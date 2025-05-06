
//#define MA_NO_DECODING
//#define MA_NO_ENCODING
//#define MINIAUDIO_IMPLEMENTATION
//#include "miniaudio.h"
#include <stdio.h> 
#include <math.h>
#include "raylib.h"
#include "external/miniaudio.h"

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
#ifdef __EMSCRIPTEN__
#include <emscripten.h>

void main_loop__em()
{
}
#endif
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
MA_API ma_result ma_waveform_init(const ma_waveform_config* pConfig, ma_waveform* pWaveform)
{
    ma_result result;

    if (pWaveform == NULL) {
        return MA_INVALID_ARGS;
    }
    pWaveform->config  = *pConfig;
    pWaveform->advance = ma_waveform__calculate_advance(pWaveform->config.sampleRate, pWaveform->config.frequency);
    pWaveform->time    = 0;

    return MA_SUCCESS;
}
#define DEVICE_FORMAT       ma_format_f32
#define DEVICE_CHANNELS     1
#define DEVICE_SAMPLE_RATE  48000
#define WAVEFORM_POOL_LEN 16
typedef struct {
    float attack;
    float decay;
    float release;
    int should_sustain;
    float sustain_end_t;
} WaveformEnvelop;
typedef enum {
    WAVE_STAT_ATTACK,
    WAVE_STAT_DECAY,
    WAVE_STAT_SUSTAIN,
    WAVE_STAT_RELEASE,
    WAVE_STAT_STOP,
} WaveformStatus;

ma_waveform waveforms_pool[WAVEFORM_POOL_LEN] = {0};
WaveformEnvelop envelops[WAVEFORM_POOL_LEN] = {0};

#define MA_TAU_D   6.28318530717958647693
static float ma_waveform_sine_f32(double time, double amplitude)
{
    return (float)(sin(MA_TAU_D * time) * amplitude);
}
WaveformEnvelop init_envelop(float attack, float decay, float release) {
    return (WaveformEnvelop) {
	.attack = attack,
	.decay = attack + decay,
	.release = release,
    };
}
float lerp(float a, float b, float t) {
    return (b - a) * t + a;
}
WaveformStatus read_sine_pcm_frames(ma_waveform* pWaveform, WaveformEnvelop envelop, void* pFramesOut, ma_uint64 frameCount) {
    float* pFramesOutF32 = (float*)pFramesOut;
    for (int iFrame = 0; iFrame < frameCount; iFrame += 1) {
	float s = ma_waveform_sine_f32(pWaveform->time, pWaveform->config.amplitude);
	pWaveform->time += pWaveform->advance;
	float real_t = pWaveform->time / pWaveform->config.frequency;
	if (real_t < envelop.attack) {
	    s *= lerp(0.0, 1.0, (real_t-0)/(envelop.attack-0));
	} else if (real_t < envelop.decay) {
	    s *= lerp(1.0, 0.6, (real_t-envelop.attack)/(envelop.decay-envelop.attack));
	} else if (envelop.should_sustain) {
	    s *= 0.6;
	} else if (real_t - envelop.sustain_end_t < envelop.release) {
	    s *= lerp(0.6, 0.0, (real_t-envelop.sustain_end_t)/(envelop.release));
	} else {
	    s = 0;
	}
	
	for (int iChannel = 0; iChannel < pWaveform->config.channels; iChannel += 1) {
	    pFramesOutF32[iFrame*pWaveform->config.channels + iChannel] = s;
	}
    }
    float real_t = pWaveform->time / pWaveform->config.frequency;
    if (real_t < envelop.attack) {
	return WAVE_STAT_ATTACK;
    } else if (real_t < envelop.decay) {
	return WAVE_STAT_DECAY;
    } else if (envelop.should_sustain) {
	return WAVE_STAT_SUSTAIN;
    } else if (real_t - envelop.sustain_end_t < envelop.release) {
	return WAVE_STAT_RELEASE;
    } else {
	return WAVE_STAT_STOP;
    }
}
void data_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount)
{
    (void)pInput;   /* Unused. */

    //printf("advance %f, time %f\n", pSineWave->advance, pSineWave->time);
    // cycle_len = 2*pi/MA_TAU_D
    float tmp[4096] = {0};
    float *float_out = (float*)pOutput;
    for (int i = 0; i < WAVEFORM_POOL_LEN; ++i) {
	ma_waveform *pSineWave = &waveforms_pool[i];
	if (pSineWave->config.amplitude <= 0) {
	    continue;
	}
	WaveformStatus status = read_sine_pcm_frames(pSineWave, envelops[i], tmp, frameCount);
	for (int frame_i = 0; frame_i < frameCount * pSineWave->config.channels; ++frame_i) {
	    float_out[frame_i] += tmp[frame_i];
	}
	if (status == WAVE_STAT_STOP) {
	    pSineWave->config.amplitude = 0;
	} else if (status == WAVE_STAT_RELEASE) {
	}
    }
    float window_sum = 0;
    for (int frame_i = 0; frame_i < frameCount; ++frame_i) {
	window_sum += float_out[frame_i * DEVICE_CHANNELS]; // only cares about the first channel
	if ((frame_i+1) % WAVEFORM_RECORD_GRANULARITY == 0) { // TODO: checks for unused frame at the end
	    RingBuffer_Append(&waveform_record, window_sum/WAVEFORM_RECORD_GRANULARITY);
	    window_sum = 0;
	}
    }

}

