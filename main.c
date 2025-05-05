
//#define MA_NO_DECODING
//#define MA_NO_ENCODING
//#define MINIAUDIO_IMPLEMENTATION
//#include "miniaudio.h"
#include <stdio.h>
#include <math.h>
#include "raylib.h"
#include "external/miniaudio.h"
#ifdef __EMSCRIPTEN__
#include <emscripten.h>

void main_loop__em()
{
}
#endif

#define DEVICE_FORMAT       ma_format_f32
#define DEVICE_CHANNELS     2
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
	    break;
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
    int notes[] = {0, 2, 4, 5, 7, 9, 11, 12};

    InitWindow(600, 800, "MIDI");
    while (!WindowShouldClose()) {
	BeginDrawing();
	ClearBackground(RED);
	EndDrawing();
	for (int key = 1; key <= 9; ++key) {
	    WaveformEnvelop *envelop = &envelops[key - 1];
	    ma_waveform *waveform = &waveforms_pool[key - 1];
	    if (IsKeyPressed(KEY_ZERO + key)) {
		sineWaveConfig = ma_waveform_config_init(device.playback.format, device.playback.channels, device.sampleRate, ma_waveform_type_sine, 0.2, 440 * exp2((double)notes[key - 1]/12));
		ma_waveform_init(&sineWaveConfig, waveform);
		*envelop = init_envelop(0.05, 0.05, 0.05);
		envelop->should_sustain = 1;
	    }
	    if (IsKeyReleased(KEY_ZERO + key)) {
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
