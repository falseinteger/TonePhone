/**
 * @file tp_audio.c
 * @brief TonePhone Bridge - Audio device management
 *
 * Implements audio device enumeration and selection using CoreAudio.
 * Provides device switching for active calls via baresip.
 */

#include "tp_internal.h"
#include "tp_bridge.h"

#include <re.h>
#include <rem.h>
#include <baresip.h>

#include <string.h>
#include <stdlib.h>

#if defined(__APPLE__)
#include <CoreAudio/CoreAudio.h>
#include <AudioToolbox/AudioToolbox.h>
#endif

/* =============================================================================
 * Module State
 * ============================================================================= */

static struct {
    char current_input[128];   /* Current input device name (empty = default) */
    char current_output[128];  /* Current output device name (empty = default) */
    bool initialized;
#if defined(__APPLE__)
    AudioObjectPropertyListenerBlock device_listener;
#endif
} g_audio = {
    .current_input = "",
    .current_output = "",
    .initialized = false,
};

/* =============================================================================
 * CoreAudio Device Enumeration (Apple platforms)
 * ============================================================================= */

#if defined(__APPLE__)

/**
 * @brief Get the default audio device ID for input or output
 */
static AudioDeviceID get_default_device_id(bool is_input)
{
    AudioDeviceID device_id = kAudioObjectUnknown;
    UInt32 size = sizeof(device_id);

    AudioObjectPropertyAddress addr = {
        .mSelector = is_input ? kAudioHardwarePropertyDefaultInputDevice
                              : kAudioHardwarePropertyDefaultOutputDevice,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };

    OSStatus status = AudioObjectGetPropertyData(
        kAudioObjectSystemObject, &addr, 0, NULL, &size, &device_id);

    if (status != noErr) {
        warning("tp_audio: failed to get default %s device: %d\n",
                is_input ? "input" : "output", (int)status);
        return kAudioObjectUnknown;
    }

    return device_id;
}

/**
 * @brief Get the name of an audio device
 */
static bool get_device_name(AudioDeviceID device_id, char *buf, size_t size)
{
    CFStringRef name = NULL;
    UInt32 prop_size = sizeof(name);

    AudioObjectPropertyAddress addr = {
        .mSelector = kAudioDevicePropertyDeviceNameCFString,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };

    OSStatus status = AudioObjectGetPropertyData(
        device_id, &addr, 0, NULL, &prop_size, &name);

    if (status != noErr || !name) {
        return false;
    }

    Boolean success = CFStringGetCString(name, buf, (CFIndex)size, kCFStringEncodingUTF8);
    CFRelease(name);

    return success;
}

/**
 * @brief Get the UID of an audio device
 */
static bool get_device_uid(AudioDeviceID device_id, char *buf, size_t size)
{
    CFStringRef uid = NULL;
    UInt32 prop_size = sizeof(uid);

    AudioObjectPropertyAddress addr = {
        .mSelector = kAudioDevicePropertyDeviceUID,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };

    OSStatus status = AudioObjectGetPropertyData(
        device_id, &addr, 0, NULL, &prop_size, &uid);

    if (status != noErr || !uid) {
        return false;
    }

    Boolean success = CFStringGetCString(uid, buf, (CFIndex)size, kCFStringEncodingUTF8);
    CFRelease(uid);

    return success;
}

/**
 * @brief Check if device has input or output streams
 */
static bool device_has_scope(AudioDeviceID device_id, bool is_input)
{
    UInt32 size = 0;

    AudioObjectPropertyAddress addr = {
        .mSelector = kAudioDevicePropertyStreams,
        .mScope = is_input ? kAudioObjectPropertyScopeInput
                           : kAudioObjectPropertyScopeOutput,
        .mElement = kAudioObjectPropertyElementMain,
    };

    OSStatus status = AudioObjectGetPropertyDataSize(
        device_id, &addr, 0, NULL, &size);

    return (status == noErr && size > 0);
}

/**
 * @brief Get all audio devices of a given type
 */
