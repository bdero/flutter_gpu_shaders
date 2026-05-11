library flutter_gpu_shaders;

import 'dart:convert' as convert;
import 'dart:io';

import 'package:hooks/hooks.dart';

import 'package:flutter_gpu_shaders/environment.dart';

/// Loads a shader bundle manifest file and builds a shader bundle.
Future<void> _buildShaderBundleJson({
  required Uri packageRoot,
  required Uri inputManifestFilePath,
  required Uri outputBundleFilePath,
  required BuildOutputBuilder buildOutput,
}) async {
  /////////////////////////////////////////////////////////////////////////////
  /// 1. Parse the manifest file.
  ///

  final manifest =
      await File(inputManifestFilePath.toFilePath()).readAsString();
  final decodedManifest = convert.json.decode(manifest);
  String reconstitutedManifest = convert.json.encode(decodedManifest);

  /////////////////////////////////////////////////////////////////////////////
  /// 2. Declare build-system dependencies.
  ///
  /// The build hook needs to rerun when any input that influences the
  /// produced shader bundle changes. We track the manifest itself and
  /// every shader source file it references. The build hook framework
  /// reruns this hook the next time any listed dependency's mtime
  /// changes.
  ///
  /// Transitive `#include`s aren't tracked yet. `impellerc`'s
  /// `--depfile` switch (which would let us capture them) is a no-op
  /// in `--shader-bundle` mode today; that's filed as an upstream
  /// follow-up.

  buildOutput.dependencies.addAll(
    collectShaderBundleDependencies(inputManifestFilePath, decodedManifest),
  );

  /////////////////////////////////////////////////////////////////////////////
  /// 3. Build the shader bundle.
  ///

  final impellercExec = await findImpellerC();
  final shaderLibPath = impellercExec.resolve('./shader_lib');
  final impellercArgs = [
    '--sl=${outputBundleFilePath.toFilePath()}',
    '--shader-bundle=$reconstitutedManifest',
    '--include=${inputManifestFilePath.resolve('./').toFilePath()}',
    '--include=${shaderLibPath.toFilePath()}',
  ];

  final impellerc = Process.runSync(
    impellercExec.toFilePath(),
    impellercArgs,
    workingDirectory: packageRoot.toFilePath(),
  );
  if (impellerc.exitCode != 0) {
    throw Exception(
      'Failed to build shader bundle: ${impellerc.stderr}\n${impellerc.stdout}',
    );
  }
}

/// Collects the build-system dependencies declared by a shader bundle
/// manifest.
///
/// Returns the manifest URI itself plus the resolved URI of every
/// shader source file referenced by a top-level entry's `file` key.
/// Paths in the manifest are interpreted relative to the manifest's
/// containing directory.
///
/// Exposed so users authoring custom build hooks (and tests) can
/// inspect the same dependency set [buildShaderBundleJson] declares.
List<Uri> collectShaderBundleDependencies(
  Uri manifestUri,
  Object decodedManifest,
) {
  final manifestDir = manifestUri.resolve('./');
  final result = <Uri>[manifestUri];
  if (decodedManifest is! Map) {
    return result;
  }
  for (final value in decodedManifest.values) {
    if (value is! Map) continue;
    final file = value['file'];
    if (file is! String) continue;
    result.add(manifestDir.resolve(file));
  }
  return result;
}

/// Build a Flutter GPU shader bundle/library from a JSON manifest file.
///
/// The [buildInput] and [buildOutput] are provided by the build hook system.
///
/// The [manifestFileName] is the path to the JSON manifest file, which is
/// relative to the package root where the build hook resides.
///
/// The [manifestFileName] must end with ".shaderbundle.json".
///
/// The built shader bundle will be written to
/// `build/shaderbundles/[name].shaderbundle`,
/// relative to the package root where the build hook resides.
///
/// The hook declares the manifest and every shader source file it
/// references as build-system dependencies, so the bundle is rebuilt
/// when any input changes.
///
/// Example usage:
///
/// hook/build.dart
/// ```dart
/// import 'package:hooks/hooks.dart';
/// import 'package:flutter_gpu_shaders/build.dart';
///
/// void main(List<String> args) async {
///   await build(args, (config, output) async {
///     await buildShaderBundleJson(
///         buildInput: config,
///         buildOutput: output,
///         manifestFileName: 'my_cool_bundle.shaderbundle.json');
///   });
/// }
/// ```
///
/// my_cool_bundle.shaderbundle.json
/// ```json
/// {
///     "SimpleVertex": {
///         "type": "vertex",
///         "file": "shaders/my_cool_shader.vert"
///     }
/// }
/// ```
Future<void> buildShaderBundleJson({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  required String manifestFileName,
}) async {
  String outputFileName = Uri(path: manifestFileName).pathSegments.last;
  if (!outputFileName.endsWith('.shaderbundle.json')) {
    throw Exception(
      'Shader bundle manifest file names must end with ".shaderbundle.json".',
    );
  }
  if (outputFileName.length <= '.shaderbundle.json'.length) {
    throw Exception(
      'Invalid shader bundle manifest file name: $outputFileName',
    );
  }
  if (outputFileName.endsWith('.json')) {
    outputFileName = outputFileName.substring(0, outputFileName.length - 5);
  }

  // TODO(bdero): Migrate to writing to `buildInput.outputDirectory` and
  // registering the produced bundle as a DataAsset via
  // `output.assets.data.add(DataAsset(...))`. Tracked at
  // https://github.com/bdero/flutter_scene/issues/106. Blocked on the
  // `dartDataAssets` feature flipping to `enabledByDefault: true` in
  // flutter_tools (currently `available: true` on master, so consumers
  // would need a `flutter config --enable-dart-data-assets` step).
  final outDir = Directory.fromUri(
    buildInput.packageRoot.resolve('build/shaderbundles/'),
  );
  await outDir.create(recursive: true);
  final packageRoot = buildInput.packageRoot;

  final inFile = packageRoot.resolve(manifestFileName);
  final outFile = outDir.uri.resolve(outputFileName);

  await _buildShaderBundleJson(
    packageRoot: packageRoot,
    inputManifestFilePath: inFile,
    outputBundleFilePath: outFile,
    buildOutput: buildOutput,
  );
}
