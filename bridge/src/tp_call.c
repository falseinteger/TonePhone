/**
 * @file tp_call.c
 * @brief TonePhone Bridge - Call control implementation
 *
 * Implements call lifecycle functions wrapping baresip's call system.
 */

#include "tp_internal.h"
#include "tp_bridge.h"

#include <re.h>
#include <baresip.h>

#include <string.h>
#include <stdlib.h>

/* Enable verbose call debugging (set to 1 for detailed SDP/call dumps) */
#ifndef TP_VERBOSE_CALL_DEBUG
#define TP_VERBOSE_CALL_DEBUG 0
#endif

/* =============================================================================
 * Constants
 * ============================================================================= */

#define MAX_CALLS 8

/* =============================================================================
 * Module State
 * ============================================================================= */

/**
 * @brief Call entry mapping our IDs to baresip calls
 */
typedef struct {
    tp_call_id_t id;
    struct call *call;
    bool in_use;
    bool muted;
} call_entry_t;

static struct {
    call_entry_t calls[MAX_CALLS];
    tp_call_id_t next_id;
} g_calls = {
    .next_id = 1,  /* Start at 1, 0 is invalid */
};

/* =============================================================================
 * Internal Helpers
 * ============================================================================= */

/**
 * @brief Find a call entry by ID
 */
static call_entry_t *find_call(tp_call_id_t id)
{
    for (int i = 0; i < MAX_CALLS; i++) {
        if (g_calls.calls[i].in_use && g_calls.calls[i].id == id) {
            return &g_calls.calls[i];
        }
    }
    return NULL;
}

/**
 * @brief Find a free call slot
 */
static call_entry_t *find_free_slot(void)
{
    for (int i = 0; i < MAX_CALLS; i++) {
        if (!g_calls.calls[i].in_use) {
            return &g_calls.calls[i];
        }
    }
    return NULL;
}

/**
 * @brief Find a call entry by baresip call pointer
 */
static call_entry_t *find_call_by_ptr(const struct call *call)
{
    for (int i = 0; i < MAX_CALLS; i++) {
        if (g_calls.calls[i].in_use && g_calls.calls[i].call == call) {
            return &g_calls.calls[i];
        }
    }
    return NULL;
}

/* =============================================================================
 * Call Functions
 * ============================================================================= */

static tp_error_t call_start_locked(const char *uri, tp_call_id_t *out_id)
{
    int err;
    struct ua *ua;
    struct call *call = NULL;

    /* Get the default UA (returns a reference) */
    ua = tp_account_get_default_ua();
    if (!ua) {
        warning("tp_call: no user agent available\n");
        return TP_ERR_NOT_FOUND;
    }

    pthread_mutex_lock(&g_mutex);
    bool has_slot = find_free_slot() != NULL;
    pthread_mutex_unlock(&g_mutex);

    if (!has_slot) {
        mem_deref(ua);
        return TP_ERR_NO_MEMORY;
    }

    /* Start the call. The OUTGOING event fires synchronously from
     * ua_connect and registers the call (see tp_call_register). */
    info("tp_call: starting call to %s\n", uri);
    err = ua_connect(ua, &call, NULL, uri, VIDMODE_OFF);

    /* Release UA reference - call holds its own reference */
    mem_deref(ua);

    if (err) {
        warning("tp_call: ua_connect failed: %m\n", err);
        return TP_ERR_CALL_FAILED;
    }

    *out_id = tp_call_register(call);
    if (*out_id == TP_INVALID_ID) {
        warning("tp_call: no slot for new call\n");
        return TP_ERR_NO_MEMORY;
    }

    info("tp_call: started call %u\n", *out_id);

    return TP_OK;
}

tp_error_t tp_call_start(const char *uri, tp_call_id_t *out_id)
{
    tp_error_t result;

    if (!uri || !out_id) {
        return TP_ERR_INVALID_ARG;
    }

    *out_id = TP_INVALID_ID;

    re_thread_enter();
    result = call_start_locked(uri, out_id);
    re_thread_leave();

    return result;
}

static tp_error_t call_answer_locked(tp_call_id_t id)
{
    call_entry_t *entry;
    struct call *call;
    int err;

    if (id == TP_INVALID_ID) {
        return TP_ERR_INVALID_ARG;
    }

    pthread_mutex_lock(&g_mutex);

    entry = find_call(id);
    if (!entry) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_NOT_FOUND;
    }

    call = entry->call;
    pthread_mutex_unlock(&g_mutex);

    info("tp_call: answering call %u\n", id);

    /* Log audio info - warning only if missing */
    struct audio *au = call_audio(call);
    if (!au) {
        warning("tp_call: NO AUDIO OBJECT!\n");
    }

    err = call_answer(call, 200, VIDMODE_OFF);
    if (err) {
        warning("tp_call: call_answer failed: %m\n", err);
        return TP_ERR_CALL_FAILED;
    }

#if TP_VERBOSE_CALL_DEBUG
    /* Verbose debug logging - disabled by default to avoid PII leaks */
    debug("tp_call: call state after answer: %s\n", call_statename(call));
    debug("%H\n", call_debug, call);
#endif

    return TP_OK;
}

tp_error_t tp_call_answer(tp_call_id_t id)
{
    tp_error_t result;

    re_thread_enter();
    result = call_answer_locked(id);
    re_thread_leave();

    return result;
}

