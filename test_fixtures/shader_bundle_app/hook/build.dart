import 'package:flutter_gpu_shaders/build.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildShaderBundleJson(
      buildInput: input,
      buildOutput: output,
      manifestFileName: 'test_bundle.shaderbundle.json',
      includeDirectories: [input.packageRoot.resolve('shaders/')],
    );
  });
}
