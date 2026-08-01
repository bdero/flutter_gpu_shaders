import 'dart:convert' as convert;
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:data_assets/data_assets.dart';
import 'package:hooks/hooks.dart';

import 'package:flutter_gpu_shaders/environment.dart';

/// Controls whether [buildShaderBundleJson] registers the produced shader
/// bundle as a Dart DataAsset.
enum ShaderBundleAssetMode {
  /// Preserve the historical behavior: only write
  /// `build/shaderbundles/[name].shaderbundle`.
  legacyOnly,

  /// Register a DataAsset when the current Flutter/Dart build supports data
  /// assets, and otherwise silently fall back to [legacyOnly].
  dataAssetsIfAvailable,

  /// Require DataAssets support and fail the build with a targeted error when
  /// the current toolchain did not request data assets from the hook.
  dataAssetsRequired,
}

/// Information about a shader bundle produced by [buildShaderBundleJson].
final class ShaderBundleBuildResult {
  const ShaderBundleBuildResult({
    required this.outputFile,
    required this.legacyAssetKey,
    this.dataAssetName,
    this.dataAssetId,
    this.flutterAssetKey,
  });

  /// Absolute file URI of the generated `.shaderbundle`.
  final Uri outputFile;

  /// Historical Flutter asset key for projects listing the generated file in
  /// `flutter.assets`.
  final String legacyAssetKey;

  /// DataAsset name registered for the generated bundle, when one was emitted.
  final String? dataAssetName;

  /// DataAsset package identifier, e.g.
  /// `package:my_app/flutter_gpu_shaders/shaderbundles/materials.shaderbundle`.
  final String? dataAssetId;

  /// Flutter asset-bundle key for the DataAsset, when one was emitted.
  ///
  /// Flutter currently exposes DataAssets through the normal asset bundle under
  /// `packages/<package>/<name>`.
  final String? flutterAssetKey;
}

/// Returns the default DataAsset name for a generated shader bundle.
String shaderBundleDataAssetName(String bundleFileName) =>
    'flutter_gpu_shaders/shaderbundles/$bundleFileName';

/// Returns the Flutter asset-bundle key for a DataAsset.
String flutterDataAssetKey({required String package, required String name}) =>
    'packages/$package/$name';

/// Registers [outputBundleFile] as a DataAsset when [assetMode] allows it.
///
/// Returns the emitted asset metadata, or `null` when [assetMode] falls back to
/// legacy output because data assets are not available.
/// Set [warnIfLegacy] to `false` only when a higher-level hook registers the
/// generated bundle itself.
ShaderBundleBuildResult? registerShaderBundleDataAsset({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  required Uri outputBundleFile,
  required String legacyAssetKey,
  required ShaderBundleAssetMode assetMode,
  String? dataAssetName,
  bool warnIfLegacy = true,
}) {
  if (assetMode == ShaderBundleAssetMode.legacyOnly) {
    if (warnIfLegacy) {
      // ignore: avoid_print
      print(
        'flutter_gpu_shaders warning, using legacy generated assets for '
        '"$legacyAssetKey". Shader bundles are tied to the active Flutter '
        'engine. Use ShaderBundleAssetMode.dataAssetsRequired instead of '
        'committing generated bundles or listing them in flutter.assets.',
      );
    }
    return null;
  }
  final dataAssetsAvailable = buildInput.config.buildDataAssets;
  if (!dataAssetsAvailable) {
    if (assetMode == ShaderBundleAssetMode.dataAssetsRequired) {
      _throwDataAssetsUnavailable(legacyAssetKey);
    }
    // ignore: avoid_print
    print(
      'flutter_gpu_shaders warning, Dart DataAssets are unavailable, so '
      '"$legacyAssetKey" was not '
      'registered as a managed asset. Enable DataAssets or use '
      'ShaderBundleAssetMode.dataAssetsRequired to fail instead.',
    );
    return null;
  }

  final name =
      dataAssetName ??
      shaderBundleDataAssetName(legacyAssetKey.split('/').last);
  final asset = DataAsset(
    package: buildInput.packageName,
    name: name,
    file: outputBundleFile,
  );
  buildOutput.assets.data.add(asset);
  return ShaderBundleBuildResult(
    outputFile: outputBundleFile,
    legacyAssetKey: legacyAssetKey,
    dataAssetName: name,
    dataAssetId: asset.id,
    flutterAssetKey: flutterDataAssetKey(
      package: buildInput.packageName,
      name: name,
    ),
  );
}

