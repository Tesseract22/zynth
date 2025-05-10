//#define MA_NO_DECODING
//#define MA_NO_ENCODING
//#define MINIAUDIO_IMPLEMENTATION
//#include "miniaudio.h"
#include <stdio.h> 
#include <math.h>
#include <stdlib.h>
#include <assert.h>
#include "raylib.h"
#include "external/miniaudio.h"

#define ma_abs(x)                       (((x) > 0) ? (x) : -(x))
#define RINGBUF_SIZE 500
typedef struct {
    size_t head, tail, count;
    float data[RINGBUF_SIZE];
} RingBuffer;
typedef struct {
    char key;
    int note;
} KeyNote;
#define RingBuffer_At(rb, i) (rb).data[((rb).head + i) % (rb).count]
void RingBuffer_Append(RingBuffer *rb, float el) {
    rb->tail = (rb->tail + 1) % RINGBUF_SIZE;
    if (rb->tail == rb->head) {
	rb->head = (rb->head + 1) % RINGBUF_SIZE;
    } else {
	rb->count += 1;
    }
    rb->data[rb->tail] = el;
}
#define foreach_rb(rb, i) for (size_t i = (rb).head; i != (rb).tail; i = (i + 1) % RINGBUF_SIZE)

#define WAVEFORM_RECORD_GRANULARITY 20
RingBuffer waveform_record = {0};

ma_waveform_config ma_waveform_config_init(ma_format format, ma_uint32 channels, ma_uint32 sampleRate, ma_waveform_type type, double amplitude, double frequency)
{
    ma_waveform_config config = {0};

    config.format     = format;
    config.channels   = channels;
    config.sampleRate = sampleRate;
    config.type       = type;
    config.amplitude  = amplitude;
    config.frequency  = frequency;

    return config;
}
static double ma_waveform__calculate_advance(ma_uint32 sampleRate, double frequency)
{
    return (1.0 / (sampleRate / frequency));
}

#define DEVICE_FORMAT       ma_format_f32
#define DEVICE_CHANNELS     1
#define DEVICE_SAMPLE_RATE  48000
#define WAVEFORM_POOL_LEN 32

typedef struct {
    double advance;
    double time;
    double amplitude;
    double frequency;
    bool should_sustain;
    bool is_live;
} Waveform;
void waveform_init(Waveform *waveform, double amp, double freq, unsigned sample_rate, bool is_live) {
    waveform->amplitude = amp;
    waveform->frequency = freq;
    waveform->advance = ma_waveform__calculate_advance(sample_rate, freq);
    waveform->time    = 0;
    waveform->is_live = is_live;
    waveform->should_sustain = true;
}
typedef struct {
    float sustain_end_t;
} LiveSustain;
typedef struct {
    float attack;
    float decay;
    float release;
    union {
	LiveSustain live_sustain;
	float fixed_sustain;
    };
} WaveformEnvelop;
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
typedef enum {
    WAVE_STAT_ATTACK,
    WAVE_STAT_DECAY,
    WAVE_STAT_SUSTAIN,
    WAVE_STAT_RELEASE,
    WAVE_STAT_STOP,
} WaveformStatus;
typedef struct {
    float buf[1024];
    int count;
    int buf_len;
    float feedback;
} StringNoise;
void stringnoise_init(StringNoise *string, double freq) {
    string->count = 0;
    string->buf_len = DEVICE_SAMPLE_RATE / freq;
    string->feedback = 0.9999;
    assert(string->buf_len <= 1024);
    for (int i = 0; i < string->buf_len; ++i) {
	string->buf[i] = (rand() / (float)RAND_MAX - 0.5) * 2;
    }
}
typedef enum {
    TONE_SINE,
    TONE_TRIANGLE,
    TONE_SAWTOOTH,
    TONE_STRING,
    TONE_LEN,
} Tone;
typedef struct {
    Waveform waveform;
    union {
	WaveformEnvelop envelop;
	StringNoise string;
    };
} Key;

typedef struct {
    Key keys[WAVEFORM_POOL_LEN];
    int octave;
    Tone tone;
} KeyBoard;

