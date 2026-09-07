#pragma once

// --------------------------------------------------------------------------
// Identity
// --------------------------------------------------------------------------
#define DISTRHO_PLUGIN_BRAND    "Ish"
#define DISTRHO_PLUGIN_NAME     "Ish Distortion"
#define DISTRHO_PLUGIN_URI      "https://example.com/plugins/ish-distortion"
#define DISTRHO_PLUGIN_CLAP_ID  "com.example.ish-distortion"

// 4-char identifiers (bare tokens, not strings). BRAND_ID is shared across
// everything you'd ship under this brand; UNIQUE_ID must be unique to this
// one plugin.
#define DISTRHO_PLUGIN_BRAND_ID Ish_
#define DISTRHO_PLUGIN_UNIQUE_ID Dst1

// --------------------------------------------------------------------------
// Ports and characteristics
// --------------------------------------------------------------------------
// Mono in/out: a distortion pedal is a mono effect, and it's what guitarix's
// rack expects for everything but its very last, stereo-only slot.
#define DISTRHO_PLUGIN_NUM_INPUTS   1
#define DISTRHO_PLUGIN_NUM_OUTPUTS  1

#define DISTRHO_PLUGIN_IS_SYNTH     0
#define DISTRHO_PLUGIN_IS_RT_SAFE   1
#define DISTRHO_PLUGIN_WANT_PROGRAMS 0
#define DISTRHO_PLUGIN_WANT_STATE    0

// No custom UI: hosts (guitarix included) render generic knobs/switches
// from the Parameter list below. Simplest option, and works well for a
// rack-style effect like this one; a real UI can be added later with
// FILES_UI in CMakeLists.txt if wanted.
#define DISTRHO_PLUGIN_HAS_UI 0

// Real LV2 taxonomy class for this plugin - see lv2core.ttl.
#define DISTRHO_PLUGIN_LV2_CATEGORY "lv2:DistortionPlugin"