static tp_error_t get_devices(tp_audio_device_list_t *out_list, bool is_input)
{
    UInt32 size = 0;
    OSStatus status;

    if (!out_list) {
        return TP_ERR_INVALID_ARG;
    }

    out_list->devices = NULL;
    out_list->count = 0;

    /* Get size of device list */
    AudioObjectPropertyAddress addr = {
        .mSelector = kAudioHardwarePropertyDevices,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };

    status = AudioObjectGetPropertyDataSize(
        kAudioObjectSystemObject, &addr, 0, NULL, &size);

    if (status != noErr) {
        warning("tp_audio: failed to get device list size: %d\n", (int)status);
        return TP_ERR_INTERNAL;
    }

    uint32_t num_devices = size / sizeof(AudioDeviceID);
    if (num_devices == 0) {
        return TP_OK;
    }

    /* Get device IDs */
    AudioDeviceID *device_ids = malloc(size);
    if (!device_ids) {
        return TP_ERR_NO_MEMORY;
    }

    status = AudioObjectGetPropertyData(
        kAudioObjectSystemObject, &addr, 0, NULL, &size, device_ids);

    if (status != noErr) {
        free(device_ids);
        warning("tp_audio: failed to get device list: %d\n", (int)status);
        return TP_ERR_INTERNAL;
    }

    /* Get default device for comparison */
    AudioDeviceID default_device = get_default_device_id(is_input);

    /* Count matching devices first */
    uint32_t matching = 0;
    for (uint32_t i = 0; i < num_devices; i++) {
        if (device_has_scope(device_ids[i], is_input)) {
            matching++;
        }
    }

    if (matching == 0) {
        free(device_ids);
        return TP_OK;
    }

    /* Allocate device list */
    out_list->devices = calloc(matching, sizeof(tp_audio_device_t));
    if (!out_list->devices) {
        free(device_ids);
        return TP_ERR_NO_MEMORY;
    }

    /* Fill in device info */
    uint32_t idx = 0;
    for (uint32_t i = 0; i < num_devices && idx < matching; i++) {
        if (!device_has_scope(device_ids[i], is_input)) {
            continue;
        }

        tp_audio_device_t *dev = &out_list->devices[idx];
        dev->type = is_input ? TP_AUDIO_DEVICE_INPUT : TP_AUDIO_DEVICE_OUTPUT;
        dev->is_default = (device_ids[i] == default_device);

        if (!get_device_name(device_ids[i], dev->name, sizeof(dev->name))) {
            snprintf(dev->name, sizeof(dev->name), "Unknown Device");
        }

        if (!get_device_uid(device_ids[i], dev->uid, sizeof(dev->uid))) {
            snprintf(dev->uid, sizeof(dev->uid), "unknown-%u", device_ids[i]);
        }

        idx++;
    }

    out_list->count = idx;
    free(device_ids);

    return TP_OK;
}

/**
 * @brief Device change listener
 */
static void on_device_change(void)
{
    tp_event_callback_t cb;
    void *ctx;

    tp_get_event_callback(&cb, &ctx);

    if (cb) {
        tp_event_t event = {
            .type = TP_EVENT_AUDIO_DEVICE_CHANGED,
        };
        cb(&event, ctx);
    }

    info("tp_audio: audio devices changed\n");
}


/**
 * @brief Find a device by name
 * @return The device ID, or kAudioObjectUnknown when no device has that name
 */
static AudioDeviceID find_device_id(const char *name, bool is_input)
{
    AudioDeviceID found = kAudioObjectUnknown;
    UInt32 size = 0;
    AudioDeviceID *ids;
    char dev_name[128];

    if (!name || !name[0]) {
        return kAudioObjectUnknown;
    }

    AudioObjectPropertyAddress addr = {
        .mSelector = kAudioHardwarePropertyDevices,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };

    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &addr,
                                       0, NULL, &size) != noErr || !size) {
        return kAudioObjectUnknown;
    }

    ids = malloc(size);
    if (!ids) {
        return kAudioObjectUnknown;
    }

    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr,
                                   0, NULL, &size, ids) == noErr) {
        for (uint32_t i = 0; i < size / sizeof(AudioDeviceID); i++) {
            if (device_has_scope(ids[i], is_input) &&
                get_device_name(ids[i], dev_name, sizeof(dev_name)) &&
                strcmp(dev_name, name) == 0) {
                found = ids[i];
                break;
            }
        }
    }

    free(ids);
    return found;
}

