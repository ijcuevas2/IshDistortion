/*
 * Ish Distortion - a passthrough LV2/VST3/JACK-standalone scaffold for a
 * guitar distortion effect, built with DPF (https://github.com/DISTRHO/DPF)
 * instead of JUCE.
 *
 * No distortion is implemented yet: run() below just copies input to
 * output. The parameters a real distortion effect needs (Drive, Tone,
 * Level, Bypass) are already declared, automatable, and host-visible;
 * see the TODO(dsp) comments in run() for where each processing stage
 * should go.
 */

#include "DistrhoPlugin.hpp"

START_NAMESPACE_DISTRHO

// -----------------------------------------------------------------------------------------------------------

enum Parameters
{
    kParameterDrive = 0,
    // kParameterTone,
    // kParameterLevel,
    // kParameterBypass,
    kParameterCount
};

class IshDistortionPlugin : public Plugin
{
public:
    IshDistortionPlugin()
        : Plugin(kParameterCount, 0, 0) // parameters, programs, states
    {
        fDrive   = 0.0f;
        // fTone    = 0.5f;
        // fLevel   = 0.0f;
        // fBypass  = 0.0f;
    }

protected:
    // ---------------------------------------------------------------------
    // Information

    const char* getLabel() const override
    {
        return "IshDistortion";
    }

    const char* getDescription() const override
    {
        return "A passthrough distortion scaffold - no DSP yet, but Drive/Tone/Level/Bypass "
               "are already exposed as automatable host parameters.";
    }

    const char* getMaker() const override
    {
        return "Ish";
    }

    const char* getHomePage() const override
    {
        return DISTRHO_PLUGIN_URI;
    }

    const char* getLicense() const override
    {
        return "ISC";
    }

    uint32_t getVersion() const override
    {
        return d_version(0, 1, 0);
    }

    int64_t getUniqueId() const override
    {
        return d_cconst('I', 's', 'h', 'D');
    }

    // ---------------------------------------------------------------------
    // Init

    void initParameter(uint32_t index, Parameter& parameter) override
    {
        switch (index)
        {
        case kParameterDrive:
            parameter.name       = "Drive";
            parameter.symbol     = "drive";
            parameter.unit       = "dB";
            parameter.hints      = kParameterIsAutomatable;
            parameter.ranges     = ParameterRanges(0.0f, 0.0f, 24.0f); // default, min, max
            parameter.description = "How hard the input signal is pushed into the waveshaper.";
            break;

        // case kParameterTone:
        //     parameter.name       = "Tone";
        //     parameter.symbol     = "tone";
        //     parameter.hints      = kParameterIsAutomatable;
        //     parameter.ranges     = ParameterRanges(0.5f, 0.0f, 1.0f);
        //     parameter.description = "Post-distortion tilt/filter balance: 0 darkest, 1 brightest.";
        //     break;

        // case kParameterLevel:
        //     parameter.name       = "Level";
        //     parameter.symbol     = "level";
        //     parameter.unit       = "dB";
        //     parameter.hints      = kParameterIsAutomatable;
        //     parameter.ranges     = ParameterRanges(0.0f, -24.0f, 6.0f);
        //     parameter.description = "Output trim applied after distortion + tone shaping.";
        //     break;

        // case kParameterBypass:
        //     parameter.name       = "Bypass";
        //     parameter.symbol     = "bypass";
        //     parameter.hints      = kParameterIsAutomatable | kParameterIsBoolean;
        //     parameter.ranges     = ParameterRanges(0.0f, 0.0f, 1.0f);
        //     parameter.designation = kParameterDesignationBypass;
        //     parameter.description = "Pass audio through unmodified (which, for now, is all this plugin ever does).";
        //     break;
        }
    }

    // ---------------------------------------------------------------------
    // Internal data

    float getParameterValue(uint32_t index) const override
    {
        switch (index)
        {
        case kParameterDrive:  return fDrive;
        // case kParameterTone:   return fTone;
        // case kParameterLevel:  return fLevel;
        // case kParameterBypass: return fBypass;
        default:               return 0.0f;
        }
    }

