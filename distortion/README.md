# Ish Distortion (LV2 scaffold)

A JUCE-based LV2 plugin scaffold, built for use as a guitarix effect. It is a
**passthrough**: audio goes in and comes out completely unmodified. No
distortion is implemented yet — this project only wires up the plugin
target, build system, and the parameters a distortion effect will need
(`Drive`, `Tone`, `Level`, `Bypass`).

See `Source/PluginProcessor.cpp` — `processBlock()` — for `TODO(dsp)`
comments marking exactly where each stage of the effect (input gain,
waveshaping, tone filter, output level) should be implemented.

JUCE has had native LV2 export support since JUCE 7, so this uses stock
JUCE + CMake — no forks or extra modules.

## Dependencies (Linux)

JUCE's GUI/audio backends need a few system dev packages. On Debian/Ubuntu:

```sh
sudo apt install build-essential cmake pkg-config \
    libasound2-dev libjack-jackd2-dev \
    libx11-dev libxcomposite-dev libxcursor-dev libxext-dev \
    libxinerama-dev libxrandr-dev libxrender-dev \
    libfreetype-dev libfontconfig1-dev
```

(Web browser and curl support are disabled in `CMakeLists.txt`, so
`libwebkit2gtk`/`libcurl` are not required.)

## Build

```sh
./build.sh
```

The first run will fetch JUCE 9.0.1 via `FetchContent` (needs internet
access once; cached under `build/_deps` afterwards).

Options: `./build.sh --debug` (Debug config), `./build.sh --clean` (wipe
`build/` first), `./build.sh -j4` (cap parallel jobs). Or drive CMake
directly:

```sh
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j
```

This produces, under `build/Distortion_artefacts/Release/`:

- `LV2/Ish Distortion.lv2/` — the LV2 bundle, for guitarix
- `Standalone/Ish Distortion` — a standalone app, for quick testing without a host
- `VST3/Ish Distortion.vst3` — for testing in any VST3 host/DAW

## Install into guitarix

`COPY_PLUGIN_AFTER_BUILD` is enabled in `CMakeLists.txt`, so a successful
build already installs the LV2 bundle to `~/.lv2/Ish Distortion.lv2` (and the
VST3 to `~/.vst3/Ish Distortion.vst3`) automatically — guitarix (and other LV2
hosts) scan `~/.lv2` by default. No manual copy needed.

If you ever need to do it by hand instead:

```sh
mkdir -p ~/.lv2
cp -r "build/Distortion_artefacts/Release/LV2/Ish Distortion.lv2" ~/.lv2/
```

### Two compatibility issues this project already works around

guitarix's own **Plugins → LADSPA/LV2 Plugins** picker does a *live*,
filtered scan of every LADSPA/LV2 plugin on the system — a plugin that
fails either check below is silently absent from that list, not just
unchecked. Both are handled automatically by this project's build, but are
worth knowing about since they're common gotchas for any JUCE LV2 plugin,
not just this one:

- **Channel layout.** guitarix's rack is mono end-to-end except for a
  stereo-only section at the very bottom, so a stereo in/out plugin (JUCE's
  default) is filtered out entirely. `PluginProcessor.cpp` declares a mono
  bus layout for exactly this reason — also just the correct layout for a
  guitar distortion effect.
- **`bufs:boundedBlockLength`.** JUCE's LV2 exporter unconditionally marks
  this LV2 feature as *required*, with no CMake option to change it. Per
  the LV2 spec, a host must refuse to even list a plugin whose required
  features it doesn't implement, and guitarix doesn't implement this one.
  `cmake/fix_lv2_required_feature.cmake` demotes it to *optional* in the
  generated `dsp.ttl` as a post-build step (both the build-tree copy and
  the one installed to `~/.lv2`) — see that file for the full rationale.

### Enabling the plugin in guitarix

guitarix also keeps its own opt-in list of *enabled* plugins
(`~/.config/guitarix/ladspa_defs.js`), separate from what it can discover —
even a fully compatible plugin needs to be checked here once:

1. Restart guitarix (so it re-scans `~/.lv2`).
2. Menu: **Plugins → LADSPA/LV2 Plugins**.
3. Find **"Ish Distortion"** in the list and check/enable it, then
   **Apply**/**Save**.
4. Open the plugin bar (toolbar button) — it now appears under the
   **"External"** category, ready to drag into the rack.

From then on it stays enabled across restarts; you only need to repeat
steps 2-3 for a plugin you haven't enabled before.

## Before distributing this beyond your own machine

`LV2URI` in `CMakeLists.txt` is currently a placeholder
(`https://example.com/plugins/distortion`). It doesn't need to resolve to a
real page, but it must be a URI you control and it must stay stable across
releases (LV2 hosts use it as the plugin's permanent identity). Change it
before sharing the plugin or publishing presets.
