cmake_minimum_required(VERSION 3.15)

project(IshDistortion VERSION 0.1.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if (NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# --------------------------------------------------------------------------
# DPF (DISTRHO Plugin Framework)
#
# Pulled in via FetchContent so the project builds with a single `cmake`
# invocation. DPF has no tagged releases - pin to a known-good commit and
# bump it deliberately:
# https://github.com/DISTRHO/DPF/commits/main
# --------------------------------------------------------------------------
include(FetchContent)
FetchContent_Declare(
    dpf
    GIT_REPOSITORY https://github.com/DISTRHO/DPF.git
    GIT_TAG 4238e1c7f0351bbe488d79f0899c540543ac7583 # main, 2025-10-23
)
FetchContent_MakeAvailable(dpf)

# --------------------------------------------------------------------------
# Plugin target
#
# jack   -> standalone app via JACK, for quick testing without a host
# vst3   -> for testing in any VST3 host/DAW
# lv2    -> the format guitarix actually loads
#
# No FILES_UI: no custom UI (see plugin/DistrhoPluginInfo.h) - hosts render
# generic controls from the Parameter list in IshDistortionPlugin.cpp.
# --------------------------------------------------------------------------
dpf_add_plugin(IshDistortion
    TARGETS jack vst3 lv2
    FILES_DSP
        plugin/IshDistortionPlugin.cpp
)

target_include_directories(IshDistortion PUBLIC plugin)