/* =============================================================================
 * Voice Processing Audio Driver ("vpio")
 *
 * baresip's audiounit module opens separate AudioUnits for playback and
 * recording, so the Voice Processing I/O unit could not cancel echo: it can
 * only remove what it plays itself from what it records. This driver runs
 * one VoiceProcessingIO unit per call, shared by the player and the source,
 * which gives echo cancellation, noise suppression and level control.
 * It also honors the selected input and output devices.
 * ============================================================================= */

#define VPIO_MAX_FRAMES 4096

/* The shared unit; exists while a player or source is open */
struct vpio {
    AudioUnit au;
    mtx_t mutex;              /* Held by the I/O callbacks */
    struct auplay_st *play;
    struct ausrc_st *src;
    uint8_t *inbuf;
    AudioDeviceID in_dev;
    AudioDeviceID out_dev;
};

struct auplay_st {
    struct vpio *vp;
    struct auplay_prm prm;
    size_t sampsz;
    uint64_t frames;
    auplay_write_h *wh;
    void *arg;
};

struct ausrc_st {
    struct vpio *vp;
    struct ausrc_prm prm;
    size_t sampsz;
    uint64_t frames;
    ausrc_read_h *rh;
    void *arg;
};

static struct vpio *g_vpio;
static struct auplay *g_vpio_play;
static struct ausrc *g_vpio_src;

static void vpio_stream_format(AudioStreamBasicDescription *fmt,
                               enum aufmt aufmt, uint32_t srate,
                               uint8_t ch, size_t sampsz)
{
    memset(fmt, 0, sizeof(*fmt));
    fmt->mSampleRate = srate;
    fmt->mFormatID = kAudioFormatLinearPCM;
    fmt->mFormatFlags = (aufmt == AUFMT_FLOAT ? kLinearPCMFormatFlagIsFloat
                                              : kLinearPCMFormatFlagIsSignedInteger)
                        | kAudioFormatFlagIsPacked;
    fmt->mBitsPerChannel = (UInt32)(8 * sampsz);
    fmt->mChannelsPerFrame = ch;
    fmt->mBytesPerFrame = (UInt32)(sampsz * ch);
    fmt->mFramesPerPacket = 1;
    fmt->mBytesPerPacket = (UInt32)(sampsz * ch);
}

static OSStatus vpio_input_cb(void *ref, AudioUnitRenderActionFlags *flags,
                              const AudioTimeStamp *ts, UInt32 bus,
                              UInt32 nframes, AudioBufferList *data)
{
    struct vpio *vp = ref;
    struct ausrc_st *st;
    AudioBufferList abl;
    struct auframe af;
    OSStatus ret = noErr;

    (void)data;

    mtx_lock(&vp->mutex);

    st = vp->src;
    if (!st || !st->rh || nframes > VPIO_MAX_FRAMES)
        goto out;

    abl.mNumberBuffers = 1;
    abl.mBuffers[0].mNumberChannels = st->prm.ch;
    abl.mBuffers[0].mDataByteSize = (UInt32)(nframes * st->prm.ch * st->sampsz);
    abl.mBuffers[0].mData = vp->inbuf;

    ret = AudioUnitRender(vp->au, flags, ts, bus, nframes, &abl);
    if (ret != noErr)
        goto out;

    auframe_init(&af, st->prm.fmt, abl.mBuffers[0].mData,
                 abl.mBuffers[0].mDataByteSize / st->sampsz,
                 st->prm.srate, st->prm.ch);
    af.timestamp = st->frames * AUDIO_TIMEBASE / st->prm.srate;
    st->frames += af.sampc / st->prm.ch;

    st->rh(&af, st->arg);

 out:
    mtx_unlock(&vp->mutex);
    return ret;
}

