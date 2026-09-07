cmake_minimum_required(VERSION 3.22)

project(DistortionLV2 VERSION 0.1.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --------------------------------------------------------------------------
# JUCE
#
# Pulled in via FetchContent so the project builds with a single `cmake`
# invocation and no manual submodule setup. JUCE has had native LV2 export
# support since version 7, so no extra module/fork is needed - just add
# LV2 to the FORMATS list below.
#
# Bump GIT_TAG to track newer JUCE releases as needed:
# https://github.com/juce-framework/JUCE/releases
# --------------------------------------------------------------------------
include(FetchContent)
FetchContent_Declare(
    JUCE
    GIT_REPOSITORY https://github.com/juce-framework/JUCE.git
    GIT_TAG 9.0.1
    GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(JUCE)

# --------------------------------------------------------------------------
# Plugin target
# --------------------------------------------------------------------------
# Also used below to locate the built/installed LV2 bundle for post-build
# patching - keep this the single source of truth for the plugin's name.
set(JUCE_PRODUCT_NAME "Ish Distortion")

juce_add_plugin(Distortion
    COMPANY_NAME "YourCompany"
    PRODUCT_NAME "${JUCE_PRODUCT_NAME}"
    PLUGIN_MANUFACTURER_CODE Ycmp
    PLUGIN_CODE Dst1

    IS_SYNTH FALSE
    NEEDS_MIDI_INPUT FALSE
    NEEDS_MIDI_OUTPUT FALSE
    IS_MIDI_EFFECT FALSE
    EDITOR_WANTS_KEYBOARD_FOCUS FALSE
    COPY_PLUGIN_AFTER_BUILD TRUE

    # Build a Standalone app and a VST3 alongside LV2 - handy for testing
    # the UI/params without a host. Guitarix only needs LV2.
    FORMATS Standalone VST3 LV2

    # LV2 plugins are identified by a globally-unique URI, not a bundle ID.
    # It does NOT need to resolve to a real page, but it must stay stable
    # across releases and should live under a domain/namespace you control
    # before you distribute this beyond your own machine.
    LV2URI "https://example.com/plugins/distortion"
)

target_sources(Distortion
    PRIVATE
        Source/PluginProcessor.cpp
        Source/PluginEditor.cpp
)

target_compile_definitions(Distortion
    PUBLIC
        JUCE_WEB_BROWSER=0
        JUCE_USE_CURL=0
        JUCE_VST3_CAN_REPLACE_VST2=0
)

target_link_libraries(Distortion
    PRIVATE
        juce::juce_audio_utils
    PUBLIC
        juce::juce_recommended_config_flags
        juce::juce_recommended_lto_flags
        juce::juce_recommended_warning_flags
)

# --------------------------------------------------------------------------
# guitarix (and some other minimal LV2 hosts) don't implement the
# bufs:boundedBlockLength feature, which JUCE's LV2 exporter always marks
# as *required* with no way to turn that off - per the LV2 spec, such
# hosts then correctly refuse to even list the plugin. Patch it down to
# *optional* after each build; see cmake/fix_lv2_required_feature.cmake
# for the full rationale. Runs after JUCE's own POST_BUILD steps (ttl
# generation + COPY_PLUGIN_AFTER_BUILD's copy to ~/.lv2), so both the
# build-tree bundle and the installed one end up patched.
# --------------------------------------------------------------------------
add_custom_command(TARGET Distortion_LV2 POST_BUILD
    COMMAND "${CMAKE_COMMAND}"
            "-DTTL_FILE=$<TARGET_FILE_DIR:Distortion_LV2>/dsp.ttl"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/fix_lv2_required_feature.cmake"
    COMMAND "${CMAKE_COMMAND}"
            "-DTTL_FILE=$ENV{HOME}/.lv2/${JUCE_PRODUCT_NAME}.lv2/dsp.ttl"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/fix_lv2_required_feature.cmake"
    VERBATIM
)
