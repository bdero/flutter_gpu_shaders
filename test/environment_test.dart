import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_gpu_shaders/environment.dart';

void main() {
  test('findEngineArtifactsDir returns expected segments.', () {
    List<String> pathVariations = [
      '/path/to/flutter/bin/cache/dart-sdk/bin/dart',
      '/path/to/flutter/bin/cache/artifacts/engine/darwin-x64/flutter_tester',
      '/path/to/.puro/shared/caches/94cf8c8fad31206e440611e309757a5a9b3be712/dart-sdk/bin/dart',
    ];
    for (String path in pathVariations) {
      Uri result = findEngineArtifactsDir(dartPath: path);
      expect(result.pathSegments.sublist(result.pathSegments.length - 3),
          ['artifacts', 'engine', '']);
    }
  });

  test('findImpellerC doesn\'t throw.', () async {
    Uri result = await findImpellerC();
    expect(result.pathSegments.last, 'impellerc');
  });
}
