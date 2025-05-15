//#define MA_NO_DECODING
//#define MA_NO_ENCODING
//#define MINIAUDIO_IMPLEMENTATION
//#include "miniaudio.h"
#include "external/port.h"
static float ma_waveform_sine_f32(double time, double amplitude);
static float ma_waveform_triangle_f32(double time, double amplitude);
static float ma_waveform_sawtooth_f32(double time, double amplitude);
static float ma_waveform_square_f32(double time, double amplitude);

static float lerp(float a, float b, float t);

#define DEVICE_FORMAT ma_format_f32
#define DEVICE_CHANNELS 1
#define DEVICE_SAMPLE_RATE 48000



#define foreach_rb(rb, i) for (size_t i = (rb).head; i != (rb).tail; i = (i + 1) % RINGBUF_SIZE)

#define WAVEFORM_RECORD_GRANULARITY 20
RingBuffer waveform_record = {0};
void RingBuffer_Append(RingBuffer *rb, float el) {
    rb->tail = (rb->tail + 1) % RINGBUF_SIZE;
    if (rb->tail == rb->head) {
	rb->head = (rb->head + 1) % RINGBUF_SIZE;
    } else {
	rb->count += 1;
    }
    rb->data[rb->tail] = el;
}
static double ma_waveform__calculate_advance(ma_uint32 sampleRate, double frequency)
{
    return (1.0 / (sampleRate / frequency));
}


void waveform_init(Waveform *waveform, double amp, double freq, unsigned sample_rate, bool is_live) {
    waveform->amplitude = amp;
    waveform->frequency = freq;
    waveform->advance = ma_waveform__calculate_advance(sample_rate, freq);
    waveform->time    = 0;
    waveform->is_live = is_live;
    waveform->should_sustain = true;
}
WaveformEnvelop init_envelop_fixed(float attack, float decay, float sustain, float release) {
    return (WaveformEnvelop) {
	.attack = attack,
	    .decay = attack + decay,
	    .fixed_sustain = attack + decay + sustain,
	    .release = attack + decay + sustain + release,
    };
}
WaveformEnvelop init_envelop_live(float attack, float decay, float release) {
    return (WaveformEnvelop) {
	.attack = attack,
	    .decay = attack + decay,
	    .release = release,
    };
}
void stringnoise_init(StringNoise *string, double freq) {
    string->count = 0;
    string->buf_len = DEVICE_SAMPLE_RATE / freq;
    string->feedback = 0.996;
    assert(string->buf_len <= 1024);
    for (int i = 0; i < string->buf_len; ++i) {
	// fit a single cycle into the buffer
	float t = (float)i / string->buf_len;
	// string->buf[i] = ma_waveform_square_f32(t, 1);
	// string->buf[i] = ma_waveform_sawtooth_f32(t, 1);
	string->buf[i] = (rand() / (float)RAND_MAX - 0.5) * 2;
    }
}

#define MA_TAU_D   6.28318530717958647693
static float ma_waveform_sine_f32(double time, double amplitude)
{
    return (float)(sin(MA_TAU_D * time) * amplitude);
}
static float ma_waveform_triangle_f32(double time, double amplitude)
{
    double f = time - (ma_int64)time;
    double r;

    r = 2 * ma_abs(2 * (f - 0.5)) - 1;

    return (float)(r * amplitude);
}
static float ma_waveform_sawtooth_f32(double time, double amplitude)
{
    double f = time - (ma_int64)time;
    double r;

    r = 2 * (f - 0.5);

    return (float)(r * amplitude);
}
static float ma_waveform_square_f32(double time, double amplitude) {
    double f = time - (ma_int64)time;
    return (f < 0.5) ? amplitude : -amplitude;
}

float lerp(float a, float b, float t) {
    return (b - a) * t + a;
}
typedef float(*WaveformFn)(double, double);
WaveformStatus read_waveform_pcm_frames(
	Waveform *waveform, 
	WaveformEnvelop *envelop, 
	void* pFramesOut, 
	ma_uint64 frameCount, 
	WaveformFn waveform_fn) {
    float* pFramesOutF32 = (float*)pFramesOut;
    WaveformStatus status;
    
    for (int iFrame = 0; iFrame < frameCount; iFrame += 1) {
	float s = waveform_fn(waveform->time, waveform->amplitude);
	waveform->time += waveform->advance;
	float real_t = waveform->time / waveform->frequency;
	if (real_t < envelop->attack) {
	    s *= lerp(0.0, 1.0, (real_t-0)/(envelop->attack-0));
	    status = WAVE_STAT_ATTACK;
	} else if (real_t < envelop->decay) {
	    s *= lerp(1.0, 0.6, (real_t-envelop->attack)/(envelop->decay-envelop->attack));
	    status = WAVE_STAT_DECAY;
	} else if (waveform->is_live) {
	    if (waveform->should_sustain) {
		s *= 0.6;
		status = WAVE_STAT_SUSTAIN;
	    } else if (real_t - envelop->live_sustain.sustain_end_t < envelop->release) {
		s *= lerp(0.6, 0.0, (real_t-envelop->live_sustain.sustain_end_t)/(envelop->release));
		status = WAVE_STAT_RELEASE;
	    } else {
		s = 0;
		status = WAVE_STAT_STOP;
	    }
	} else {
	    if (real_t < envelop->fixed_sustain) {
		s *= 0.6;
		status = WAVE_STAT_SUSTAIN;
	    } else if (real_t < envelop->release) {
		s *= lerp(0.6, 0.0, (real_t-envelop->fixed_sustain)/(envelop->release-envelop->fixed_sustain));
		status = WAVE_STAT_RELEASE;
	    } else {
		s = 0;
		status = WAVE_STAT_STOP;
	    }
	}

	for (int iChannel = 0; iChannel < DEVICE_CHANNELS; iChannel += 1) {
	    pFramesOutF32[iFrame*DEVICE_CHANNELS + iChannel] = s;
	}
    }
    float real_t = waveform->time / waveform->frequency;
    return status;
}
WaveformStatus read_string_pcm_frames(Waveform *waveform, StringNoise *string, float* float_out, int frameCount) {
    float feedback = string->feedback * (waveform->should_sustain ? 1 : 0.9);
    for (int frame_i = 0; frame_i < frameCount; ++frame_i) {
	if (frame_i > 2 * DEVICE_SAMPLE_RATE) return WAVE_STAT_STOP;
	for (int channel_i = 0; channel_i < DEVICE_CHANNELS; ++channel_i) {
	    float_out[frame_i * DEVICE_CHANNELS + channel_i] = string->buf[string->count] * waveform->amplitude;
	}
	int range = 2;
	float sum = 0;
	int len = string->buf_len;
	for (int i = -range; i <= range; ++i) {
	    int idx = ((string->count + i) % len + len) % len;
	    sum += string->buf[idx];
	}
	string->buf[string->count] = sum / (range * 2 + 1) * feedback;

	//printf("sum: %f\n", sum);
	int next = (string->count + 1) % len;
	// int prev = (string->count % len + len) % len;
	// string->buf[string->count] = (string->buf[string->count] + string->buf[next] + string->buf[prev]) / 3 * feedback;
	string->count = next;
    }
    return WAVE_STAT_SUSTAIN;
}