    void setParameterValue(uint32_t index, float value) override
    {
        switch (index)
        {
        case kParameterDrive:  fDrive  = value; break;
        // case kParameterTone:   fTone   = value; break;
        // case kParameterLevel:  fLevel  = value; break;
        // case kParameterBypass: fBypass = value; break;
        }
    }

    // ---------------------------------------------------------------------
    // Process

    void activate() override
    {
        // TODO(dsp): reset/prepare any filter and waveshaper state here
        // once the effect is implemented, e.g. clear filter memory, and
        // (re)build any oversampling stage sized for the current sample
        // rate (getSampleRate()) and block size (getBufferSize()).
    }

    float exponential(float x, int n) {
        float sum = 1.0f; // initialize sum of series

        for (int i = n - 1; i > 0; --i) {
            sum = 1 + x * sum / i;
        }

        return sum;
    }

    float distortion(float x, int n){
        float y;
        float factor = 2.0;
        if(x > 0){
            y = 1 - exponential(-x, n);
            /* y = 1 - exp(-x); */
        } else {
            y = -1 + exponential(x, n);
            /* y = -1 + exp(x); */
        }

        return y;
    }

    float waveshaper(float x_n, float drive){
        float y = (((1 + drive) * x_n) / (1 + drive * absolute(x_n)));
        return y;
    }

    float absolute(float val){
        if(val >= 0) {
            return val;
        }

        return -1 * val;
    }

    void run(const float** inputs, float** outputs, uint32_t frames) override
    {
        // --- Passthrough only, below is where the actual effect goes -------
        //
        // The block currently reaches the host/guitarix completely
        // unmodified. Parameter values are already available as plain
        // member floats (fDrive, fTone, fLevel, fBypass) via
        // getParameterValue()/setParameterValue() above - read them here
        // (or smooth them per-sample to avoid zipper noise on fast
        // automation).
        //
        // A typical distortion chain, in order, would be:
        //
        //   1. TODO(dsp) Input gain: scale the signal by fDrive (e.g. a
        //      dB-to-linear conversion) to push it harder into the
        //      waveshaper below.
        //


        //   2. TODO(dsp) Optional oversampling: upsample here before
        //      waveshaping, to push aliasing from the nonlinearity above
        //      the audible band.
        //
        //   3. TODO(dsp) Waveshaping/nonlinearity: this is the actual
        //      "distortion" - apply a nonlinear transfer function per
        //      sample, e.g. soft clipping (tanhf), hard clipping, or a
        //      diode/tube-style curve. This is the core of the effect and
        //      currently does nothing.
        //
        //   4. TODO(dsp) Downsample back (if oversampling was used in
        //      step 2).
        //
        //   5. TODO(dsp) Tone shaping: filter the distorted signal using
        //      fTone, e.g. a tilt EQ, a single shelving filter, or a
        //      blend between a low-passed and high-passed copy of the
        //      signal.
        //
        //   6. TODO(dsp) Output level: apply fLevel as a final gain stage
        //      so the player can match perceived loudness to the
        //      bypassed signal.
        //
        // fBypass should short-circuit steps 1-6 above (as it effectively
        // does now, since none of them exist yet) and/or crossfade in/out
        // to avoid clicks when toggled during playback.
        int num_coeff = 3;
        for (uint32_t i = 0; i < frames; ++i)
        {
            float x = inputs[0][i];      // read sample i of channel 0

            float distRes = distortion(x, num_coeff);
            float y  = waveshaper(distRes, fDrive);

            outputs[0][i] = y;           // write sample i of channel 0
        }

        // if (outputs[0] != inputs[0])
        //     std::memcpy(outputs[0], inputs[0], sizeof(float) * frames);
    }

    // -----------------------------------------------------------------------

private:
    float fDrive;
    // float fTone, fLevel, fBypass;

    DISTRHO_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(IshDistortionPlugin)
};

// -----------------------------------------------------------------------------------------------------------

Plugin* createPlugin()
{
    return new IshDistortionPlugin();
}

// -----------------------------------------------------------------------------------------------------------

END_NAMESPACE_DISTRHO
