Build tools for Flutter GPU shader bundles/libraries.

## Features

Use native asset build hooks to import Flutter GPU shader bundle assets.

## Getting started

1. This package requires the experimental "native assets" feature to be enabled. Enable it with the following command:
    ```bash
    flutter config --enable-native-assets
    ```
2. Place some Flutter GPU shaders in your project. For this example, we'll assume the existence of two shaders: `shaders/my_cool_shader.vert` and `shaders/my_cool_shader.frag`.
3. Create a shader bundle manifest file in your project. The filename must end with `.shaderbundle.json`. For this example, we'll assume the following file is saved as `my_cool_bundle.shaderbundle.json`:
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
4. Next, define a build hook in your project that builds the shader bundle using `buildShaderBundleJson`. The build hook must be named `hook/build.dart` in your project; this script will be automatically invoked by Flutter when the "native assets" feature is enabled:
    ```dart
    import 'package:native_assets_cli/native_assets_cli.dart';
    import 'package:flutter_gpu_shaders/build.dart';

    void main(List<String> args) async {
      await build(args, (config, output) async {
        await buildShaderBundleJson(
            buildConfig: config,
            buildOutput: output,
            manifestFileName: 'my_cool_bundle.shaderbundle.json');
      });
    }
    ```
5. In your project's `pubspec.yaml`, add an asset import rule to package the built shader bundles (this will become unnecessary once "native assets" supports `DataAsset` in a future release of Flutter):
    ```yaml
    flutter:
      assets:
        - build/shaderbundles/*.shaderbundle.json
    ```
6. You can now import the built shader bundle as a library using `gpu.ShaderLibrary.fromAsset` in your project. For example:
    ```dart
    import 'package:flutter_gpu/gpu.dart' as gpu;
    
    final String _kBaseShaderBundlePath =
        'packages/my_project/build/shaderbundles/my_cool_bundle.shaderbundle';
    
    gpu.ShaderLibrary? _baseShaderLibrary = null;
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