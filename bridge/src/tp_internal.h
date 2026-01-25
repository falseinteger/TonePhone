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

#endif /* TP_INTERNAL_H */
