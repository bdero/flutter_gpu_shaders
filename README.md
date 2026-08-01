Build tools for Flutter GPU shader bundles/libraries.

## Features

Use build hooks to compile Flutter GPU shaders and register the resulting
bundle as a managed Dart DataAsset.

## Getting started

1. Enable Dart DataAssets once for your Flutter SDK.

    ```sh
    flutter config --enable-dart-data-assets
    ```

2. Place Flutter GPU shader sources in your project. This example uses
   `shaders/my_cool_shader.vert` and `shaders/my_cool_shader.frag`.

3. Create a source manifest named `my_cool_bundle.shaderbundle.json`.

    ```json
    {
        "CoolVertex": {
            "type": "vertex",
            "file": "shaders/my_cool_shader.vert"
        },
        "CoolFragment": {
            "type": "fragment",
            "file": "shaders/my_cool_shader.frag"
        }
    }
    ```

    The manifest and shader sources are portable build inputs and belong in
    version control. The generated `.shaderbundle` is compiled by the active
    Flutter engine's `impellerc`. It is an engine-coupled intermediary and must
    not be committed.

4. Define `hook/build.dart` and register the generated bundle as a required
   DataAsset.

    ```dart
    import 'package:hooks/hooks.dart';
    import 'package:flutter_gpu_shaders/build.dart';

    void main(List<String> args) async {
      await build(args, (config, output) async {
        await buildShaderBundleJson(
          buildInput: config,
          buildOutput: output,
          manifestFileName: 'my_cool_bundle.shaderbundle.json',
          assetMode: ShaderBundleAssetMode.dataAssetsRequired,
        );
      });
    }
    ```

    The hook declares the manifest and directly listed shader files as build
    dependencies. With Flutter SDKs whose `impellerc` supports `--depfile` for
    shader bundles, it also declares transitive `#include` dependencies.

5. Load the DataAsset using its Flutter asset key. The default key is
   `packages/<package>/flutter_gpu_shaders/shaderbundles/<bundle>.shaderbundle`.

    ```dart
    import 'package:flutter_gpu/gpu.dart' as gpu;

    final String _kBaseShaderBundlePath =
        'packages/my_app/flutter_gpu_shaders/shaderbundles/'
        'my_cool_bundle.shaderbundle';

    gpu.ShaderLibrary? _baseShaderLibrary;
    gpu.ShaderLibrary get baseShaderLibrary {
      if (_baseShaderLibrary != null) {
        return _baseShaderLibrary!;
      }
      _baseShaderLibrary = gpu.ShaderLibrary.fromAsset(_kBaseShaderBundlePath);
      if (_baseShaderLibrary != null) {
        return _baseShaderLibrary!;
      }

      throw Exception(
          "Failed to load base shader bundle! ($_kBaseShaderBundlePath)");
    }
    ```

Do not list generated shader bundles in `flutter.assets`.
`ShaderBundleAssetMode.legacyOnly` and `dataAssetsIfAvailable` remain available
for older Flutter toolchains. They emit a warning when the generated bundle is
not managed as a DataAsset.