static OSStatus vpio_output_cb(void *ref, AudioUnitRenderActionFlags *flags,
                               const AudioTimeStamp *ts, UInt32 bus,
                               UInt32 nframes, AudioBufferList *data)
{
    struct vpio *vp = ref;
    struct auplay_st *st;

    (void)ts;
    (void)bus;
    (void)nframes;

    mtx_lock(&vp->mutex);

    st = vp->play;
    for (UInt32 i = 0; i < data->mNumberBuffers; i++) {
        AudioBuffer *ab = &data->mBuffers[i];
        struct auframe af;

        if (!st || !st->wh) {
            memset(ab->mData, 0, ab->mDataByteSize);
            *flags |= kAudioUnitRenderAction_OutputIsSilence;
            continue;
        }

        auframe_init(&af, st->prm.fmt, ab->mData,
                     ab->mDataByteSize / st->sampsz,
                     st->prm.srate, st->prm.ch);
        af.timestamp = st->frames * AUDIO_TIMEBASE / st->prm.srate;
        st->frames += af.sampc / st->prm.ch;

        st->wh(&af, st->arg);
    }

    mtx_unlock(&vp->mutex);
    return noErr;
}

/**
 * @brief Log the devices the unit actually uses
 */
static void vpio_log_devices(struct vpio *vp)
{
    AudioDeviceID dev[2] = {kAudioObjectUnknown, kAudioObjectUnknown};
    char name[2][128] = {"?", "?"};

    for (int i = 0; i < 2; i++) {
        UInt32 size = sizeof(dev[i]);
        if (AudioUnitGetProperty(vp->au, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, (AudioUnitElement)i,
                                 &dev[i], &size) == noErr) {
            get_device_name(dev[i], name[i], sizeof(name[i]));
        }
    }

    info("tp_audio: vpio: input '%s', output '%s'\n", name[1], name[0]);
}

/**
 * @brief Apply the open player/source formats and devices, then (re)start
 *
 * Formats and devices can only change while the unit is uninitialized,
 * so every open or close of the player or source restarts the unit.
 */
static int vpio_restart(struct vpio *vp)
{
    AudioStreamBasicDescription fmt;
    OSStatus ret;

    AudioOutputUnitStop(vp->au);
    AudioUnitUninitialize(vp->au);

    if (!vp->play && !vp->src)
        return 0;

    /* Devices: unknown means the system default */
    if (vp->in_dev != kAudioObjectUnknown) {
        ret = AudioUnitSetProperty(vp->au, kAudioOutputUnitProperty_CurrentDevice,
                                   kAudioUnitScope_Global, 1,
                                   &vp->in_dev, sizeof(vp->in_dev));
        if (ret)
            warning("tp_audio: vpio: can't use input device (%d)\n", (int)ret);
    }
    if (vp->out_dev != kAudioObjectUnknown) {
        ret = AudioUnitSetProperty(vp->au, kAudioOutputUnitProperty_CurrentDevice,
                                   kAudioUnitScope_Global, 0,
                                   &vp->out_dev, sizeof(vp->out_dev));
        if (ret)
            warning("tp_audio: vpio: can't use output device (%d)\n", (int)ret);
    }

    /* The side without a stream gets the other side's format */
    if (vp->play)
        vpio_stream_format(&fmt, vp->play->prm.fmt, vp->play->prm.srate,
                           vp->play->prm.ch, vp->play->sampsz);
    else
        vpio_stream_format(&fmt, vp->src->prm.fmt, vp->src->prm.srate,
                           vp->src->prm.ch, vp->src->sampsz);
    ret = AudioUnitSetProperty(vp->au, kAudioUnitProperty_StreamFormat,
                               kAudioUnitScope_Input, 0, &fmt, sizeof(fmt));
    if (ret)
        goto out;

    if (vp->src)
        vpio_stream_format(&fmt, vp->src->prm.fmt, vp->src->prm.srate,
                           vp->src->prm.ch, vp->src->sampsz);
    ret = AudioUnitSetProperty(vp->au, kAudioUnitProperty_StreamFormat,
                               kAudioUnitScope_Output, 1, &fmt, sizeof(fmt));
    if (ret)
        goto out;

    ret = AudioUnitInitialize(vp->au);
    if (ret)
        goto out;

    ret = AudioOutputUnitStart(vp->au);
    if (ret)
        goto out;

    vpio_log_devices(vp);

 out:
    if (ret) {
        warning("tp_audio: vpio: start failed (%d)\n", (int)ret);
        return ENODEV;
    }

    return 0;
}

