#pragma once

#include <juce_audio_processors/juce_audio_processors.h>

//==============================================================================
/**
    Distortion (passthrough scaffold).

    This processor does not yet alter the signal - processBlock() below just
    passes audio straight through. The parameters a distortion effect needs
    are already exposed and wired up via an AudioProcessorValueTreeState so
    the UI, host automation, and LV2 port mapping all work today; only the
    actual DSP math is missing. See the comments in PluginProcessor.cpp for
    where each stage should be implemented.
*/
class DistortionAudioProcessor : public juce::AudioProcessor
{
public:
    DistortionAudioProcessor();
    ~DistortionAudioProcessor() override;

    //==============================================================================
    void prepareToPlay (double sampleRate, int samplesPerBlock) override;
    void releaseResources() override;

    bool isBusesLayoutSupported (const BusesLayout& layouts) const override;

    using AudioProcessor::processBlock; // unhide the double-precision overload we don't implement
    void processBlock (juce::AudioBuffer<float>&, juce::MidiBuffer&) override;

    //==============================================================================
    juce::AudioProcessorEditor* createEditor() override;
    bool hasEditor() const override;

    //==============================================================================
    const juce::String getName() const override;

    bool acceptsMidi() const override;
    bool producesMidi() const override;
    bool isMidiEffect() const override;
    double getTailLengthSeconds() const override;

    //==============================================================================
    int getNumPrograms() override;
    int getCurrentProgram() override;
    void setCurrentProgram (int index) override;
    const juce::String getProgramName (int index) override;
    void changeProgramName (int index, const juce::String& newName) override;

    //==============================================================================
    void getStateInformation (juce::MemoryBlock& destData) override;
    void setStateInformation (const void* data, int sizeInBytes) override;

    //==============================================================================
    // Parameter IDs - shared between the processor, the editor's attachments,
    // and (via LV2URI + these IDs) the plugin's LV2 ports.
    static constexpr auto driveParamID  = "drive";
    static constexpr auto toneParamID   = "tone";
    static constexpr auto levelParamID  = "level";
    static constexpr auto bypassParamID = "bypass";

    juce::AudioProcessorValueTreeState apvts;

private:
    static juce::AudioProcessorValueTreeState::ParameterLayout createParameterLayout();

    // Cached raw pointers into apvts for cheap, lock-free reads from the
    // audio thread. Populated in the constructor.
    std::atomic<float>* driveParam  = nullptr;
    std::atomic<float>* toneParam   = nullptr;
    std::atomic<float>* levelParam  = nullptr;
    std::atomic<float>* bypassParam = nullptr;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (DistortionAudioProcessor)
};
