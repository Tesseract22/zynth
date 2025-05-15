#pragma once
#include <stdio.h> 
#include <math.h>
#include <stdlib.h>
#include <assert.h>
#include "raylib.h"
#include "external/miniaudio.h"
#define ma_abs(x)                       (((x) > 0) ? (x) : -(x))
#define RINGBUF_SIZE 500
#define WAVEFORM_POOL_LEN 32
typedef struct {
    double advance;
    double time;
    double amplitude;
    double frequency;
    bool should_sustain;
    bool is_live;
} Waveform;

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



typedef struct {
    size_t head, tail, count;
    float data[RINGBUF_SIZE];
} RingBuffer;
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




void waveform_init(Waveform *waveform, double amp, double freq, unsigned sample_rate, bool is_live);
void data_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount);


#define RingBuffer_At(rb, i) (rb).data[((rb).head + i) % (rb).count]
void RingBuffer_Append(RingBuffer *rb, float el);


extern RingBuffer waveform_record;

void stringnoise_init(StringNoise *string, double freq);
WaveformEnvelop init_envelop_fixed(float attack, float decay, float sustain, float release);
WaveformEnvelop init_envelop_live(float attack, float decay, float release);