static void vpio_destructor(void *arg)
{
    struct vpio *vp = arg;

    if (vp->au) {
        AudioOutputUnitStop(vp->au);
        AudioUnitUninitialize(vp->au);
        AudioComponentInstanceDispose(vp->au);
    }

    mem_deref(vp->inbuf);
    mtx_destroy(&vp->mutex);

    if (g_vpio == vp)
        g_vpio = NULL;
}

/**
 * @brief Get the shared unit, creating it for the first stream
 */
static int vpio_get(struct vpio **vpp)
{
    AudioComponentDescription desc = {
        .componentType = kAudioUnitType_Output,
        .componentSubType = kAudioUnitSubType_VoiceProcessingIO,
        .componentManufacturer = kAudioUnitManufacturer_Apple,
    };
    const UInt32 enable = 1;
    const UInt32 max_frames = VPIO_MAX_FRAMES;
    AURenderCallbackStruct cb;
    AudioComponent comp;
    struct vpio *vp;
    OSStatus ret;

    if (g_vpio) {
        *vpp = mem_ref(g_vpio);
        return 0;
    }

    comp = AudioComponentFindNext(NULL, &desc);
    if (!comp) {
        warning("tp_audio: vpio: Voice Processing I/O not found\n");
        return ENOENT;
    }

    vp = mem_zalloc(sizeof(*vp), vpio_destructor);
    if (!vp)
        return ENOMEM;

    vp->in_dev = kAudioObjectUnknown;
    vp->out_dev = kAudioObjectUnknown;

    /* Room for the largest slice: 4096 stereo float frames */
    vp->inbuf = mem_alloc(VPIO_MAX_FRAMES * 2 * sizeof(float), NULL);
    if (!vp->inbuf || mtx_init(&vp->mutex, mtx_plain) != thrd_success) {
        mem_deref(vp);
        return ENOMEM;
    }

    ret = AudioComponentInstanceNew(comp, &vp->au);
    if (ret)
        goto out;

    ret = AudioUnitSetProperty(vp->au, kAudioOutputUnitProperty_EnableIO,
                               kAudioUnitScope_Input, 1, &enable, sizeof(enable));
    if (ret)
        goto out;

    ret = AudioUnitSetProperty(vp->au, kAudioOutputUnitProperty_EnableIO,
                               kAudioUnitScope_Output, 0, &enable, sizeof(enable));
    if (ret)
        goto out;

    AudioUnitSetProperty(vp->au, kAudioUnitProperty_MaximumFramesPerSlice,
                         kAudioUnitScope_Global, 0, &max_frames, sizeof(max_frames));

    /* Keep other apps (music, video) at their volume during calls */
    AUVoiceIOOtherAudioDuckingConfiguration ducking = {
        .mEnableAdvancedDucking = false,
        .mDuckingLevel = kAUVoiceIOOtherAudioDuckingLevelMin,
    };
    AudioUnitSetProperty(vp->au, kAUVoiceIOProperty_OtherAudioDuckingConfiguration,
                         kAudioUnitScope_Global, 0, &ducking, sizeof(ducking));

    cb.inputProc = vpio_input_cb;
    cb.inputProcRefCon = vp;
    ret = AudioUnitSetProperty(vp->au, kAudioOutputUnitProperty_SetInputCallback,
                               kAudioUnitScope_Global, 1, &cb, sizeof(cb));
    if (ret)
        goto out;

    cb.inputProc = vpio_output_cb;
    cb.inputProcRefCon = vp;
    ret = AudioUnitSetProperty(vp->au, kAudioUnitProperty_SetRenderCallback,
                               kAudioUnitScope_Input, 0, &cb, sizeof(cb));

 out:
    if (ret) {
        warning("tp_audio: vpio: setup failed (%d)\n", (int)ret);
        mem_deref(vp);
        return ENODEV;
    }

    info("tp_audio: vpio: voice processing started\n");
    g_vpio = vp;
    *vpp = vp;
    return 0;
}

