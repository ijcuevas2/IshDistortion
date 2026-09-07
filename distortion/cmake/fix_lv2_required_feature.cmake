# Demotes bufs:boundedBlockLength from a *required* LV2 feature to an
# *optional* one in a JUCE-generated dsp.ttl.
#
# Why: JUCE's LV2 exporter (juce_audio_plugin_client_LV2.cpp) unconditionally
# writes bufs:boundedBlockLength into lv2:requiredFeature, with no CMake
# option to change it. Per the LV2 spec, a host MUST refuse to even list a
# plugin that requires a feature it doesn't implement - and some real hosts
# (guitarix among them) don't implement this one, silently hiding the
# plugin from their picker. This plugin doesn't rely on a bounded block
# size, so relaxing the requirement is safe and restores compatibility.
#
# Usage: cmake -DTTL_FILE=<path/to/dsp.ttl> -P fix_lv2_required_feature.cmake
# Run as a POST_BUILD step - see CMakeLists.txt.

if (NOT DEFINED TTL_FILE)
    message(FATAL_ERROR "fix_lv2_required_feature.cmake: TTL_FILE not set")
endif()

if (NOT EXISTS "${TTL_FILE}")
    message(STATUS "fix_lv2_required_feature: ${TTL_FILE} not found, skipping")
    return()
endif()

file(READ "${TTL_FILE}" contents)

set(required_block [=[	lv2:requiredFeature
		urid:map ,
		opts:options ,
		bufs:boundedBlockLength ;
]=])

set(replacement [=[	lv2:requiredFeature
		urid:map ,
		opts:options ;
	lv2:optionalFeature
		bufs:boundedBlockLength ;
]=])

string(FIND "${contents}" "${required_block}" pos)
if (pos EQUAL -1)
    # Either already patched, or JUCE's LV2 export format changed under us.
    string(FIND "${contents}" "bufs:boundedBlockLength" already_optional)
    if (already_optional EQUAL -1)
        message(WARNING
            "fix_lv2_required_feature: expected requiredFeature block not "
            "found in ${TTL_FILE} - a JUCE upgrade may have changed the LV2 "
            "export format. Leaving the file untouched; guitarix may hide "
            "this plugin again until this script is updated to match.")
    endif()
    return()
endif()

string(REPLACE "${required_block}" "${replacement}" contents "${contents}")
file(WRITE "${TTL_FILE}" "${contents}")
message(STATUS "fix_lv2_required_feature: demoted bufs:boundedBlockLength to optionalFeature in ${TTL_FILE}")
