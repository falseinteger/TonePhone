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
 * Uses baresip's audio_set_source/audio_set_player with "audiounit" module.
 */
static void apply_audio_device_to_calls(bool is_input, const char *device_name)
{
    /* Access the list of UAs via baresip */
    struct list *uas = uag_list();
    struct le *le;

    if (!uas) {
        return;
    }

    /* For audiounit module, device is specified as:
     * - Empty string or NULL: use system default
     * - Device name: use specific device
     *
     * The format for baresip audio functions is "module,device"
     */
    char device_spec[256];
    if (device_name && device_name[0] != '\0') {
        snprintf(device_spec, sizeof(device_spec), "audiounit,%s", device_name);
    } else {
        snprintf(device_spec, sizeof(device_spec), "audiounit");
    }

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
                    err = audio_set_source(au, device_spec, device_name);
                    if (err) {
                        warning("tp_audio: failed to set input device: %m\n", err);
                    } else {
                        info("tp_audio: set input device to '%s'\n",
                             device_name && device_name[0] ? device_name : "(default)");
                    }
                } else {
                    err = audio_set_player(au, device_spec, device_name);
                    if (err) {
                        warning("tp_audio: failed to set output device: %m\n", err);
                    } else {
                        info("tp_audio: set output device to '%s'\n",
                             device_name && device_name[0] ? device_name : "(default)");
                    }
                }
            }
        }
    }
}

tp_error_t tp_audio_set_input_device(const char *device_name)
{
    pthread_mutex_lock(&g_mutex);

    if (device_name && device_name[0] != '\0') {
        strncpy(g_audio.current_input, device_name, sizeof(g_audio.current_input) - 1);
        g_audio.current_input[sizeof(g_audio.current_input) - 1] = '\0';
    } else {
        g_audio.current_input[0] = '\0';
    }

    pthread_mutex_unlock(&g_mutex);

    /* Apply to active calls - need to enter re thread context */
    re_thread_enter();
    apply_audio_device_to_calls(true, device_name);
    re_thread_leave();

    info("tp_audio: input device set to '%s'\n",
         device_name && device_name[0] ? device_name : "(system default)");

    return TP_OK;
}

tp_error_t tp_audio_set_output_device(const char *device_name)
{
    pthread_mutex_lock(&g_mutex);

    if (device_name && device_name[0] != '\0') {
        strncpy(g_audio.current_output, device_name, sizeof(g_audio.current_output) - 1);
        g_audio.current_output[sizeof(g_audio.current_output) - 1] = '\0';
    } else {
        g_audio.current_output[0] = '\0';
    }

    pthread_mutex_unlock(&g_mutex);

    /* Apply to active calls - need to enter re thread context */
    re_thread_enter();
    apply_audio_device_to_calls(false, device_name);
    re_thread_leave();

    info("tp_audio: output device set to '%s'\n",
         device_name && device_name[0] ? device_name : "(system default)");

    return TP_OK;
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

    g_audio.device_listener = ^(UInt32 inNumberAddresses,
                                 const AudioObjectPropertyAddress *inAddresses) {
        (void)inNumberAddresses;
        (void)inAddresses;
        on_device_change();
    };

    OSStatus status = AudioObjectAddPropertyListenerBlock(
        kAudioObjectSystemObject, &addr,
        dispatch_get_main_queue(), g_audio.device_listener);

    if (status != noErr) {
        warning("tp_audio: failed to register device listener: %d\n", (int)status);
        /* Not fatal - continue without hot-plug detection */
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
#endif

    g_audio.current_input[0] = '\0';
    g_audio.current_output[0] = '\0';
    g_audio.initialized = false;

    info("tp_audio: closed\n");
}
