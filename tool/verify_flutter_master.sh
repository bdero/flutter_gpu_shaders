#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_source="$repo_root/test_fixtures/shader_bundle_app"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

fixture="$workdir/shader_bundle_app"
cp -R "$fixture_source" "$fixture"

cat > "$fixture/pubspec_overrides.yaml" <<YAML
dependency_overrides:
  flutter_gpu_shaders:
    path: "$repo_root"
YAML

cd "$fixture"

flutter --version
flutter pub get

flutter build bundle
bundle="build/shaderbundles/test_bundle.shaderbundle"
if [[ ! -s "$bundle" ]]; then
  echo "Expected shader bundle at $bundle" >&2
  exit 1
fi

second_build_log="$workdir/second_build.log"
flutter build bundle -v > "$second_build_log" 2>&1
if ! grep -q "Skipping target: build_hooks" "$second_build_log"; then
  echo "Expected unchanged build to skip build_hooks." >&2
  cat "$second_build_log" >&2
  exit 1
fi

cat > shaders/shared_color.glsl <<'GLSL'
vec4 sharedColor() {
  return vec4(0.9, 0.8, 0.7, 1.0);
}
GLSL

third_build_log="$workdir/third_build.log"
flutter build bundle -v > "$third_build_log" 2>&1
if ! grep -q "build_hooks: Starting due to" "$third_build_log"; then
  echo "Expected editing a transitive #include to rerun build_hooks." >&2
  cat "$third_build_log" >&2
  exit 1
fi

if [[ ! -s "$bundle" ]]; then
  echo "Expected shader bundle at $bundle after rebuild" >&2
  exit 1
fi