static void vpio_play_destructor(void *arg)
{
    struct auplay_st *st = arg;
    struct vpio *vp = st->vp;

    if (!vp)
        return;

    mtx_lock(&vp->mutex);
    if (vp->play == st)
        vp->play = NULL;
    mtx_unlock(&vp->mutex);

    vpio_restart(vp);
    mem_deref(vp);
}

static void vpio_src_destructor(void *arg)
{
    struct ausrc_st *st = arg;
    struct vpio *vp = st->vp;

    if (!vp)
        return;

    mtx_lock(&vp->mutex);
    if (vp->src == st)
        vp->src = NULL;
    mtx_unlock(&vp->mutex);

    vpio_restart(vp);
    mem_deref(vp);
}

static int vpio_play_alloc(struct auplay_st **stp, const struct auplay *ap,
                           struct auplay_prm *prm, const char *device,
                           auplay_write_h *wh, void *arg)
{
    struct auplay_st *st;
    int err;

    (void)ap;

    if (!stp || !prm)
        return EINVAL;

    if (prm->fmt != AUFMT_S16LE && prm->fmt != AUFMT_FLOAT)
        return ENOTSUP;

    st = mem_zalloc(sizeof(*st), vpio_play_destructor);
    if (!st)
        return ENOMEM;

    st->prm = *prm;
    st->sampsz = aufmt_sample_size(prm->fmt);
    st->wh = wh;
    st->arg = arg;

    err = vpio_get(&st->vp);
    if (err) {
        mem_deref(st);
        return err;
    }

    mtx_lock(&st->vp->mutex);
    st->vp->play = st;
    st->vp->out_dev = find_device_id(device, false);
    mtx_unlock(&st->vp->mutex);

    err = vpio_restart(st->vp);
    if (err) {
        mem_deref(st);
        return err;
    }

    *stp = st;
    return 0;
}

static int vpio_src_alloc(struct ausrc_st **stp, const struct ausrc *as,
                          struct ausrc_prm *prm, const char *device,
                          ausrc_read_h *rh, ausrc_error_h *errh, void *arg)
{
    struct ausrc_st *st;
    int err;

    (void)as;
    (void)errh;

    if (!stp || !prm)
        return EINVAL;

    if (prm->fmt != AUFMT_S16LE && prm->fmt != AUFMT_FLOAT)
        return ENOTSUP;

    if (prm->ch > 2)
        return ENOTSUP;

    st = mem_zalloc(sizeof(*st), vpio_src_destructor);
    if (!st)
        return ENOMEM;

    st->prm = *prm;
    st->sampsz = aufmt_sample_size(prm->fmt);
    st->rh = rh;
    st->arg = arg;

    err = vpio_get(&st->vp);
    if (err) {
        mem_deref(st);
        return err;
    }

    mtx_lock(&st->vp->mutex);
    st->vp->src = st;
    st->vp->in_dev = find_device_id(device, true);
    mtx_unlock(&st->vp->mutex);

    err = vpio_restart(st->vp);
    if (err) {
        mem_deref(st);
        return err;
    }

    *stp = st;
    return 0;
}

#endif /* __APPLE__ */

/* =============================================================================
 * Audio Device Functions
 * ============================================================================= */

tp_error_t tp_audio_get_input_devices(tp_audio_device_list_t *out_list)
{
#if defined(__APPLE__)
    return get_devices(out_list, true);
#else
    if (!out_list) {
        return TP_ERR_INVALID_ARG;
    }
    out_list->devices = NULL;
    out_list->count = 0;
    return TP_OK;
#endif
}

tp_error_t tp_audio_get_output_devices(tp_audio_device_list_t *out_list)
{
#if defined(__APPLE__)
    return get_devices(out_list, false);
#else
    if (!out_list) {
        return TP_ERR_INVALID_ARG;
    }
    out_list->devices = NULL;
    out_list->count = 0;
    return TP_OK;
#endif
}

void tp_audio_device_list_free(tp_audio_device_list_t *list)
{
    if (list && list->devices) {
        free(list->devices);
        list->devices = NULL;
        list->count = 0;
    }
}

