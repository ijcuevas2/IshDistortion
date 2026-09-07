#pragma once

#include "PluginProcessor.h"
#include <juce_audio_processors/juce_audio_processors.h>

//==============================================================================
/** Minimal editor: one rotary slider per parameter, plus a bypass toggle.
    Purely a control surface - all attachments bind straight to the APVTS,
    so nothing here needs to change once the DSP in PluginProcessor.cpp is
    implemented.
*/
class DistortionAudioProcessorEditor : public juce::AudioProcessorEditor
{
public:
    explicit DistortionAudioProcessorEditor (DistortionAudioProcessor&);
    ~DistortionAudioProcessorEditor() override;

    //==============================================================================
    void paint (juce::Graphics&) override;
    void resized() override;

private:
    DistortionAudioProcessor& processorRef;

    juce::Slider driveSlider, toneSlider, levelSlider;
    juce::Label  driveLabel, toneLabel, levelLabel;
    juce::ToggleButton bypassButton { "Bypass" };

    using SliderAttachment = juce::AudioProcessorValueTreeState::SliderAttachment;
    using ButtonAttachment = juce::AudioProcessorValueTreeState::ButtonAttachment;

    std::unique_ptr<SliderAttachment> driveAttachment;
    std::unique_ptr<SliderAttachment> toneAttachment;
    std::unique_ptr<SliderAttachment> levelAttachment;
    std::unique_ptr<ButtonAttachment> bypassAttachment;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (DistortionAudioProcessorEditor)
};
