#include "PluginProcessor.h"
#include "PluginEditor.h"

//==============================================================================
DistortionAudioProcessor::DistortionAudioProcessor()
    : AudioProcessor (BusesProperties()
                           // Mono in/out: a distortion pedal is a mono effect, and it's
                           // what guitarix's rack expects for everything but the very last,
                           // stereo-only slot. LV2 ports are static (fixed at build time,
                           // no runtime renegotiation like VST3), so this default layout is
                           // what actually gets baked into the exported LV2 plugin - see
                           // isBusesLayoutSupported() below for the (mono OR stereo, but not
                           // mixed) layouts still permitted for hosts that do renegotiate,
                           // e.g. the Standalone/VST3 builds.
                           .withInput ("Input", juce::AudioChannelSet::mono(), true)
                           .withOutput ("Output", juce::AudioChannelSet::mono(), true)),
      apvts (*this, nullptr, "PARAMETERS", createParameterLayout())
{
    driveParam  = apvts.getRawParameterValue (driveParamID);
    toneParam   = apvts.getRawParameterValue (toneParamID);
    levelParam  = apvts.getRawParameterValue (levelParamID);
    bypassParam = apvts.getRawParameterValue (bypassParamID);
}

DistortionAudioProcessor::~DistortionAudioProcessor() = default;

//==============================================================================
juce::AudioProcessorValueTreeState::ParameterLayout DistortionAudioProcessor::createParameterLayout()
{
    std::vector<std::unique_ptr<juce::RangedAudioParameter>> params;

    // Drive: how hard the input signal is pushed into the waveshaper.
    // 0 dB = unity gain in, 24 dB = heavily overdriven input.
    params.push_back (std::make_unique<juce::AudioParameterFloat> (
        juce::ParameterID { driveParamID, 1 },
        "Drive",
        juce::NormalisableRange<float> (0.0f, 24.0f, 0.01f),
        0.0f,
        juce::AudioParameterFloatAttributes().withLabel ("dB")));

    // Tone: post-distortion tilt/filter balance. 0 = darkest, 1 = brightest,
    // 0.5 = neutral/flat. Exact mapping (shelving filter, tilt EQ, simple
    // low-pass blend, etc.) is an implementation choice - see
    // processBlock() below.
    params.push_back (std::make_unique<juce::AudioParameterFloat> (
        juce::ParameterID { toneParamID, 1 },
        "Tone",
        juce::NormalisableRange<float> (0.0f, 1.0f, 0.001f),
        0.5f));

    // Level: output trim applied after distortion + tone shaping, so the
    // player can match the effect's loudness back to unity/bypassed level.
    params.push_back (std::make_unique<juce::AudioParameterFloat> (
        juce::ParameterID { levelParamID, 1 },
        "Level",
        juce::NormalisableRange<float> (-24.0f, 6.0f, 0.01f),
        0.0f,
        juce::AudioParameterFloatAttributes().withLabel ("dB")));

    // Bypass: true = pass audio through unmodified (which, for now, is all
    // this processor ever does).
    params.push_back (std::make_unique<juce::AudioParameterBool> (
        juce::ParameterID { bypassParamID, 1 },
        "Bypass",
        false));

    return { params.begin(), params.end() };
}

//==============================================================================
void DistortionAudioProcessor::prepareToPlay (double /*sampleRate*/, int /*samplesPerBlock*/)
{
    // TODO(dsp): reset/prepare any filter and waveshaper state here once the
    // effect is implemented, e.g.:
    //   - juce::dsp::ProcessSpec spec { sampleRate, (uint32) samplesPerBlock, ... };
    //   - toneFilter.prepare (spec); toneFilter.reset();
    //   - any oversampler used to band-limit the distortion's harmonics
    //     (juce::dsp::Oversampling) should be prepared here too.
}

void DistortionAudioProcessor::releaseResources()
{
}

bool DistortionAudioProcessor::isBusesLayoutSupported (const BusesLayout& layouts) const
{
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono()
        && layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;

    return layouts.getMainOutputChannelSet() == layouts.getMainInputChannelSet();
}