tp_error_t tp_audio_get_current_input(char *buf, size_t size)
{
    if (!buf || size == 0) {
        return TP_ERR_INVALID_ARG;
    }

    pthread_mutex_lock(&g_mutex);
    strncpy(buf, g_audio.current_input, size - 1);
    buf[size - 1] = '\0';
    pthread_mutex_unlock(&g_mutex);

    return TP_OK;
}

tp_error_t tp_audio_get_current_output(char *buf, size_t size)
{
    if (!buf || size == 0) {
        return TP_ERR_INVALID_ARG;
    }

    pthread_mutex_lock(&g_mutex);
    strncpy(buf, g_audio.current_output, size - 1);
    buf[size - 1] = '\0';
    pthread_mutex_unlock(&g_mutex);

    return TP_OK;
}

/**
 * @brief Apply audio device to all active calls
 *
 * Uses baresip's audio_set_source/audio_set_player with the configured
 * driver ("vpio" or "audiounit").
 *
 * @param is_input true for input (microphone), false for output (speaker)
 * @param device_name Device name, or NULL/empty for system default
 * @return TP_OK on success, error code if any call failed to switch
 */
static tp_error_t apply_audio_device_to_calls(bool is_input, const char *device_name)
{
    /* Access the list of UAs via baresip */
    struct list *uas = uag_list();
    struct le *le;
    tp_error_t result = TP_OK;

    if (!uas) {
        return TP_OK;  /* No UAs, nothing to do */
    }

    /* The device is a device name, or NULL for the system default */
    struct config *cfg = conf_config();
    const char *mod = is_input ? cfg->audio.src_mod : cfg->audio.play_mod;
    const char *dev = (device_name && device_name[0] != '\0') ? device_name : NULL;

    /* Iterate through all UAs and get their current call */
    for (le = list_head(uas); le; le = le->next) {
        struct ua *ua = le->data;
        struct call *call = ua_call(ua);

        /* ua_call returns the current call for this UA */
        if (call) {
            struct audio *au = call_audio(call);
            if (au) {
                int err;
                if (is_input) {
                    err = audio_set_source(au, mod, dev);
                    if (err) {
                        warning("tp_audio: failed to set input device: %m\n", err);
                        if (result == TP_OK) {
                            result = TP_ERR_INTERNAL;
                        }
                    } else {
                        info("tp_audio: set input device to '%s'\n",
                             dev ? dev : "(default)");
                    }
                } else {
                    err = audio_set_player(au, mod, dev);
                    if (err) {
                        warning("tp_audio: failed to set output device: %m\n", err);
                        if (result == TP_OK) {
                            result = TP_ERR_INTERNAL;
                        }
                    } else {
                        info("tp_audio: set output device to '%s'\n",
                             dev ? dev : "(default)");
                    }
                }
            }
        }
    }

    return result;
}

tp_error_t tp_audio_set_input_device(const char *device_name)
{
    tp_error_t result;

    pthread_mutex_lock(&g_mutex);

    if (device_name && device_name[0] != '\0') {
        strncpy(g_audio.current_input, device_name, sizeof(g_audio.current_input) - 1);
        g_audio.current_input[sizeof(g_audio.current_input) - 1] = '\0';
    } else {
        g_audio.current_input[0] = '\0';
    }

    pthread_mutex_unlock(&g_mutex);

    /* Apply to active calls and to the config used for new calls -
     * need to enter re thread context */
    re_thread_enter();
    struct config *cfg = conf_config();
    if (cfg) {
        str_ncpy(cfg->audio.src_dev,
                 device_name ? device_name : "",
                 sizeof(cfg->audio.src_dev));
    }
    result = apply_audio_device_to_calls(true, device_name);
    re_thread_leave();

    info("tp_audio: input device set to '%s'\n",
         device_name && device_name[0] ? device_name : "(system default)");

    return result;
}

