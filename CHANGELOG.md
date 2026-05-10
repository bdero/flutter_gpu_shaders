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
