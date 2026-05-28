#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_source="$repo_root/test_fixtures/shader_bundle_app"
verify_build_hook_cache="${VERIFY_BUILD_HOOK_CACHE:-false}"
verify_data_assets="${VERIFY_DATA_ASSETS:-false}"
verify_direct_shader="${VERIFY_DIRECT_SHADER:-false}"
verify_transitive_include="${VERIFY_TRANSITIVE_INCLUDE:-false}"
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

if [[ "$verify_data_assets" == "true" ]]; then
  export FLUTTER_DART_DATA_ASSETS=true
fi

flutter build bundle
bundle="build/shaderbundles/test_bundle.shaderbundle"
if [[ ! -s "$bundle" ]]; then
  echo "Expected shader bundle at $bundle" >&2
  exit 1
fi

if [[ "$verify_data_assets" == "true" ]]; then
  data_asset="build/flutter_assets/packages/shader_bundle_app/flutter_gpu_shaders/shaderbundles/test_bundle.shaderbundle"
  if [[ ! -s "$data_asset" ]]; then
    echo "Expected DataAsset shader bundle at $data_asset" >&2
    find build/flutter_assets -maxdepth 5 -type f >&2
    exit 1
  fi
fi

if [[ "$verify_build_hook_cache" != "true" ]]; then
  exit 0
fi

second_build_log="$workdir/second_build.log"
flutter build bundle -v > "$second_build_log" 2>&1
if ! grep -q "Skipping target: build_hooks" "$second_build_log"; then
  echo "Expected unchanged build to skip build_hooks." >&2
  cat "$second_build_log" >&2
  exit 1
fi

if [[ "$verify_direct_shader" != "true" ]]; then
  exit 0
fi

cat > shaders/smoke.frag <<'GLSL'
#version 460 core

#include <shared_color.glsl>

out vec4 frag_color;

void main() {
  frag_color = vec4(0.4, 0.5, 0.6, 1.0);
}
GLSL

third_build_log="$workdir/third_build.log"
flutter build bundle -v > "$third_build_log" 2>&1
if ! grep -q "build_hooks: Starting due to" "$third_build_log"; then
  echo "Expected editing a directly declared shader to rerun build_hooks." >&2
  cat "$third_build_log" >&2
  exit 1
fi

if [[ ! -s "$bundle" ]]; then
  echo "Expected shader bundle at $bundle after direct shader rebuild" >&2
  exit 1
fi

if [[ "$verify_transitive_include" != "true" ]]; then
  exit 0
fi

cat > shaders/shared_color.glsl <<'GLSL'
vec4 sharedColor() {
  return vec4(0.9, 0.8, 0.7, 1.0);
}
GLSL

fourth_build_log="$workdir/fourth_build.log"
flutter build bundle -v > "$fourth_build_log" 2>&1
if ! grep -q "build_hooks: Starting due to" "$fourth_build_log"; then
  echo "Expected editing a transitive #include to rerun build_hooks." >&2
  cat "$fourth_build_log" >&2
  exit 1
fi

if [[ ! -s "$bundle" ]]; then
  echo "Expected shader bundle at $bundle after transitive include rebuild" >&2
  exit 1
fi