tp_error_t tp_audio_set_output_device(const char *device_name)
{
    tp_error_t result;

    pthread_mutex_lock(&g_mutex);

    if (device_name && device_name[0] != '\0') {
        strncpy(g_audio.current_output, device_name, sizeof(g_audio.current_output) - 1);
        g_audio.current_output[sizeof(g_audio.current_output) - 1] = '\0';
    } else {
        g_audio.current_output[0] = '\0';
    }

    pthread_mutex_unlock(&g_mutex);

    /* Apply to active calls and to the config used for new calls -
     * need to enter re thread context */
    re_thread_enter();
    struct config *cfg = conf_config();
    if (cfg) {
        str_ncpy(cfg->audio.play_dev,
                 device_name ? device_name : "",
                 sizeof(cfg->audio.play_dev));
    }
    result = apply_audio_device_to_calls(false, device_name);
    re_thread_leave();

    info("tp_audio: output device set to '%s'\n",
         device_name && device_name[0] ? device_name : "(system default)");

    return result;
}

/* =============================================================================
 * Lifecycle Functions
 * ============================================================================= */

tp_error_t tp_audio_init(void)
{
    if (g_audio.initialized) {
        return TP_OK;
    }

#if defined(__APPLE__)
    /* Register for device change notifications */
    AudioObjectPropertyAddress addr = {
        .mSelector = kAudioHardwarePropertyDevices,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };

    /* Create block and copy to heap (stack blocks become dangling after function returns) */
    AudioObjectPropertyListenerBlock block = ^(UInt32 inNumberAddresses,
                                                const AudioObjectPropertyAddress *inAddresses) {
        (void)inNumberAddresses;
        (void)inAddresses;
        on_device_change();
    };
    g_audio.device_listener = Block_copy(block);

    OSStatus status = AudioObjectAddPropertyListenerBlock(
        kAudioObjectSystemObject, &addr,
        dispatch_get_main_queue(), g_audio.device_listener);

    if (status != noErr) {
        warning("tp_audio: failed to register device listener: %d\n", (int)status);
        /* Not fatal - continue without hot-plug detection */
    }

    /* The voice processing driver; the config picks it or audiounit */
    int err = auplay_register(&g_vpio_play, baresip_auplayl(), "vpio", vpio_play_alloc);
    err |= ausrc_register(&g_vpio_src, baresip_ausrcl(), "vpio", vpio_src_alloc);
    if (err) {
        warning("tp_audio: failed to register vpio driver: %m\n", err);
    }
#endif

    g_audio.initialized = true;
    info("tp_audio: initialized\n");

    return TP_OK;
}

void tp_audio_close(void)
{
    if (!g_audio.initialized) {
        return;
    }

#if defined(__APPLE__)
    /* Remove device change listener */
    if (g_audio.device_listener) {
        AudioObjectPropertyAddress addr = {
            .mSelector = kAudioHardwarePropertyDevices,
            .mScope = kAudioObjectPropertyScopeGlobal,
            .mElement = kAudioObjectPropertyElementMain,
        };

        AudioObjectRemovePropertyListenerBlock(
            kAudioObjectSystemObject, &addr,
            dispatch_get_main_queue(), g_audio.device_listener);

        Block_release(g_audio.device_listener);
        g_audio.device_listener = NULL;
    }

    g_vpio_src = mem_deref(g_vpio_src);
    g_vpio_play = mem_deref(g_vpio_play);
#endif

    g_audio.current_input[0] = '\0';
    g_audio.current_output[0] = '\0';
    g_audio.initialized = false;

    info("tp_audio: closed\n");
}

tp_error_t tp_audio_set_echo_cancellation(bool enabled)
{
    const char *mod = enabled ? "vpio" : "audiounit";
    struct config *cfg;

    re_thread_enter();
    cfg = conf_config();
    if (cfg) {
        str_ncpy(cfg->audio.src_mod, mod, sizeof(cfg->audio.src_mod));
        str_ncpy(cfg->audio.play_mod, mod, sizeof(cfg->audio.play_mod));
    }
    re_thread_leave();

    if (!cfg) {
        return TP_ERR_NOT_INITIALIZED;
    }

    info("tp_audio: echo cancellation %s (from the next call)\n",
         enabled ? "on" : "off");
    return TP_OK;
}
