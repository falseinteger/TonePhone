/**
 * @file tp_internal.h
 * @brief TonePhone Bridge - Internal shared declarations
 *
 * This header contains declarations shared between bridge implementation
 * files (tp_core.c, tp_events.c, tp_accounts.c, tp_calls.c) but not
 * exposed in the public API (tp_bridge.h).
 */

#ifndef TP_INTERNAL_H
#define TP_INTERNAL_H

#include "tp_bridge.h"
#include <pthread.h>

/* =============================================================================
 * Shared Mutex
 * ============================================================================= */

/**
 * @brief Global mutex for bridge state protection
 * Defined in tp_core.c
 */
extern pthread_mutex_t g_mutex;

/* =============================================================================
 * Event Callback Access
 * ============================================================================= */

/**
 * @brief Get the current event callback and context (thread-safe)
 * @param cb_out Output: callback function pointer
 * @param ctx_out Output: callback context pointer
 *
 * Copies the callback and context under the mutex to avoid races.
 */
void tp_get_event_callback(tp_event_callback_t *cb_out, void **ctx_out);

/* =============================================================================
 * Event System Functions
 * ============================================================================= */

/**
 * @brief Initialize the event callback system
 *
 * Registers the event handler with baresip.
 * Called from tp_init() after baresip is initialized.
 *
 * @return TP_OK on success, error code otherwise
 */
tp_error_t tp_events_init(void);

/**
 * @brief Close the event callback system
 *
 * Unregisters the event handler from baresip.
 * Called from tp_shutdown() before baresip is closed.
 */
void tp_events_close(void);

/* =============================================================================
 * Account ID Mapping (from tp_account.c)
 * ============================================================================= */

/* Forward declaration of baresip types */
struct ua;

/**
 * @brief Look up account ID by UA pointer
 * @param ua The UA pointer from baresip
 * @return The account ID, or TP_INVALID_ID if not found
 */
tp_account_id_t tp_account_find_id_by_ua(const struct ua *ua);

/**
 * @brief Get the default account's UA pointer
 * @return The UA pointer, or NULL if no default account
 *
 * Returns a reference to the UA that must be released with mem_deref().
 */
struct ua *tp_account_get_default_ua(void);

/* =============================================================================
 * Call ID Mapping (from tp_call.c)
 * ============================================================================= */

/* Forward declaration of baresip types */
struct call;

/**
 * @brief Look up call ID by call pointer
 * @param call The call pointer from baresip
 * @return The call ID, or TP_INVALID_ID if not found
 */
tp_call_id_t tp_call_find_id_by_ptr(const struct call *call);

/**
 * @brief Register an incoming call and assign it an ID
 * @param call The incoming call pointer from baresip
 * @return The assigned call ID, or TP_INVALID_ID if no slot available
 */
tp_call_id_t tp_call_register_incoming(struct call *call);

/**
 * @brief Unregister a call (called when call ends)
 * @param id The call ID to unregister
 */
void tp_call_unregister(tp_call_id_t id);

#endif /* TP_INTERNAL_H */