void keyboard_init(KeyBoard *keyboard, ma_device *device) {
    for (int i = 0; i < WAVEFORM_POOL_LEN; ++i) {
	waveform_init(&keyboard->keys[i].waveform, 0, 220, device->sampleRate, true);
    } 
    keyboard->octave = 0;
    keyboard->tone = TONE_SINE;
}
void keyboard_listen_input(KeyBoard* keyboard, ma_device *device) {

#define KN(k, n) (KeyNote) {.key = (k), .note = (n)}
    static const KeyNote keynote_map[] = {
	KN(KEY_Q, 		0),
	KN(KEY_TWO, 	1),
	KN(KEY_W, 		2),
	KN(KEY_THREE,	3),
	KN(KEY_E,		4),
	KN(KEY_R,		5),
	KN(KEY_FIVE,	6),
	KN(KEY_T,		7),
	KN(KEY_SIX,		8),
	KN(KEY_Y,		9),
	KN(KEY_SEVEN,	10),
	KN(KEY_U,		11),
	KN(KEY_I,		12),
	KN(KEY_NINE,	13),
	KN(KEY_O,		14),
	KN(KEY_ZERO,	15),
	KN(KEY_P,		16),
    };
    int keynote_map_len = sizeof(keynote_map)/sizeof(KeyNote);
    for (int key = 0; key < keynote_map_len; ++key) {
	WaveformEnvelop *envelop = &keyboard->keys[key].envelop;
	StringNoise *string = &keyboard->keys[key].string;
	Waveform *waveform = &keyboard->keys[key].waveform;
	KeyNote kn = keynote_map[key];

	double freq = 261.63 * exp2((double)kn.note/12 + keyboard->octave);
	if (IsKeyPressed(kn.key)) {
	    waveform_init(waveform, 0.2, freq, device->sampleRate, true);
	    switch (keyboard->tone) {
		case TONE_SINE:
		case TONE_TRIANGLE:
		case TONE_SAWTOOTH:
		    *envelop = init_envelop_live(0.05, 0.05, 0.10);
		    break;
		case TONE_STRING:
		    stringnoise_init(string, freq);
		    break;
		default:
		    assert(false && "Unknown Tone");
	    }
	}
	if (IsKeyReleased(kn.key)) {
	    waveform->should_sustain = false;
	    //printf("key release %f\n", envelop->sustain_end_t);
	    switch (keyboard->tone) {
		case TONE_SINE:
		case TONE_TRIANGLE:
		case TONE_SAWTOOTH:
		    envelop->live_sustain.sustain_end_t = fmax(waveform->time / freq, envelop->decay);
		    break;
		case TONE_STRING:
		    break;
		default:
		    assert(false && "Unknown Tone");
	    }
	}
    }
    if (IsKeyReleased(KEY_LEFT_SHIFT)) keyboard->octave += 1;
    if (IsKeyReleased(KEY_LEFT_CONTROL)) keyboard->octave -= 1;

    if (IsKeyReleased(KEY_LEFT_ALT)) keyboard->tone = (keyboard->tone + 1) % TONE_LEN;
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
	int next = (string->count + 1) % string->buf_len;

	string->buf[string->count] = (string->buf[string->count] + string->buf[next]) / 2 * feedback;
	string->count = next;
    }
    return WAVE_STAT_SUSTAIN;
}
void keyboard_callback(KeyBoard *keyboard, float *float_out, ma_uint32 frameCount) {
    float tmp[4096] = {0};
    assert(4096 >= frameCount * DEVICE_CHANNELS);
    for (int i = 0; i < WAVEFORM_POOL_LEN; ++i) {
	Waveform *waveform = &keyboard->keys[i].waveform;
	if (waveform->amplitude <= 0) {
	    continue;
	}
	WaveformStatus status;
	switch (keyboard->tone) {
	    case TONE_SINE:
		status = read_waveform_pcm_frames(waveform, &keyboard->keys[i].envelop, tmp, frameCount, ma_waveform_sine_f32);
		break;
	    case TONE_TRIANGLE:
		status = read_waveform_pcm_frames(waveform, &keyboard->keys[i].envelop, tmp, frameCount, ma_waveform_triangle_f32);
		break;
	    case TONE_SAWTOOTH:
		status = read_waveform_pcm_frames(waveform, &keyboard->keys[i].envelop, tmp, frameCount, ma_waveform_sawtooth_f32);
		break;

	    case TONE_STRING:
		status = read_string_pcm_frames(waveform, &keyboard->keys[i].string, tmp, frameCount);
		break;
	    default:
		assert(false && "Unknown Tone");
	}
	for (int frame_i = 0; frame_i < frameCount * DEVICE_CHANNELS; ++frame_i) {
	    float_out[frame_i] += tmp[frame_i];
	}
	if (status == WAVE_STAT_STOP) {
	    waveform->amplitude = 0;
	}

    }
}
void data_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount)
{
    (void)pInput;   /* Unused. */

    //printf("advance %f, time %f\n", pSineWave->advance, pSineWave->time);
    // cycle_len = 2*pi/MA_TAU_D
    KeyBoard *keyboard = pDevice->pUserData;
    float *float_out = (float*)pOutput;
    assert(4096 >= frameCount * DEVICE_CHANNELS);
    
    for (int k = 0; k < 2; ++k) {
	keyboard_callback(&keyboard[k], float_out, frameCount);
    }


    float window_sum = 0;
    for (int frame_i = 0; frame_i < frameCount; ++frame_i) {
	window_sum += float_out[frame_i * DEVICE_CHANNELS]; // only cares about the first channel
	if ((frame_i+1) % WAVEFORM_RECORD_GRANULARITY == 0) { // TODO: checks for unused frame at the end
	    RingBuffer_Append(&waveform_record, window_sum/WAVEFORM_RECORD_GRANULARITY);
	    window_sum = 0;
	}
    }
    // if (pDevice->pUserData) fwrite(float_out, 1, sizeof(float) * frameCount * DEVICE_CHANNELS, pDevice->pUserData);

}