static tp_error_t call_hangup_locked(tp_call_id_t id)
{
    call_entry_t *entry;
    struct call *call;

    if (id == TP_INVALID_ID) {
        return TP_ERR_INVALID_ARG;
    }

    pthread_mutex_lock(&g_mutex);

    entry = find_call(id);
    if (!entry) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_NOT_FOUND;
    }

    call = entry->call;

    pthread_mutex_unlock(&g_mutex);

    info("tp_call: hanging up call %u\n", id);

    /* ua_hangup sends BYE/CANCEL/486, emits BEVENT_CALL_CLOSED (which
     * unregisters the call and reports TP_CALL_STATE_ENDED) and frees
     * the call. call_hangup alone would leak the call inside the UA. */
    ua_hangup(call_get_ua(call), call, 0, "Call ended");

    return TP_OK;
}

tp_error_t tp_call_hangup(tp_call_id_t id)
{
    tp_error_t result;

    re_thread_enter();
    result = call_hangup_locked(id);
    re_thread_leave();

    return result;
}

static tp_error_t call_hold_locked(tp_call_id_t id, bool hold)
{
    call_entry_t *entry;
    struct call *call;
    int err;

    if (id == TP_INVALID_ID) {
        return TP_ERR_INVALID_ARG;
    }

    pthread_mutex_lock(&g_mutex);

    entry = find_call(id);
    if (!entry) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_NOT_FOUND;
    }

    call = entry->call;
    pthread_mutex_unlock(&g_mutex);

    info("tp_call: %s call %u\n", hold ? "holding" : "resuming", id);

    if (hold) {
        err = call_hold(call, true);
    } else {
        err = call_hold(call, false);
    }

    if (err) {
        warning("tp_call: hold failed: %m\n", err);
        return TP_ERR_INTERNAL;
    }

    return TP_OK;
}

tp_error_t tp_call_hold(tp_call_id_t id, bool hold)
{
    tp_error_t result;

    re_thread_enter();
    result = call_hold_locked(id, hold);
    re_thread_leave();

    return result;
}

static tp_error_t call_mute_locked(tp_call_id_t id, bool mute)
{
    call_entry_t *entry;
    struct call *call;

    if (id == TP_INVALID_ID) {
        return TP_ERR_INVALID_ARG;
    }

    pthread_mutex_lock(&g_mutex);

    entry = find_call(id);
    if (!entry) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_NOT_FOUND;
    }

    call = entry->call;
    entry->muted = mute;
    pthread_mutex_unlock(&g_mutex);

    info("tp_call: %s call %u\n", mute ? "muting" : "unmuting", id);

    /* Use audio_mute to mute the microphone */
    struct audio *au = call_audio(call);
    if (au) {
        audio_mute(au, mute);
    }

    return TP_OK;
}

tp_error_t tp_call_mute(tp_call_id_t id, bool mute)
{
    tp_error_t result;

    re_thread_enter();
    result = call_mute_locked(id, mute);
    re_thread_leave();

    return result;
}

static tp_error_t call_send_dtmf_locked(tp_call_id_t id, const char *digits)
{
    call_entry_t *entry;
    struct call *call;
    int err;

    if (id == TP_INVALID_ID || !digits) {
        return TP_ERR_INVALID_ARG;
    }

    pthread_mutex_lock(&g_mutex);

    entry = find_call(id);
    if (!entry) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_NOT_FOUND;
    }

    call = entry->call;
    pthread_mutex_unlock(&g_mutex);

    info("tp_call: sending DTMF '%s' on call %u\n", digits, id);

    /* Send each digit */
    for (const char *p = digits; *p; p++) {
        err = call_send_digit(call, *p);
        if (err) {
            warning("tp_call: send_digit '%c' failed: %m\n", *p, err);
            return TP_ERR_INTERNAL;
        }
    }

    return TP_OK;
}

tp_error_t tp_call_send_dtmf(tp_call_id_t id, const char *digits)
{
    tp_error_t result;

    re_thread_enter();
    result = call_send_dtmf_locked(id, digits);
    re_thread_leave();

    return result;
}

/* =============================================================================
 * ID Lookup (for event system)
 * ============================================================================= */

tp_call_id_t tp_call_find_id_by_ptr(const struct call *call)
{
    tp_call_id_t result = TP_INVALID_ID;

    if (!call) {
        return TP_INVALID_ID;
    }

    pthread_mutex_lock(&g_mutex);

    call_entry_t *entry = find_call_by_ptr(call);
    if (entry) {
        result = entry->id;
    }

    pthread_mutex_unlock(&g_mutex);

    return result;
}

tp_call_id_t tp_call_register(struct call *call)
{
    call_entry_t *entry;
    tp_call_id_t id = TP_INVALID_ID;

    if (!call) {
        return TP_INVALID_ID;
    }

    pthread_mutex_lock(&g_mutex);

    /* Check if already registered */
    entry = find_call_by_ptr(call);
    if (entry) {
        id = entry->id;
        pthread_mutex_unlock(&g_mutex);
        return id;
    }

    /* Find free slot */
    entry = find_free_slot();
    if (!entry) {
        pthread_mutex_unlock(&g_mutex);
        return TP_INVALID_ID;
    }

    /* Store call entry */
    entry->id = g_calls.next_id++;
    entry->call = call;
    entry->in_use = true;
    entry->muted = false;

    id = entry->id;

    pthread_mutex_unlock(&g_mutex);

    info("tp_call: registered call %u\n", id);

    return id;
}

void tp_call_unregister(tp_call_id_t id)
{
    if (id == TP_INVALID_ID) {
        return;
    }

    pthread_mutex_lock(&g_mutex);

    call_entry_t *entry = find_call(id);
    if (entry) {
        entry->in_use = false;
        entry->call = NULL;
        entry->muted = false;
    }

    pthread_mutex_unlock(&g_mutex);
}
