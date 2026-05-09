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