Never _throwDataAssetsUnavailable(String legacyAssetKey) {
  throw UnsupportedError(
    'Dart DataAssets were requested for "$legacyAssetKey", but this Flutter '
    'build did not enable data assets for hooks. DataAssets are currently '
    'experimental and require a Flutter toolchain that supports the Dart data '
    'assets feature. On supported Flutter master builds, run '
    '`flutter config --enable-dart-data-assets` or set '
    '`FLUTTER_DART_DATA_ASSETS=true`, then rebuild. Otherwise use '
    'ShaderBundleAssetMode.legacyOnly and list "$legacyAssetKey" in '
    'flutter.assets.',
  );
}

/// Loads a shader bundle manifest file and builds a shader bundle.
Future<void> _buildShaderBundleJson({
  required Uri packageRoot,
  required Uri inputManifestFilePath,
  required Uri outputBundleFilePath,
  required BuildOutputBuilder buildOutput,
  required List<Uri> includeDirectories,
  int? glesLanguageVersion,
}) async {
  /////////////////////////////////////////////////////////////////////////////
  /// 1. Parse the manifest file.
  ///

  final manifest = await File(
    inputManifestFilePath.toFilePath(),
  ).readAsString();
  final decodedManifest = convert.json.decode(manifest);
  String reconstitutedManifest = convert.json.encode(decodedManifest);

  /////////////////////////////////////////////////////////////////////////////
  /// 2. Declare build-system dependencies.
  ///
  /// The build hook needs to rerun when any input that influences the
  /// produced shader bundle changes. We track the manifest itself and
  /// every shader source file it references before invoking `impellerc`,
  /// so older compilers still get the same dependency tracking as previous
  /// package versions. Newer compilers also emit a depfile that captures
  /// transitive `#include`s; those dependencies are merged after a
  /// successful compile.

  final dependencies = collectShaderBundleDependencies(
    inputManifestFilePath,
    decodedManifest,
    packageRoot: packageRoot,
  );

  /////////////////////////////////////////////////////////////////////////////
  /// 3. Build the shader bundle.
  ///

  final impellercExec = await findImpellerC();
  final shaderLibPath = impellercExec.resolve('./shader_lib');
  final depfilePath = Uri.file('${outputBundleFilePath.toFilePath()}.d');
  final depfile = File.fromUri(depfilePath);
  final supportsDepfile = impellerCHelpSupportsDepfile(
    _impellerCHelpText(impellercExec),
  );
  if (supportsDepfile && await depfile.exists()) {
    await depfile.delete();
  }
  final impellercArgs = shaderBundleImpellercArguments(
    outputBundleFilePath: outputBundleFilePath,
    manifestJson: reconstitutedManifest,
    manifestDirectory: inputManifestFilePath.resolve('./'),
    shaderLibDirectory: shaderLibPath,
    includeDirectories: includeDirectories,
    depfilePath: supportsDepfile ? depfilePath : null,
    glesLanguageVersion: glesLanguageVersion,
  );

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

  if (supportsDepfile && await depfile.exists()) {
    final depfileContents = await depfile.readAsString();
    dependencies.addAll(
      parseImpellerCDepfileDependencies(
        depfileContents,
        relativeTo: packageRoot,
      ),
    );
    await depfile.delete();
  }

  // The produced bundle is tied to the engine build that supplied `impellerc`
  // (the compiler ships in lockstep with the engine artifacts), so the
  // compiler binary is a build input like any shader source. Content-hashing
  // it reruns this hook on engine changes that the Dart SDK version alone
  // does not reveal.
  dependencies.add(impellercExec);

  // Declare the collected dependencies, excluding anything under the package's
  // `build/` output directory. Generated shaders (for example synthesized from
  // another format and written into `build/`) are rewritten on every build, so
  // depending on them would make the hook re-run on every build. The real
  // sources that produced them should be declared by their own producer.
  final buildDirectory = packageRoot
      .resolve('build/')
      .toFilePath(windows: false);
  buildOutput.dependencies.addAll(
    dependencies.where(
      (uri) => !uri.toFilePath(windows: false).startsWith(buildDirectory),
    ),
  );

  // The output path is shared through the pub cache, so another project
  // (possibly on a different Flutter SDK) can rewrite the same bundle file
  // with a different `impellerc`. The stamp records which compiler last wrote
  // the bundle; declaring it as a dependency turns such a rewrite into a hash
  // mismatch that reruns this hook. Declared after the `build/` filter above
  // because the stamp deliberately lives next to the bundle.
  final stampUri = engineStampUriForBundle(outputBundleFilePath);
  await writeEngineStampIfChanged(
    stampUri: stampUri,
    impellercExec: impellercExec,
    glesLanguageVersion: glesLanguageVersion,
  );
  buildOutput.dependencies.add(stampUri);
}

