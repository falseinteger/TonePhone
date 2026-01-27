/**
 * @file tp_events.c
 * @brief TonePhone Bridge - Event callback system implementation
 *
 * Implements the event forwarding layer that captures baresip events
 * and forwards them to the registered callback function.
 */

#include "tp_internal.h"
#include "tp_bridge.h"

#include <re.h>
#include <baresip.h>

#include <pthread.h>

/* =============================================================================
 * Internal State
 * ============================================================================= */

static bool g_events_registered = false;

/* =============================================================================
 * ID Mapping
 * ============================================================================= */

/**
 * @brief Get call ID for a call
 *
 * Looks up the call in our tracking system.
 * For incoming calls not yet registered, returns TP_INVALID_ID.
 */
static tp_call_id_t get_call_id_for_call(const struct call *call)
{
    if (!call)
        return TP_INVALID_ID;

    return tp_call_find_id_by_ptr(call);
}

/* =============================================================================
 * Event Mapping
 * ============================================================================= */

/**
 * @brief Map baresip registration events to account state
 */
static bool map_account_event(enum bevent_ev ev, tp_account_state_t *state)
{
    switch (ev) {
    case BEVENT_REGISTERING:
        *state = TP_ACCOUNT_STATE_REGISTERING;
        return true;

    case BEVENT_REGISTER_OK:
    case BEVENT_FALLBACK_OK:
        *state = TP_ACCOUNT_STATE_REGISTERED;
        return true;

    case BEVENT_REGISTER_FAIL:
    case BEVENT_FALLBACK_FAIL:
        *state = TP_ACCOUNT_STATE_FAILED;
        return true;

    case BEVENT_UNREGISTERING:
        *state = TP_ACCOUNT_STATE_UNREGISTERED;
        return true;

    default:
        return false;
    }
}

/**
 * @brief Map baresip call events to call state
 */
static bool map_call_event(enum bevent_ev ev, tp_call_state_t *state)
{
    switch (ev) {
    case BEVENT_CALL_INCOMING:
        *state = TP_CALL_STATE_INCOMING;
        return true;

    case BEVENT_CALL_OUTGOING:
        *state = TP_CALL_STATE_OUTGOING;
        return true;

    case BEVENT_CALL_RINGING:
    case BEVENT_CALL_PROGRESS:
        *state = TP_CALL_STATE_EARLY;
        return true;

    case BEVENT_CALL_ANSWERED:
    case BEVENT_CALL_ESTABLISHED:
        *state = TP_CALL_STATE_ESTABLISHED;
        return true;

    case BEVENT_CALL_HOLD:
        *state = TP_CALL_STATE_HELD;
        return true;

    case BEVENT_CALL_RESUME:
        *state = TP_CALL_STATE_ESTABLISHED;
        return true;

    case BEVENT_CALL_CLOSED:
        *state = TP_CALL_STATE_ENDED;
        return true;

    default:
        return false;
    }
}

/* =============================================================================
 * Event Handler
 * ============================================================================= */

/**
 * @brief Handle account-related events
 */
static void handle_account_event(enum bevent_ev ev, struct bevent *event)
{
    tp_event_callback_t cb;
    void *ctx;
    tp_account_state_t state;

    if (!map_account_event(ev, &state))
        return;

    struct ua *ua = bevent_get_ua(event);
    if (!ua)
        return;

    /* Look up our account ID from the UA pointer */
    tp_account_id_t account_id = tp_account_find_id_by_ua(ua);
    if (account_id == TP_INVALID_ID) {
        warning("tp_events: unknown UA in account event\n");
        return;
    }

    /* Get callback (thread-safe) */
    tp_get_event_callback(&cb, &ctx);
    if (!cb)
        return;

    const char *text = bevent_get_text(event);

    tp_event_t tp_event = {
        .type = TP_EVENT_ACCOUNT_STATE_CHANGED,
        .data.account = {
            .id = account_id,
            .state = state,
            .reason = text,
        },
    };

    info("tp_events: account %u state changed to %d\n", account_id, state);

    cb(&tp_event, ctx);
}

/**
 * @brief Handle call-related events
 */
static void handle_call_event(enum bevent_ev ev, struct bevent *event)
{
    tp_event_callback_t cb;
    void *ctx;
    tp_call_state_t state;
    tp_call_id_t call_id;

    if (!map_call_event(ev, &state))
        return;

    struct call *call = bevent_get_call(event);
    if (!call)
        return;

    /* For incoming calls, register them first */
    if (ev == BEVENT_CALL_INCOMING) {
        call_id = tp_call_register_incoming(call);
        if (call_id == TP_INVALID_ID) {
            warning("tp_events: failed to register incoming call\n");
            return;
        }
        info("tp_events: registered incoming call %u\n", call_id);
    } else {
        call_id = get_call_id_for_call(call);
        if (call_id == TP_INVALID_ID) {
            /* Call not tracked - this can happen for calls we didn't initiate */
            warning("tp_events: unknown call in event %d\n", ev);
            return;
        }
    }

    /* Unregister call when it ends */
    if (state == TP_CALL_STATE_ENDED) {
        tp_call_unregister(call_id);
    }

    /* Get callback (thread-safe) */
    tp_get_event_callback(&cb, &ctx);
    if (!cb)
        return;

    const char *peer_uri = call_peeruri(call);
    const char *text = bevent_get_text(event);

    tp_event_t tp_event = {
        .type = TP_EVENT_CALL_STATE_CHANGED,
        .data.call = {
            .id = call_id,
            .state = state,
            .remote_uri = peer_uri,
            .reason = (state == TP_CALL_STATE_ENDED) ? text : NULL,
        },
    };

    info("tp_events: call %u state changed to %d\n", call_id, state);

    cb(&tp_event, ctx);
}

