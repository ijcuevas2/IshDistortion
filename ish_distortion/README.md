# Ish Distortion (DPF/LV2 scaffold)

A DPF-based LV2 plugin scaffold, built for use as a guitarix effect — the
non-JUCE counterpart to the `distortion` project. It is a **passthrough**:
audio goes in and comes out completely unmodified. No distortion is
implemented yet — this project only wires up the plugin target, build
system, and the parameters a distortion effect will need (`Drive`, `Tone`,
`Level`, `Bypass`).

See `plugin/IshDistortionPlugin.cpp` — `run()` — for `TODO(dsp)` comments
marking exactly where each stage of the effect (input gain, waveshaping,
tone filter, output level) should be implemented.

## Why DPF instead of JUCE

The JUCE version of this plugin hit two real guitarix-compatibility issues
before it would even show up in guitarix's plugin picker: a default stereo
bus layout, and JUCE's LV2 exporter unconditionally marking
`bufs:boundedBlockLength` as a *required* LV2 feature (with no way to turn
it off), which guitarix doesn't implement — both had to be worked around
after the fact.

[DPF](https://github.com/DISTRHO/DPF) is LV2-first rather than a
VST-shaped abstraction retrofitted with LV2 export, so this project avoids
both problems by construction:

- Mono in/out is declared directly (`DISTRHO_PLUGIN_NUM_INPUTS/OUTPUTS` in
  `plugin/DistrhoPluginInfo.h`), matching guitarix's mostly-mono rack.
- DPF's own LV2 exporter puts `boundedBlockLength` in `optionalFeature`,
  not `requiredFeature` — verified directly in DPF's source
  (`distrho/src/DistrhoPluginLV2export.cpp`) before writing this project.
- Parameters export as plain `lv2:ControlPort`s rather than JUCE's
  atom/`patch:Message`-based parameter system — the older, more
  universally-supported style.
- The plugin's LV2 class is `lv2:DistortionPlugin` (a real class in LV2's
  core taxonomy), not JUCE's generic default.

None of this is JUCE-specific criticism so much as "a framework built
LV2-first behaves differently from one where LV2 is one export target
among several" — see the `distortion` project's README for the JUCE-side
story and workarounds in full.

## Dependencies (Linux)

```sh
sudo apt install build-essential cmake pkg-config \
    libasound2-dev libjack-jackd2-dev \
    libx11-dev libxext-dev libxcursor-dev libxrandr-dev
```

(DPF's LV2/VST3/JACK targets built here don't need a GUI toolkit like
Cairo/OpenGL/GTK — this project has no custom UI; see
"About the UI" below.)

## Build

```sh
./build.sh
```

The first run fetches DPF via `FetchContent` (needs internet access once;
cached under `build/_deps` afterwards).

Options: `./build.sh --debug` (Debug config), `./build.sh --clean` (wipe
`build/` first), `./build.sh --no-install` (build only, skip copying to
`~/.lv2`/`~/.vst3`), `./build.sh -j4` (cap parallel jobs).

This produces, under `build/bin/`:

- `IshDistortion.lv2/` — the LV2 bundle, for guitarix
- `IshDistortion.vst3/` — for testing in any VST3 host/DAW
- `IshDistortion` — a JACK standalone client, for quick testing without a
  host (needs a running JACK or PipeWire-JACK server)

Unlike the JUCE project, DPF has no built-in "copy after build" step, so
`build.sh` installs the LV2/VST3 bundles to `~/.lv2` and `~/.vst3` itself
after a successful build.

## Install into guitarix

Already done by `build.sh` above. guitarix also keeps its own opt-in list
of *enabled* plugins, separate from what it can discover, so even a fully
compatible plugin needs to be checked once:

1. Restart guitarix (so it re-scans `~/.lv2`).
2. Menu: **Plugins → LADSPA/LV2 Plugins**.
3. Find **"Ish Distortion"** in the list and check/enable it, then
   **Apply**/**Save**.
4. Open the plugin bar (toolbar button) — it now appears under the
   **"External"** category, ready to drag into the rack.

From then on it stays enabled across restarts; you only need to repeat
steps 2-3 for a plugin you haven't enabled before.

## About the UI

`DISTRHO_PLUGIN_HAS_UI` is `0` — there's no custom plugin UI. Hosts
(guitarix included) render generic knobs/switches from the `Parameter`
list in `IshDistortionPlugin.cpp`, which is normal for rack-style LV2
effects and keeps this scaffold's dependencies minimal. A real UI can be
added later via DPF's `FILES_UI`/DGL toolkit if wanted — see
`dpf/examples/CairoUI` (fetched under `build/_deps/dpf-src/examples/`)
for a worked example.

## Before distributing this beyond your own machine

`DISTRHO_PLUGIN_URI` in `plugin/DistrhoPluginInfo.h` is currently a
placeholder (`https://example.com/plugins/ish-distortion`). It doesn't
need to resolve to a real page, but it must be a URI you control and it
must stay stable across releases (LV2 hosts use it as the plugin's
permanent identity). Change it, and `DISTRHO_PLUGIN_CLAP_ID`/
`DISTRHO_PLUGIN_BRAND_ID`/`DISTRHO_PLUGIN_UNIQUE_ID` alongside it, before
sharing the plugin or publishing presets.
