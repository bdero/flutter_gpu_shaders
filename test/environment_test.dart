import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_gpu_shaders/environment.dart';

void main() {
  test('findEngineArtifactsDir returns expected segments.', () {
    Uri result = findEngineArtifactsDir();
    expect(result.pathSegments.sublist(result.pathSegments.length - 5),
        ['bin', 'cache', 'artifacts', 'engine', '']);
  });

  test('findImpellerC doesn\'t throw.', () async {
    Uri result = await findImpellerC();
    expect(result.pathSegments.last, 'impellerc');
  });
}