int main(int argc, char** argv)
{
    ma_device_config deviceConfig;
    ma_device device;
    ma_waveform_config sineWaveConfig;

    deviceConfig = ma_device_config_init(ma_device_type_playback);
    deviceConfig.playback.format   = DEVICE_FORMAT;
    deviceConfig.playback.channels = DEVICE_CHANNELS;
    deviceConfig.sampleRate        = DEVICE_SAMPLE_RATE;
    deviceConfig.dataCallback      = data_callback;
    deviceConfig.pUserData         = NULL;

    if (ma_device_init(NULL, &deviceConfig, &device) != MA_SUCCESS) {
	printf("Failed to open playback device.\n");
	return -4;
    }

    printf("Device Name: %s\n", device.playback.name);

    sineWaveConfig = ma_waveform_config_init(device.playback.format, device.playback.channels, device.sampleRate, ma_waveform_type_sine, 0, 220);
    for (int i = 0; i < WAVEFORM_POOL_LEN; ++i) {
	ma_waveform_init(&sineWaveConfig, &waveforms_pool[i]);
    }

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
    while (!WindowShouldClose()) {
	BeginDrawing();
	{
	    ClearBackground(WHITE);
	    //DrawLine(0, WINDOW_H/2, WINDOW_W, WINDOW_H/2, (Color) {.r = 0, .g = 0, .b = 0, .a = 0x7f});
	    float rect_w = (float)WINDOW_W/RINGBUF_SIZE;
	    //for (int i = 0; i < RINGBUF_SIZE; ++i) {
	    //    float amp = RingBuffer_At(waveform_record, i);
	    //    //int h = GetRandomValue(-WINDOW_W/3, WINDOW_H/3);
	    //    int h = (float)WINDOW_H/3 * amp;
	    //    if (h > 0) {
	    //        DrawRectangle(i * rect_w, WINDOW_H/2-h, rect_w, h, RED);
	    //    } else {
	    //        DrawRectangle(i * rect_w, WINDOW_H/2, rect_w, -h, RED);
	    //    }
	    //}
	    for (int i = 0; i < RINGBUF_SIZE-1; ++i) {
		float amp1 = RingBuffer_At(waveform_record, i);
		float amp2 = RingBuffer_At(waveform_record, i+1);
		float h1 = (float)WINDOW_W/2 * amp1;
		float h2 = (float)WINDOW_W/2 * amp2;
		DrawLineV(
			(Vector2) {.x = i * rect_w, .y = (float)WINDOW_H/2-h1}, 
			(Vector2) {.x = (i+1) * rect_w, .y = (float)WINDOW_H/2-h2},
			RED
			);
	    }
	}
	EndDrawing();
#define KN(k, n) (KeyNote) {.key = (k), .note = (n)}
	KeyNote keynote_map[] = {
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
	};
	int keynote_map_len = sizeof(keynote_map)/sizeof(KeyNote);
	for (int key = 0; key < keynote_map_len; ++key) {
	    WaveformEnvelop *envelop = &envelops[key];
	    ma_waveform *waveform = &waveforms_pool[key];
	    KeyNote kn = keynote_map[key];
	    if (IsKeyPressed(kn.key)) {
		printf("pressed %i\n", kn.key);
		sineWaveConfig = ma_waveform_config_init(
			device.playback.format, 
			device.playback.channels, 
			device.sampleRate, 
			ma_waveform_type_sine, 
			0.2, 
			261.63 * exp2((double)kn.note/12));
		ma_waveform_init(&sineWaveConfig, waveform);
		*envelop = init_envelop(0.05, 0.05, 0.25);
		envelop->should_sustain = 1;
	    }
	    if (IsKeyReleased(kn.key)) {
		envelop->should_sustain = 0;
		envelop->sustain_end_t = fmax(waveform->time / waveform->config.frequency, envelop->decay);
		//printf("key release %f\n", envelop->sustain_end_t);
	    }
	}
    }
#endif
    CloseWindow();
    ma_device_uninit(&device);


    (void)argc;
    (void)argv;
    return 0;
}