void DistortionAudioProcessor::processBlock (juce::AudioBuffer<float>& buffer, juce::MidiBuffer&)
{
    juce::ScopedNoDenormals noDenormals;

    const auto totalNumInputChannels  = getTotalNumInputChannels();
    const auto totalNumOutputChannels = getTotalNumOutputChannels();

    for (auto ch = totalNumInputChannels; ch < totalNumOutputChannels; ++ch)
        buffer.clear (ch, 0, buffer.getNumSamples());

    // --- Passthrough only, below is where the actual effect goes ----------
    //
    // The block currently reaches the host/guitarix completely unmodified.
    // Parameter values are already available as lock-free atomics
    // (driveParam, toneParam, levelParam, bypassParam) - read them with
    // ->load() once per block (or per-sample if you want zipper-free
    // smoothing via juce::SmoothedValue).
    //
    // A typical distortion chain, in order, would be:
    //
    //   1. TODO(dsp) Input gain: scale the signal by the "drive" parameter
    //      (e.g. juce::Decibels::decibelsToGain (driveParam->load())) to
    //      push it harder into the waveshaper below.
    //
    //   2. TODO(dsp) Optional oversampling: upsample here (e.g. 2x/4x with
    //      juce::dsp::Oversampling) before waveshaping, to push aliasing
    //      from the nonlinearity above the audible band.
    //
    //   3. TODO(dsp) Waveshaping/nonlinearity: this is the actual
    //      "distortion" - apply a nonlinear transfer function per sample,
    //      e.g. soft clipping (std::tanh), hard clipping (juce::jlimit),
    //      or a diode/tube-style curve. This is the core of the effect and
    //      currently does nothing.
    //
    //   4. TODO(dsp) Downsample back (if oversampling was used in step 2).
    //
    //   5. TODO(dsp) Tone shaping: filter the distorted signal using the
    //      "tone" parameter, e.g. a tilt EQ, a single shelving filter
    //      (juce::dsp::IIR::Filter), or a blend between a low-passed and
    //      high-passed copy of the signal.
    //
    //   6. TODO(dsp) Output level: apply the "level" parameter as a final
    //      gain stage (juce::Decibels::decibelsToGain (levelParam->load()))
    //      so the player can match perceived loudness to the bypassed
    //      signal.
    //
    // "bypass" should short-circuit steps 1-6 above (as it effectively
    // does now, since none of them exist yet) and/or crossfade in/out to
    // avoid clicks when toggled during playback.
    juce::ignoreUnused (driveParam, toneParam, levelParam, bypassParam);
}

//==============================================================================
juce::AudioProcessorEditor* DistortionAudioProcessor::createEditor()
{
    return new DistortionAudioProcessorEditor (*this);
}

bool DistortionAudioProcessor::hasEditor() const
{
    return true;
}

//==============================================================================
const juce::String DistortionAudioProcessor::getName() const
{
    return JucePlugin_Name;
}

bool DistortionAudioProcessor::acceptsMidi() const   { return false; }
bool DistortionAudioProcessor::producesMidi() const  { return false; }
bool DistortionAudioProcessor::isMidiEffect() const  { return false; }
double DistortionAudioProcessor::getTailLengthSeconds() const { return 0.0; }

//==============================================================================
int DistortionAudioProcessor::getNumPrograms()                        { return 1; }
int DistortionAudioProcessor::getCurrentProgram()                     { return 0; }
void DistortionAudioProcessor::setCurrentProgram (int)                {}
const juce::String DistortionAudioProcessor::getProgramName (int)     { return {}; }
void DistortionAudioProcessor::changeProgramName (int, const juce::String&) {}

//==============================================================================
void DistortionAudioProcessor::getStateInformation (juce::MemoryBlock& destData)
{
    if (auto state = apvts.copyState(); true)
    {
        if (auto xml = state.createXml())
            copyXmlToBinary (*xml, destData);
    }
}

void DistortionAudioProcessor::setStateInformation (const void* data, int sizeInBytes)
{
    if (auto xml = getXmlFromBinary (data, sizeInBytes))
        if (xml->hasTagName (apvts.state.getType()))
            apvts.replaceState (juce::ValueTree::fromXml (*xml));
}

//==============================================================================
// This creates new instances of the plugin.
juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
{
    return new DistortionAudioProcessor();
}
