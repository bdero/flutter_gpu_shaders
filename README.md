Build tools for Flutter GPU shader bundles/libraries.

## Features

Use native asset build hooks to import Flutter GPU shader bundle assets.

## Getting started

1. Place some Flutter GPU shaders in your project. For this example, we'll assume the existence of two shaders: `shaders/my_cool_shader.vert` and `shaders/my_cool_shader.frag`.
2. Create a shader bundle manifest file in your project. The filename must end with `.shaderbundle.json`. For this example, we'll assume the following file is saved as `my_cool_bundle.shaderbundle.json`:
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
3. Next, define a build hook in your project that builds the shader bundle using `buildShaderBundleJson`. The build hook must be named `hook/build.dart` in your project; this script will be automatically invoked by Flutter:
    ```dart
    import 'package:hooks/hooks.dart';
    import 'package:flutter_gpu_shaders/build.dart';

    void main(List<String> args) async {
      await build(args, (config, output) async {
        await buildShaderBundleJson(
            buildInput: config,
            buildOutput: output,
            manifestFileName: 'my_cool_bundle.shaderbundle.json');
      });
    }
    ```
    `buildShaderBundleJson` always declares the manifest and directly listed
    shader files as build dependencies. With Flutter SDKs whose `impellerc`
    supports `--depfile` for shader bundles, it also declares transitive
    `#include` dependencies from the generated depfile. Older `impellerc`
    builds continue to use the manifest scan fallback.
4. In your project's `pubspec.yaml`, add the built shader bundle as an asset:
    ```yaml
    flutter:
      assets:
        - build/shaderbundles/my_cool_bundle.shaderbundle
    ```
5. If your Flutter toolchain supports Dart DataAssets, you can opt in to
   registering the generated bundle with the Flutter asset bundle instead of
   listing it in `pubspec.yaml`:
    ```dart
    await buildShaderBundleJson(
      buildInput: config,
      buildOutput: output,
      manifestFileName: 'my_cool_bundle.shaderbundle.json',
      assetMode: ShaderBundleAssetMode.dataAssetsIfAvailable,
    );
    ```
   With DataAssets enabled, the result's `flutterAssetKey` is the key to pass
   to `gpu.ShaderLibrary.fromAsset`. When DataAssets are unavailable,
   `dataAssetsIfAvailable` falls back to the legacy file output. Use
   `ShaderBundleAssetMode.dataAssetsRequired` to fail fast with guidance
   instead.
6. You can now import the built shader bundle as a library using `gpu.ShaderLibrary.fromAsset` in your project. For example:
    ```dart
    import 'package:flutter_gpu/gpu.dart' as gpu;

    final String _kBaseShaderBundlePath =
        'build/shaderbundles/my_cool_bundle.shaderbundle';

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