int main(int argc, char** argv)
{
    ma_device_config deviceConfig;
    ma_device device;
    KeyBoard keyboards[2];
    for (int k = 0; k < 2; ++k) {
	keyboard_init(&keyboards[k], &device);
    }
    FILE *out = fopen("output.ppm", "wb");

    deviceConfig = ma_device_config_init(ma_device_type_playback);
    deviceConfig.playback.format   = DEVICE_FORMAT;
    deviceConfig.playback.channels = DEVICE_CHANNELS;
    deviceConfig.sampleRate        = DEVICE_SAMPLE_RATE;
    deviceConfig.dataCallback      = data_callback;
    deviceConfig.pUserData         = &keyboards;

    if (ma_device_init(NULL, &deviceConfig, &device) != MA_SUCCESS) {
	printf("Failed to open playback device.\n");
	return -4;
    }

    printf("Device Name: %s\n", device.playback.name);



    if (ma_device_start(&device) != MA_SUCCESS) {
	printf("Failed to start playback device.\n");
	ma_device_uninit(&device);
	return -5;
    }

#ifdef __EMSCRIPTEN__
    emscripten_set_main_loop(main_loop__em, 0, 1);
#else
    int should_quit = 0;
    //int notes[] = {0, 2, 4, 5, 7, 9, 11, 12, 14, 16};
    int WINDOW_W = 1920;
    int WINDOW_H = 1080;
    InitWindow(WINDOW_W, WINDOW_H, "MIDI");
    SetTargetFPS(60);
    int bpm = 120;
    double t = 0;
    int count = 0;
    int octave = 0;
    int progression[][3] = {
	{2, 5, 9},
	{7, 11, 14},
	{0, 4, 7},
	{0, 4, 7},
    };
    while (!WindowShouldClose()) {
	double dt = GetFrameTime();
	if (t <= 0) {
	    t += 60.0/bpm * 4;
	    for (int n = 0; n < 3; ++n) {
		int num = progression[count][n];
		float freq = 261.63 * exp2(num/12.0) / 2;
		waveform_init(&keyboards[1].keys[n].waveform, 0.2, freq, DEVICE_SAMPLE_RATE, false);
		keyboards[1].keys[n].envelop = init_envelop_fixed(0.05, 0.05, (60.0/(bpm))*2-0.15, 0.05);

	    }
	    count = (count + 1) % 4;
	}
	t -= dt;
	BeginDrawing();
	{
	    ClearBackground(WHITE);
	    DrawLine(0, WINDOW_H/2, WINDOW_W, WINDOW_H/2, (Color) {.r = 0, .g = 0, .b = 0, .a = 0x7f});
	    float rect_w = (float)WINDOW_W/RINGBUF_SIZE;
	    for (int i = 0; i < RINGBUF_SIZE-1; ++i) {
		float amp1 = RingBuffer_At(waveform_record, i);
		float amp2 = RingBuffer_At(waveform_record, i+1);
		float h1 = (float)WINDOW_H/2 * amp1;
		float h2 = (float)WINDOW_H/2 * amp2;
		DrawLineV(
			(Vector2) {.x = i * rect_w, .y = (float)WINDOW_H/2-h1}, 
			(Vector2) {.x = (i+1) * rect_w, .y = (float)WINDOW_H/2-h2},
			RED
			);
	    }
	}
	EndDrawing();
	keyboard_listen_input(&keyboards[0], &device);
    }
#endif
    CloseWindow();
    ma_device_uninit(&device);
    fclose(out);

    (void)argc;
    (void)argv;
    return 0;
}
