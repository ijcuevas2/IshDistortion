#!/usr/bin/env bash
#
# Build (and optionally clean/rebuild) the Distortion LV2/VST3/Standalone
# plugin. COPY_PLUGIN_AFTER_BUILD is enabled in CMakeLists.txt, so a
# successful build also installs the LV2 bundle to ~/.lv2 and the VST3 to
# ~/.vst3 automatically - nothing further to do for guitarix to pick it up.
#
# Usage:
#   ./build.sh              # configure (if needed) + build, Release
#   ./build.sh --debug      # build a Debug configuration instead
#   ./build.sh --clean      # wipe the build/ dir first, then configure+build
#   ./build.sh -j4          # cap parallel build jobs (default: all cores)

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

build_dir="build"
build_type="Release"
jobs="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
clean=0

for arg in "$@"; do
    case "$arg" in
        --debug)   build_type="Debug" ;;
        --release) build_type="Release" ;;
        --clean)   clean=1 ;;
        -j*)       jobs="${arg#-j}" ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

if [[ "$clean" -eq 1 ]]; then
    echo "Removing $build_dir/"
    rm -rf "$build_dir"
fi

echo "Configuring ($build_type)..."
cmake -B "$build_dir" -DCMAKE_BUILD_TYPE="$build_type"

echo "Building with $jobs job(s)..."
cmake --build "$build_dir" --config "$build_type" -j"$jobs"

artefacts="$build_dir/Distortion_artefacts/$build_type"
product_name="Ish Distortion" # keep in sync with PRODUCT_NAME in CMakeLists.txt
echo
echo "Done. Artefacts:"
echo "  LV2:        $artefacts/LV2/$product_name.lv2  (also installed to ~/.lv2)"
echo "  VST3:       $artefacts/VST3/$product_name.vst3 (also installed to ~/.vst3)"
echo "  Standalone: $artefacts/Standalone/$product_name"
