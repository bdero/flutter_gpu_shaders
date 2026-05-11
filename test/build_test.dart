import 'dart:convert' as convert;

import 'package:flutter_gpu_shaders/build.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('collectShaderBundleDependencies', () {
    test('returns the manifest plus each referenced shader file', () {
      final manifestUri = Uri.parse(
        'file:///pkg/shaders/bundle.shaderbundle.json',
      );
      final manifest = convert.json.decode('''
        {
          "UnskinnedVertex": {
            "type": "vertex",
            "file": "flutter_scene_unskinned.vert"
          },
          "StandardFragment": {
            "type": "fragment",
            "file": "flutter_scene_standard.frag"
          }
        }
      ''');
      final deps = collectShaderBundleDependencies(manifestUri, manifest);
      expect(deps, [
        manifestUri,
        Uri.parse('file:///pkg/shaders/flutter_scene_unskinned.vert'),
        Uri.parse('file:///pkg/shaders/flutter_scene_standard.frag'),
      ]);
    });

    test('resolves subdirectory-relative paths against the manifest dir', () {
      final manifestUri = Uri.parse(
        'file:///pkg/shaders/bundle.shaderbundle.json',
      );
      final manifest = convert.json.decode('''
        {
          "DeepVertex": {
            "type": "vertex",
            "file": "stages/vertex/deep.vert"
          }
        }
      ''');
      final deps = collectShaderBundleDependencies(manifestUri, manifest);
      expect(deps, [
        manifestUri,
        Uri.parse('file:///pkg/shaders/stages/vertex/deep.vert'),
      ]);
    });

    test('skips entries without a string file field', () {
      final manifestUri = Uri.parse('file:///pkg/bundle.shaderbundle.json');
      // Malformed entries should not blow up; the user will see a real
      // error from impellerc when it tries to compile.
      final manifest = convert.json.decode('''
        {
          "Good":   { "type": "vertex",   "file": "good.vert" },
          "Bad":    { "type": "fragment" },
          "Ugly":   "not even a map",
          "Worse":  { "type": "vertex", "file": 42 }
        }
      ''');
      final deps = collectShaderBundleDependencies(manifestUri, manifest);
      expect(deps, [manifestUri, Uri.parse('file:///pkg/good.vert')]);
    });

    test('returns only the manifest when the decoded value is not a map', () {
      final manifestUri = Uri.parse('file:///pkg/bundle.shaderbundle.json');
      final deps = collectShaderBundleDependencies(manifestUri, '[]');
      expect(deps, [manifestUri]);
    });
  });
}
