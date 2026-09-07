#include "PluginEditor.h"

namespace
{
    void setupRotary (juce::Slider& slider, juce::Label& label, const juce::String& text,
                       juce::Component& parent)
    {
        slider.setSliderStyle (juce::Slider::RotaryHorizontalVerticalDrag);
        slider.setTextBoxStyle (juce::Slider::TextBoxBelow, false, 80, 20);
        parent.addAndMakeVisible (slider);

        label.setText (text, juce::dontSendNotification);
        label.setJustificationType (juce::Justification::centred);
        label.attachToComponent (&slider, false);
        parent.addAndMakeVisible (label);
    }
}

//==============================================================================
DistortionAudioProcessorEditor::DistortionAudioProcessorEditor (DistortionAudioProcessor& p)
    : AudioProcessorEditor (&p), processorRef (p)
{
    setupRotary (driveSlider, driveLabel, "Drive", *this);
    setupRotary (toneSlider,  toneLabel,  "Tone",  *this);
    setupRotary (levelSlider, levelLabel, "Level", *this);

    addAndMakeVisible (bypassButton);

    auto& apvts = processorRef.apvts;
    driveAttachment  = std::make_unique<SliderAttachment> (apvts, DistortionAudioProcessor::driveParamID,  driveSlider);
    toneAttachment   = std::make_unique<SliderAttachment> (apvts, DistortionAudioProcessor::toneParamID,   toneSlider);
    levelAttachment  = std::make_unique<SliderAttachment> (apvts, DistortionAudioProcessor::levelParamID,  levelSlider);
    bypassAttachment = std::make_unique<ButtonAttachment> (apvts, DistortionAudioProcessor::bypassParamID, bypassButton);

    setSize (360, 220);
}

DistortionAudioProcessorEditor::~DistortionAudioProcessorEditor() = default;

//==============================================================================
void DistortionAudioProcessorEditor::paint (juce::Graphics& g)
{
    g.fillAll (getLookAndFeel().findColour (juce::ResizableWindow::backgroundColourId));

    g.setColour (juce::Colours::white);
    g.setFont (juce::FontOptions (16.0f, juce::Font::bold));
    g.drawFittedText ("Ish Distortion (passthrough)", getLocalBounds().removeFromTop (30),
                       juce::Justification::centred, 1);
}

void DistortionAudioProcessorEditor::resized()
{
    auto bounds = getLocalBounds().reduced (20);
    bounds.removeFromTop (30); // title

    bypassButton.setBounds (bounds.removeFromTop (24));
    bounds.removeFromTop (10);

    const auto knobWidth = bounds.getWidth() / 3;
    driveSlider.setBounds (bounds.removeFromLeft (knobWidth).reduced (10));
    toneSlider.setBounds  (bounds.removeFromLeft (knobWidth).reduced (10));
    levelSlider.setBounds (bounds.removeFromLeft (knobWidth).reduced (10));
}
