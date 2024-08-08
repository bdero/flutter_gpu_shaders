library flutter_gpu_shaders;

import 'dart:io';

import 'package:flutter_gpu_shaders/base.dart';

const _macosHostArtifacts = 'darwin-x64';
const _linuxHostArtifacts = 'linux-x64';
const _windowsHostArtifacts = 'windows-x64';

const _impellercLocations = [
  '$_macosHostArtifacts/impellerc',
  '$_linuxHostArtifacts/impellerc',
  '$_windowsHostArtifacts/impellerc.exe',
];

/// Locate the engine artifacts cache directory in the Flutter SDK.
Uri findEngineArtifactsDir({String? dartPath}) {
  // Could be:
  //   `/path/to/flutter/bin/cache/dart-sdk/bin/dart`
  //   `/path/to/flutter/bin/cache/artifacts/engine/darwin-x64/flutter_tester`
  //   `/path/to/.puro/shared/caches/94cf8c8fad31206e440611e309757a5a9b3be712/dart-sdk/bin/dart`
  final Uri dartExec = Uri.file(dartPath ?? Platform.resolvedExecutable);
  logger.info('Dart executable: `${dartExec.toFilePath()}`');

  Uri? cacheDir;
  // Search backwards through the segment list until finding `bin` and `cache` in sequence.
  for (var i = dartExec.pathSegments.length - 1; i >= 0; i--) {
    if (dartExec.pathSegments[i] == 'dart-sdk' ||
        dartExec.pathSegments[i] == 'artifacts') {
      // Note: The final empty string denotes that this is a directory path.
      cacheDir = dartExec.replace(
          pathSegments: dartExec.pathSegments.sublist(0, i) + ['']);
      break;
    }
  }
  if (cacheDir == null) {
    throw Exception(
        'Unable to find Flutter SDK cache directory! Dart executable: `${dartExec.toFilePath()}`');
  }
  // We should now have a path of `/path/to/flutter/bin/cache/`.

  final engineArtifactsDir = cacheDir
      .resolve('./artifacts/engine/'); // Note: The final slash is important.
  logger.info(
      'Flutter SDK cache directory: `${engineArtifactsDir.toFilePath()}`');

  return engineArtifactsDir;
}

/// Locate the ImpellerC offline shader compiler in the engine artifacts cach
/// directory.
Future<Uri> findImpellerC() async {
  /////////////////////////////////////////////////////////////////////////////
  /// 1. If the `IMPELLERC` environment variable is set, use it.
  ///

  const impellercEnvVar = String.fromEnvironment('IMPELLERC', defaultValue: '');
  if (impellercEnvVar != '') {
    logger.info('IMPELLERC environment variable: `$impellercEnvVar`');
    if (!await File(impellercEnvVar).exists()) {
      throw Exception(
          'IMPELLERC environment variable is set, but it doesn\'t point to a valid file!');
    }
    return Uri.file(impellercEnvVar);
  }

  /////////////////////////////////////////////////////////////////////////////
  /// 3. Search for the `impellerc` binary within the host-specific artifacts.
  ///

  Uri engineArtifactsDir = findEngineArtifactsDir();

  // No need to get fancy. Just search all the possible directories rather than
  // picking the correct one for the specific host type.
  Uri? found;
  List<Uri> tried = [];
  logger.info('Searching for impellerc in artifacts directories...');
  for (final variant in _impellercLocations) {
    logger.info('  Checking `$variant`...');
    final impellercPath = engineArtifactsDir.resolve(variant);
    if (await File(impellercPath.toFilePath()).exists()) {
      found = impellercPath;
      break;
    }
    tried.add(impellercPath);
  }
  if (found == null) {
    throw Exception(
        'Unable to find impellerc! Tried the following locations: $tried');
  }

  return found;
}