/// The engine-stamp path for a shader bundle at [outputBundleFilePath].
Uri engineStampUriForBundle(Uri outputBundleFilePath) =>
    Uri.file('${outputBundleFilePath.toFilePath()}.engine_stamp.json');

/// JSON stamp identifying the compiler configuration a bundle was built with.
Future<String> engineStampJson({
  required Uri impellercExec,
  int? glesLanguageVersion,
}) async {
  final digest = crypto.sha256.convert(
    await File.fromUri(impellercExec).readAsBytes(),
  );
  return convert.json.encode({
    'impellerc_sha256': digest.toString(),
    'gles_language_version': ?glesLanguageVersion,
  });
}

/// Writes the engine stamp for [impellercExec] to [stampUri], skipping the
/// write when the on-disk content already matches.
///
/// Skipping matters because hook runners flag any tracked file modified
/// during the build and would otherwise rerun the hook on every build. For
/// the same reason a genuine rewrite backdates the stamp's mtime; change
/// detection is content-hash based, so the mtime carries no information.
Future<void> writeEngineStampIfChanged({
  required Uri stampUri,
  required Uri impellercExec,
  int? glesLanguageVersion,
}) async {
  final contents = await engineStampJson(
    impellercExec: impellercExec,
    glesLanguageVersion: glesLanguageVersion,
  );
  final file = File.fromUri(stampUri);
  if (await file.exists() && await file.readAsString() == contents) {
    return;
  }
  await file.writeAsString(contents);
  try {
    file.setLastModifiedSync(DateTime.utc(2000));
  } on FileSystemException {
    // Backdating is best-effort; without it the runner reruns the hook once
    // more before the stamp settles.
  }
}

String _impellerCHelpText(Uri impellercExec) {
  final result = Process.runSync(impellercExec.toFilePath(), ['--help']);
  if (result.exitCode != 0) {
    return '';
  }
  return '${result.stdout}\n${result.stderr}';
}

/// Collects the build-system dependencies declared by a shader bundle
/// manifest.
///
/// Returns the manifest URI itself plus the resolved URI of every
/// shader source file referenced by a top-level entry's `file` key.
/// Entry `file` paths are interpreted relative to [packageRoot], matching how
/// `impellerc` resolves them (it runs with the package root as its working
/// directory). Resolving them against the manifest's directory instead would
/// produce paths that do not exist when the manifest lives in a subdirectory.
///
/// Exposed so users authoring custom build hooks (and tests) can
/// inspect the same dependency set [buildShaderBundleJson] declares.
List<Uri> collectShaderBundleDependencies(
  Uri manifestUri,
  Object decodedManifest, {
  required Uri packageRoot,
}) {
  final result = <Uri>[manifestUri];
  if (decodedManifest is! Map) {
    return result;
  }
  for (final value in decodedManifest.values) {
    if (value is! Map) continue;
    final file = value['file'];
    if (file is! String) continue;
    result.add(packageRoot.resolve(file));
  }
  return result;
}

/// Returns whether the `impellerc --help` text advertises `--depfile`.
///
/// Older `impellerc` builds either omit the flag entirely or accept it without
/// producing a depfile in `--shader-bundle` mode. Build hooks use this helper
/// to avoid passing an unsupported flag while preserving the existing manifest
/// dependency fallback.
bool impellerCHelpSupportsDepfile(String helpText) {
  return helpText.contains('--depfile=');
}

/// Parses dependency paths from an `impellerc` depfile.
///
/// `impellerc` emits a Ninja-style single-line depfile:
/// `<target>: <dep1> <dep2> ...`. The target is ignored. Dependency paths are
/// converted to file URIs; relative paths are resolved against [relativeTo]
/// when it is provided.
List<Uri> parseImpellerCDepfileDependencies(
  String depfileContents, {
  Uri? relativeTo,
}) {
  final separator = RegExp(r':(?:\s|$)').firstMatch(depfileContents);
  if (separator == null) {
    return const [];
  }
  final dependencies = depfileContents.substring(separator.end).trim();
  if (dependencies.isEmpty) {
    return const [];
  }
  return dependencies
      .split(RegExp(r'\s+'))
      .where((dependency) => dependency.isNotEmpty)
      .map((dependency) {
        if (_isAbsoluteFilePath(dependency)) {
          return Uri.file(dependency);
        }
        return relativeTo?.resolve(dependency) ?? Uri.file(dependency);
      })
      .toList();
}

bool _isAbsoluteFilePath(String path) {
  return path.startsWith('/') || RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(path);
}

