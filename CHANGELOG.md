## 0.4.5

* Added optional Dart DataAssets registration for shader bundles via
  `ShaderBundleAssetMode`. The default remains legacy file output under
  `build/shaderbundles/`, while `dataAssetsIfAvailable` registers the generated
  `.shaderbundle` with the Flutter asset bundle when supported and falls back
  otherwise.
* `buildShaderBundleJson` now returns `ShaderBundleBuildResult`, including the
  legacy asset key and DataAsset/Flutter asset keys when a DataAsset is emitted.

## 0.4.4

* `buildShaderBundleJson` now consumes `impellerc` depfiles when the resolved
  compiler advertises `--depfile` support. This lets newer Flutter SDKs track
  transitive shader `#include` dependencies while preserving the existing
  manifest dependency scan for older `impellerc` builds that do not support the
  flag or do not emit a depfile in `--shader-bundle` mode.
* `buildShaderBundleJson` accepts an `includeDirectories` parameter:
  extra directories appended to `impellerc`'s `#include` search path,
  after the manifest directory and the bundled `shader_lib`. This lets a
  build hook compile shaders that `#include` reusable GLSL shipped by
  another package, by resolving that package's shader directory and
  passing it through. Files resolved this way are not auto-declared as
  build dependencies; declare them via the build output if edits to them
  should retrigger the build.
* New `shaderBundleImpellercArguments(...)` helper returns the exact
  `impellerc` argument list, exposed for inspection from custom build
  hooks and tests.

## 0.4.3

* `buildShaderBundleJson` now declares the manifest and every shader
  source file it references as build-hook dependencies. The build
  system reruns the hook (and `impellerc`) whenever any of those
  inputs change, so editing a `.frag` no longer requires a manual
  clean. Transitive `#include`s aren't tracked yet because
  `impellerc`'s `--depfile` switch is a no-op when `--shader-bundle`
  is in use; this is a known limitation pending an upstream fix.
* New `collectShaderBundleDependencies(manifestUri, decodedManifest)`
  helper returns the dependency set for inspection from custom build
  hooks and tests.

## 0.1.0

* Add `buildShaderBundleJson` build hook utility.
* Document usage instructions in the readme.

## 0.1.1

* Fix working directory for impellerc invocation.

## 0.1.2

* Fix SDK path resolution for puro users.

## 0.1.3

* Relax native_assets_cli dependency pin.

## 0.1.4

* Pin native_assets_cli to <0.9.0.
  (https://github.com/bdero/flutter_gpu_shaders/issues/3)

## 0.2.0

* Update to native_assets_cli 0.9.0.
  Breaking: `BuildOutput` is now `BuildOutputBuilder`

## 0.2.1

* Bump native_assets_cli to 0.10.0.

## 0.3.0

* Update to native_assets_cli to 0.13.0.
  (https://github.com/bdero/flutter_gpu_shaders/issues/6)
  Breaking: `BuildConfig` is now `BuildInput`

## 0.4.0

* Migrate from `native_assets_cli` (discontinued) to `hooks` 1.0. Build
  hook authors must now `import 'package:hooks/hooks.dart';` instead of
  `package:native_assets_cli/native_assets_cli.dart`.
* Bump SDK constraint to `^3.7.0` (matches `hooks` 1.0 requirements).

## 0.4.2

* `findImpellerC` now also honors a runtime `IMPELLERC` environment
  variable in addition to the compile-time define. flutter_tools
  populates this for build hook subprocesses
  (https://github.com/flutter/flutter/pull/186300), including the
  `--local-engine` case where the locally built `impellerc` should be
  used in preference to the SDK cache. Compile-time define takes
  precedence; runtime env var is checked next; otherwise the existing
  SDK cache lookup runs.

## 0.4.1

* Documentation: update `README.md` and `buildShaderBundleJson`
  dartdoc to reflect the 0.4.0 migration (drop the obsolete
  `flutter config --enable-native-assets` step, swap the import,
  and rename `buildConfig:` → `buildInput:` to match the parameter
  name introduced in 0.3.0). No code changes.
