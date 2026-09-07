#!/usr/bin/env bash
#
# Build (and install) the Ish Distortion LV2/VST3/JACK-standalone plugin.
#
# Unlike the JUCE version of this project, DPF has no built-in "copy after
# build" step, so this script installs the LV2 bundle to ~/.lv2 and the
# VST3 to ~/.vst3 itself after a successful build.
#
# Usage:
#   ./build.sh              # configure (if needed) + build + install, Release
#   ./build.sh --debug      # build a Debug configuration instead
#   ./build.sh --clean      # wipe the build/ dir first, then configure+build
#   ./build.sh --no-install # build only, skip the ~/.lv2 / ~/.vst3 copy
#   ./build.sh -j4          # cap parallel build jobs (default: all cores)

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

build_dir="build"
build_type="Release"
jobs="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
clean=0
install=1

for arg in "$@"; do
    case "$arg" in
        --debug)      build_type="Debug" ;;
        --release)    build_type="Release" ;;
        --clean)      clean=1 ;;
        --no-install) install=0 ;;
        -j*)          jobs="${arg#-j}" ;;
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
cmake --build "$build_dir" -j"$jobs"

bin_dir="$build_dir/bin"
lv2_bundle="$bin_dir/IshDistortion.lv2"
vst3_bundle="$bin_dir/IshDistortion.vst3"

if [[ "$install" -eq 1 ]]; then
    if [[ -d "$lv2_bundle" ]]; then
        echo "Installing LV2 bundle to ~/.lv2/"
        mkdir -p "$HOME/.lv2"
        rm -rf "$HOME/.lv2/IshDistortion.lv2"
        cp -r "$lv2_bundle" "$HOME/.lv2/"
    fi
    if [[ -d "$vst3_bundle" ]]; then
        echo "Installing VST3 bundle to ~/.vst3/"
        mkdir -p "$HOME/.vst3"
        rm -rf "$HOME/.vst3/IshDistortion.vst3"
        cp -r "$vst3_bundle" "$HOME/.vst3/"
    fi
fi

echo
echo "Done. Artefacts:"
echo "  LV2:        $lv2_bundle $( [[ $install -eq 1 ]] && echo '(also installed to ~/.lv2)' )"
echo "  VST3:       $vst3_bundle $( [[ $install -eq 1 ]] && echo '(also installed to ~/.vst3)' )"
echo "  Standalone: $bin_dir/IshDistortion (JACK client - needs a running JACK/PipeWire-JACK server)"