/// Builds the `impellerc` argument list for a shader-bundle compile.
///
/// The first two `--include` directories are always the manifest's own
/// directory and `impellerc`'s bundled `shader_lib`. Any [includeDirectories]
/// are appended after them, so a package that ships reusable GLSL (for example
/// framework shaders that generated bundles `#include`) can put its shader
/// directory on the search path.
///
/// Exposed so users authoring custom build hooks (and tests) can inspect the
/// exact arguments [buildShaderBundleJson] passes to `impellerc`.
List<String> shaderBundleImpellercArguments({
  required Uri outputBundleFilePath,
  required String manifestJson,
  required Uri manifestDirectory,
  required Uri shaderLibDirectory,
  List<Uri> includeDirectories = const [],
  Uri? depfilePath,
  int? glesLanguageVersion,
}) {
  return [
    '--sl=${outputBundleFilePath.toFilePath()}',
    '--shader-bundle=$manifestJson',
    if (depfilePath != null) '--depfile=${depfilePath.toFilePath()}',
    if (glesLanguageVersion != null)
      '--gles-language-version=$glesLanguageVersion',
    '--include=${manifestDirectory.toFilePath()}',
    '--include=${shaderLibDirectory.toFilePath()}',
    for (final directory in includeDirectories)
      '--include=${directory.toFilePath()}',
  ];
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
/// when any input changes. When the resolved `impellerc` supports
/// `--depfile` in `--shader-bundle` mode, the hook also declares transitive
/// `#include` dependencies from the generated depfile. Older `impellerc`
/// builds fall back to the manifest scan.
///
/// The optional [includeDirectories] are added to `impellerc`'s `#include`
/// search path, after the manifest's directory and `impellerc`'s built-in
/// `shader_lib`. Use this to compile shaders that `#include` reusable GLSL
/// shipped by another package: resolve that package's shader directory and
/// pass it here. Files resolved through these directories are not declared as
/// dependencies automatically; add them via [buildOutput] if edits to them
/// should retrigger the build.
///
/// The optional [glesLanguageVersion] is forwarded to `impellerc` as
/// `--gles-language-version` and selects the GLSL ES version of the bundle's
/// OpenGL ES shaders (for example `300` emits `#version 300 es`, where
/// `textureLod` and friends are core rather than extensions). When omitted,
/// `impellerc` defaults to GLSL ES 1.00.
///
/// Set [assetMode] to [ShaderBundleAssetMode.dataAssetsRequired] for new
/// applications. This registers the generated `.shaderbundle` as a managed
/// DataAsset and fails early with setup guidance when DataAssets are
/// unavailable. The generated bundle is tied to the active Flutter engine and
/// must not be committed or listed in `flutter.assets`.
///
/// [ShaderBundleAssetMode.legacyOnly] preserves the historical behavior and
/// [ShaderBundleAssetMode.dataAssetsIfAvailable] falls back to it when
/// DataAssets are unavailable. Both fallback paths emit a migration warning.
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
///         manifestFileName: 'my_cool_bundle.shaderbundle.json',
///         assetMode: ShaderBundleAssetMode.dataAssetsRequired);
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
Future<ShaderBundleBuildResult> buildShaderBundleJson({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  required String manifestFileName,
  List<Uri> includeDirectories = const [],
  ShaderBundleAssetMode assetMode = ShaderBundleAssetMode.legacyOnly,
  String? dataAssetName,
  int? glesLanguageVersion,
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

  final outDir = Directory.fromUri(
    buildInput.packageRoot.resolve('build/shaderbundles/'),
  );
  await outDir.create(recursive: true);
  final packageRoot = buildInput.packageRoot;

  final inFile = packageRoot.resolve(manifestFileName);
  final outFile = outDir.uri.resolve(outputFileName);
  final legacyAssetKey = 'build/shaderbundles/$outputFileName';

  if (assetMode == ShaderBundleAssetMode.dataAssetsRequired &&
      !buildInput.config.buildDataAssets) {
    _throwDataAssetsUnavailable(legacyAssetKey);
  }

  await _buildShaderBundleJson(
    packageRoot: packageRoot,
    inputManifestFilePath: inFile,
    outputBundleFilePath: outFile,
    buildOutput: buildOutput,
    includeDirectories: includeDirectories,
    glesLanguageVersion: glesLanguageVersion,
  );

  return registerShaderBundleDataAsset(
        buildInput: buildInput,
        buildOutput: buildOutput,
        outputBundleFile: outFile,
        legacyAssetKey: legacyAssetKey,
        assetMode: assetMode,
        dataAssetName: dataAssetName,
        // Generated manifests are owned by a higher-level hook that registers
        // the final bundle and sidecars itself.
        warnIfLegacy: !manifestFileName.startsWith('build/'),
      ) ??
      ShaderBundleBuildResult(
        outputFile: outFile,
        legacyAssetKey: legacyAssetKey,
      );
}