/**
 * @brief Handle media-related events
 */
static void handle_media_event(enum bevent_ev ev, struct bevent *event)
{
    tp_event_callback_t cb;
    void *ctx;

    /* Only handle RTP establishment for now */
    if (ev != BEVENT_CALL_RTPESTAB && ev != BEVENT_CALL_MENC)
        return;

    struct call *call = bevent_get_call(event);
    if (!call)
        return;

    /* Get callback (thread-safe) */
    tp_get_event_callback(&cb, &ctx);
    if (!cb)
        return;

    tp_event_t tp_event = {
        .type = TP_EVENT_CALL_MEDIA_CHANGED,
        .data.media = {
            .id = get_call_id_for_call(call),
            .audio_established = (ev == BEVENT_CALL_RTPESTAB),
            .video_established = false,  /* TODO: check video state */
            .encrypted = (ev == BEVENT_CALL_MENC),
        },
    };

    cb(&tp_event, ctx);
}

/**
 * @brief Main baresip event handler
 *
 * This function is registered with baresip and receives all events.
 * Events are filtered and mapped to tp_event_t before forwarding.
 */
static void baresip_event_handler(enum bevent_ev ev, struct bevent *event,
                                  void *arg)
{
    (void)arg;

    info("tp_events: received baresip event %d\n", ev);

    /* Route events to appropriate handlers based on type */
    switch (ev) {
    /* Account/Registration events */
    case BEVENT_REGISTERING:
    case BEVENT_REGISTER_OK:
    case BEVENT_REGISTER_FAIL:
    case BEVENT_UNREGISTERING:
    case BEVENT_FALLBACK_OK:
    case BEVENT_FALLBACK_FAIL:
        handle_account_event(ev, event);
        break;

    /* Call state events */
    case BEVENT_CALL_INCOMING:
        info("tp_events: *** INCOMING CALL EVENT ***\n");
        handle_call_event(ev, event);
        break;
    case BEVENT_CALL_OUTGOING:
    case BEVENT_CALL_RINGING:
    case BEVENT_CALL_PROGRESS:
    case BEVENT_CALL_ANSWERED:
    case BEVENT_CALL_ESTABLISHED:
    case BEVENT_CALL_CLOSED:
    case BEVENT_CALL_HOLD:
    case BEVENT_CALL_RESUME:
        handle_call_event(ev, event);
        break;

    /* Media events */
    case BEVENT_CALL_RTPESTAB:
    case BEVENT_CALL_MENC:
        handle_media_event(ev, event);
        break;

    /* Core events - handled by tp_core.c */
    case BEVENT_SHUTDOWN:
    case BEVENT_EXIT:
        /* These are handled in tp_core.c lifecycle management */
        break;

    /* Events we don't forward (yet) */
    case BEVENT_CREATE:
    case BEVENT_MWI_NOTIFY:
    case BEVENT_CALL_TRANSFER:
    case BEVENT_CALL_REDIRECT:
    case BEVENT_CALL_TRANSFER_FAILED:
    case BEVENT_CALL_DTMF_START:
    case BEVENT_CALL_DTMF_END:
    case BEVENT_CALL_RTCP:
    case BEVENT_VU_TX:
    case BEVENT_VU_RX:
    case BEVENT_AUDIO_ERROR:
    case BEVENT_CALL_LOCAL_SDP:
    case BEVENT_CALL_REMOTE_SDP:
    case BEVENT_REFER:
    case BEVENT_MODULE:
    case BEVENT_END_OF_FILE:
    case BEVENT_CUSTOM:
    case BEVENT_SIPSESS_CONN:
    case BEVENT_MAX:
        /* Ignore these events for now */
        break;
    }
}

/* =============================================================================
 * Public Functions
 * ============================================================================= */

/**
 * @brief Register the event handler with baresip
 *
 * Called from tp_init() after baresip is initialized.
 *
 * @return TP_OK on success, error code otherwise
 */
tp_error_t tp_events_init(void)
{
    int err;

    if (g_events_registered) {
        return TP_OK;
    }

    err = bevent_register(baresip_event_handler, NULL);
    if (err) {
        warning("tp_events: bevent_register failed: %m\n", err);
        return TP_ERR_INTERNAL;
    }

    g_events_registered = true;
    info("tp_events: registered event handler\n");

    return TP_OK;
}

/**
 * @brief Unregister the event handler from baresip
 *
 * Called from tp_shutdown() before baresip is closed.
 */
void tp_events_close(void)
{
    if (!g_events_registered) {
        return;
    }

    bevent_unregister(baresip_event_handler);
    g_events_registered = false;

    info("tp_events: unregistered event handler\n");
}
