library flutter_gpu_shaders;

import 'dart:convert' as convert;
import 'dart:io';

import 'package:native_assets_cli/code_assets_testing.dart';
import 'package:native_assets_cli/native_assets_cli.dart';

import 'package:flutter_gpu_shaders/environment.dart';

/// Loads a shader bundle manifest file and builds a shader bundle.
Future<void> _buildShaderBundleJson({
  required Uri packageRoot,
  required Uri inputManifestFilePath,
  required Uri outputBundleFilePath,
}) async {
  /////////////////////////////////////////////////////////////////////////////
  /// 1. Parse the manifest file.
  ///

  final manifest =
      await File(inputManifestFilePath.toFilePath()).readAsString();
  final decodedManifest = convert.json.decode(manifest);
  String reconstitutedManifest = convert.json.encode(decodedManifest);

  //throw Exception(reconstitutedManifest);

  /////////////////////////////////////////////////////////////////////////////
  /// 2. Build the shader bundle.
  ///

  final impellercExec = await findImpellerC();
  final shaderLibPath = impellercExec.resolve('./shader_lib');
  final impellercArgs = [
    '--sl=${outputBundleFilePath.toFilePath()}',
    '--shader-bundle=$reconstitutedManifest',
    '--include=${inputManifestFilePath.resolve('./').toFilePath()}',
    '--include=${shaderLibPath.toFilePath()}',
  ];

  final impellerc = Process.runSync(impellercExec.toFilePath(), impellercArgs,
      workingDirectory: packageRoot.toFilePath());
  if (impellerc.exitCode != 0) {
    throw Exception(
        'Failed to build shader bundle: ${impellerc.stderr}\n${impellerc.stdout}');
  }
}

/// Build a Flutter GPU shader bundle/library from a JSON manifest file.
///
/// The [buildConfig] and [buildOutput] are provided by the build hook system.
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
/// Example usage:
///
/// hook/build.dart
/// ```dart
/// void main(List<String> args) async {
///   await build(args, (config, output) async {
///     await buildShaderBundleJson(
///         buildConfig: config,
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
Future<void> buildShaderBundleJson(
    {required BuildInput buildInput,
    required BuildOutputBuilder buildOutput,
    required String manifestFileName}) async {
  String outputFileName = Uri(path: manifestFileName).pathSegments.last;
  if (!outputFileName.endsWith('.shaderbundle.json')) {
    throw Exception(
        'Shader bundle manifest file names must end with ".shaderbundle.json".');
  }
  if (outputFileName.length <= '.shaderbundle.json'.length) {
    throw Exception(
        'Invalid shader bundle manifest file name: $outputFileName');
  }
  if (outputFileName.endsWith('.json')) {
    outputFileName = outputFileName.substring(0, outputFileName.length - 5);
  }

  // TODO(bdero): Register DataAssets instead of outputting to the project directory once it's possible to do so.
  //final outDir = config.outputDirectory;
  final outDir = Directory.fromUri(
      buildInput.packageRoot.resolve('build/shaderbundles/'));
  await outDir.create(recursive: true);
  final packageRoot = buildInput.packageRoot;

  final inFile = packageRoot.resolve(manifestFileName);
  final outFile = outDir.uri.resolve(outputFileName);

  await _buildShaderBundleJson(
      packageRoot: packageRoot,
      inputManifestFilePath: inFile,
      outputBundleFilePath: outFile);
}
