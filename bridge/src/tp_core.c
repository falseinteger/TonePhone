/**
 * @file tp_core.c
 * @brief TonePhone Bridge - Core lifecycle implementation
 *
 * Implements the lifecycle functions that wrap baresip initialization,
 * main loop management, and shutdown.
 */

#include "tp_internal.h"
#include "tp_bridge.h"

#include <re.h>
#include <baresip.h>

#include <pthread.h>
#include <string.h>

/* =============================================================================
 * Constants
 * ============================================================================= */

#define TP_ASYNC_WORKERS 4
#define TP_SOFTWARE_NAME "TonePhone/1.0"

/* =============================================================================
 * Module State
 * ============================================================================= */

/**
 * @brief Bridge state machine
 */
typedef enum {
    STATE_UNINITIALIZED = 0,
    STATE_INITIALIZING,
    STATE_INITIALIZED,
    STATE_STARTING,
    STATE_RUNNING,
    STATE_STOPPING,
    STATE_SHUTTING_DOWN,
} bridge_state_t;

/**
 * @brief Global bridge state
 */
static struct {
    bridge_state_t state;
    pthread_t main_thread;
    pthread_mutex_t mutex;
    bool thread_started;

    /* Event callback */
    tp_event_callback_t event_cb;
    void *event_ctx;
} g_bridge = {
    .state = STATE_UNINITIALIZED,
    .thread_started = false,
    .event_cb = NULL,
    .event_ctx = NULL,
};

/* Initialize mutex statically - shared across bridge modules via tp_internal.h */
pthread_mutex_t g_mutex = PTHREAD_MUTEX_INITIALIZER;

/* =============================================================================
 * Internal Helpers
 * ============================================================================= */

/**
 * @brief Post a core state change event
 */
static void post_core_state_event(tp_core_state_t state)
{
    tp_event_callback_t cb;
    void *ctx;

    /* Copy callback under lock to avoid race with tp_set_event_callback */
    pthread_mutex_lock(&g_mutex);
    cb = g_bridge.event_cb;
    ctx = g_bridge.event_ctx;
    pthread_mutex_unlock(&g_mutex);

    if (cb) {
        tp_event_t event = {
            .type = TP_EVENT_CORE_STATE_CHANGED,
            .data.core.state = state,
        };
        cb(&event, ctx);
    }
}

/**
 * @brief Signal handler for the main loop
 */
static void signal_handler(int sig)
{
    (void)sig;
    /* Signal received, stop the main loop */
    re_cancel();
}

/**
 * @brief UA exit handler - called when all UAs are closed
 */
static void ua_exit_handler(void *arg)
{
    (void)arg;
    /* All UAs closed, stop the main loop */
    re_cancel();
}

/* Enable verbose SIP tracing (set to 1 for detailed SIP message dumps) */
#ifndef TP_ENABLE_SIP_TRACE
#define TP_ENABLE_SIP_TRACE 0
#endif

#if TP_ENABLE_SIP_TRACE
/**
 * @brief SIP trace handler - logs all SIP messages for debugging
 *
 * Note: Only enabled when TP_ENABLE_SIP_TRACE is defined.
 * SIP messages may contain sensitive information.
 */
static void sip_trace_handler(bool tx, enum sip_transp tp,
                              const struct sa *src, const struct sa *dst,
                              const uint8_t *pkt, size_t len, void *arg)
{
    (void)arg;
    (void)pkt;

    /* Log direction and transport - basic info only */
    debug("tp_core: SIP %s via %s %J -> %J (len=%zu)\n",
         tx ? ">>>" : "<<<",
         tp == SIP_TRANSP_UDP ? "UDP" :
         tp == SIP_TRANSP_TCP ? "TCP" :
         tp == SIP_TRANSP_TLS ? "TLS" : "???",
         src, dst, len);
}
#endif

/**
 * @brief Main loop thread entry point
 */
static void *main_loop_thread(void *arg)
{
    (void)arg;
    int err;

    /* Run the libre main loop */
    err = re_main(signal_handler);
    if (err) {
        warning("tp_core: re_main failed: %m\n", err);
    }

    pthread_mutex_lock(&g_mutex);
    g_bridge.state = STATE_INITIALIZED;
    pthread_mutex_unlock(&g_mutex);

    post_core_state_event(TP_CORE_STATE_IDLE);

    return NULL;
}

/* =============================================================================
 * Lifecycle Functions
 * ============================================================================= */

tp_error_t tp_init(const char *config_path, const char *log_path)
{
    int err;

    pthread_mutex_lock(&g_mutex);

    if (g_bridge.state != STATE_UNINITIALIZED) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_ALREADY_INITIALIZED;
    }

    /* Mark as initializing to block concurrent tp_init calls */
    g_bridge.state = STATE_INITIALIZING;
    pthread_mutex_unlock(&g_mutex);

    /* Initialize libre */
    err = libre_init();
    if (err) {
        warning("tp_core: libre_init failed: %m\n", err);
        pthread_mutex_lock(&g_mutex);
        g_bridge.state = STATE_UNINITIALIZED;
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_INTERNAL;
    }

    /* Set configuration path if provided */
    if (config_path && config_path[0] != '\0') {
        err = conf_path_set(config_path);
        if (err) {
            warning("tp_core: conf_path_set failed: %m\n", err);
            libre_close();
            pthread_mutex_lock(&g_mutex);
            g_bridge.state = STATE_UNINITIALIZED;
            pthread_mutex_unlock(&g_mutex);
            return TP_ERR_INVALID_ARG;
        }
    }

    /* Configure from config files */
    info("tp_core: calling conf_configure with path: %s\n",
         config_path ? config_path : "(default)");
    err = conf_configure();
    if (err) {
        warning("tp_core: conf_configure failed: %m\n", err);
        libre_close();
        pthread_mutex_lock(&g_mutex);
        g_bridge.state = STATE_UNINITIALIZED;
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_INTERNAL;
    }
    info("tp_core: conf_configure succeeded, conf_cur=%p, conf_config=%p\n",
         conf_cur(), conf_config());

    /* Initialize async worker threads */
    err = re_thread_async_init(TP_ASYNC_WORKERS);
    if (err) {
        warning("tp_core: re_thread_async_init failed: %m\n", err);
        conf_close();
        libre_close();
        pthread_mutex_lock(&g_mutex);
        g_bridge.state = STATE_UNINITIALIZED;
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_INTERNAL;
    }

    /* Initialize baresip core */
    err = baresip_init(conf_config());
    if (err) {
        warning("tp_core: baresip_init failed: %m\n", err);
        re_thread_async_close();
        conf_close();
        libre_close();
        pthread_mutex_lock(&g_mutex);
        g_bridge.state = STATE_UNINITIALIZED;
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_INTERNAL;
    }

    /* Enable debug-level logging for SIP troubleshooting */
    log_level_set(LEVEL_DEBUG);

    /* Initialize User Agent system */
    err = ua_init(TP_SOFTWARE_NAME, true, true, true);
    if (err) {
        warning("tp_core: ua_init failed: %m\n", err);
        baresip_close();
        re_thread_async_close();
        conf_close();
        libre_close();
        pthread_mutex_lock(&g_mutex);
        g_bridge.state = STATE_UNINITIALIZED;
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_INTERNAL;
    }

    /* Set exit handler */
    uag_set_exit_handler(ua_exit_handler, NULL);

#if TP_ENABLE_SIP_TRACE
    /* Enable SIP tracing for debugging (disabled by default) */
    sip_set_trace_handler(uag_sip(), sip_trace_handler);
#endif

    /* Load configured modules */
    err = conf_modules();
    if (err) {
        warning("tp_core: conf_modules failed: %m\n", err);
        ua_close();
        baresip_close();
        re_thread_async_close();
        conf_close();
        libre_close();
        pthread_mutex_lock(&g_mutex);
        g_bridge.state = STATE_UNINITIALIZED;
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_INTERNAL;
    }

    /* Initialize file logging if path provided */
    if (log_path && log_path[0] != '\0') {
        tp_error_t log_err = tp_log_init(log_path);
        if (log_err != TP_OK) {
            warning("tp_core: tp_log_init failed: %s\n", tp_error_string(log_err));
            /* Continue without file logging - not fatal */
        }
    }

    /* Initialize event callback system */
    tp_error_t tp_err = tp_events_init();
    if (tp_err != TP_OK) {
        warning("tp_core: tp_events_init failed: %s (%d)\n",
                tp_error_string(tp_err), tp_err);
        module_app_unload();
        ua_close();
        baresip_close();
        re_thread_async_close();
        conf_close();
        libre_close();
        pthread_mutex_lock(&g_mutex);
        g_bridge.state = STATE_UNINITIALIZED;
        pthread_mutex_unlock(&g_mutex);
        return tp_err;
    }

    pthread_mutex_lock(&g_mutex);
    g_bridge.state = STATE_INITIALIZED;
    g_bridge.thread_started = false;
    pthread_mutex_unlock(&g_mutex);

    /* Log initialization summary for verification */
    info("tp_core: ===== Initialization Summary =====\n");
    info("tp_core: libre version: %s\n", sys_libre_version_get());
    info("tp_core: baresip version: %s\n", baresip_version());

    /* Log audio codec info */
    const struct list *codecs = baresip_aucodecl();
    if (codecs) {
        info("tp_core: audio codecs: %u loaded\n", list_count(codecs));
    }

    info("tp_core: config path: %s\n", config_path ? config_path : "(default)");
    info("tp_core: =====================================\n");
    info("tp_core: initialized successfully\n");

    return TP_OK;
}

tp_error_t tp_start(void)
{
    int err;

    pthread_mutex_lock(&g_mutex);

    if (g_bridge.state == STATE_UNINITIALIZED ||
        g_bridge.state == STATE_INITIALIZING) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_NOT_INITIALIZED;
    }

    if (g_bridge.state == STATE_RUNNING || g_bridge.state == STATE_STARTING) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_ALREADY_STARTED;
    }

    if (g_bridge.state == STATE_SHUTTING_DOWN) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_NOT_INITIALIZED;
    }

    g_bridge.state = STATE_STARTING;
    pthread_mutex_unlock(&g_mutex);

    post_core_state_event(TP_CORE_STATE_STARTING);

    /* Start main loop on background thread */
    err = pthread_create(&g_bridge.main_thread, NULL, main_loop_thread, NULL);
    if (err != 0) {
        warning("tp_core: pthread_create failed: %d\n", err);
        pthread_mutex_lock(&g_mutex);
        g_bridge.state = STATE_INITIALIZED;
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_INTERNAL;
    }

    pthread_mutex_lock(&g_mutex);
    g_bridge.state = STATE_RUNNING;
    g_bridge.thread_started = true;
    pthread_mutex_unlock(&g_mutex);

    post_core_state_event(TP_CORE_STATE_RUNNING);

    info("tp_core: main loop started on background thread\n");

    return TP_OK;
}

tp_error_t tp_stop(void)
{
    pthread_mutex_lock(&g_mutex);

    if (g_bridge.state == STATE_UNINITIALIZED ||
        g_bridge.state == STATE_INITIALIZING ||
        g_bridge.state == STATE_SHUTTING_DOWN) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_NOT_INITIALIZED;
    }

    if (g_bridge.state != STATE_RUNNING) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_NOT_STARTED;
    }

    g_bridge.state = STATE_STOPPING;
    bool thread_was_started = g_bridge.thread_started;
    pthread_mutex_unlock(&g_mutex);

    post_core_state_event(TP_CORE_STATE_STOPPING);

    info("tp_core: stopping...\n");

    /* Stop all user agents (this will trigger ua_exit_handler) */
    ua_stop_all(false);

    /* Signal the main loop to stop */
    re_cancel();

    /* Wait for thread to finish */
    if (thread_was_started) {
        pthread_join(g_bridge.main_thread, NULL);
    }

    pthread_mutex_lock(&g_mutex);
    g_bridge.state = STATE_INITIALIZED;
    g_bridge.thread_started = false;
    pthread_mutex_unlock(&g_mutex);

    post_core_state_event(TP_CORE_STATE_IDLE);

    info("tp_core: main loop stopped\n");

    return TP_OK;
}

void tp_shutdown(void)
{
    pthread_mutex_lock(&g_mutex);

    /* Already uninitialized or shutting down - nothing to do */
    if (g_bridge.state == STATE_UNINITIALIZED ||
        g_bridge.state == STATE_SHUTTING_DOWN) {
        pthread_mutex_unlock(&g_mutex);
        return;
    }

    bridge_state_t current_state = g_bridge.state;
    /* Mark as shutting down to block concurrent shutdown calls */
    g_bridge.state = STATE_SHUTTING_DOWN;
    pthread_mutex_unlock(&g_mutex);

    /* If running, stop first */
    if (current_state == STATE_RUNNING || current_state == STATE_STARTING) {
        tp_stop();
    }

    info("tp_core: ===== Shutdown Sequence =====\n");

    /* Unregister event handler first (reverse order of init) */
    info("tp_core: closing event handler...\n");
    tp_events_close();

    /* Shutdown in reverse order of initialization */
    info("tp_core: closing user agents...\n");
    ua_close();

    info("tp_core: unloading app modules...\n");
    module_app_unload();

    info("tp_core: closing configuration...\n");
    conf_close();

    info("tp_core: closing baresip core...\n");
    baresip_close();

    info("tp_core: closing modules...\n");
    mod_close();

    info("tp_core: closing async workers...\n");
    re_thread_async_close();

    info("tp_core: closing libre...\n");
    libre_close();

    pthread_mutex_lock(&g_mutex);
    g_bridge.state = STATE_UNINITIALIZED;
    g_bridge.thread_started = false;
    g_bridge.event_cb = NULL;
    g_bridge.event_ctx = NULL;
    pthread_mutex_unlock(&g_mutex);

    info("tp_core: =============================\n");
    info("tp_core: shutdown complete\n");

    /* Close file logging last (after final log messages) */
    tp_log_close();
}

/* =============================================================================
 * Event Callback
 * ============================================================================= */

void tp_set_event_callback(tp_event_callback_t callback, void *ctx)
{
    pthread_mutex_lock(&g_mutex);
    g_bridge.event_cb = callback;
    g_bridge.event_ctx = ctx;
    pthread_mutex_unlock(&g_mutex);
}

void tp_get_event_callback(tp_event_callback_t *cb_out, void **ctx_out)
{
    pthread_mutex_lock(&g_mutex);
    if (cb_out)
        *cb_out = g_bridge.event_cb;
    if (ctx_out)
        *ctx_out = g_bridge.event_ctx;
    pthread_mutex_unlock(&g_mutex);
}

/* =============================================================================
 * Utility Functions
 * ============================================================================= */

const char *tp_error_string(tp_error_t error)
{
    switch (error) {
    case TP_OK:                     return "Success";
    case TP_ERR_INVALID_ARG:        return "Invalid argument";
    case TP_ERR_NOT_INITIALIZED:    return "Bridge not initialized";
    case TP_ERR_ALREADY_INITIALIZED: return "Bridge already initialized";
    case TP_ERR_NOT_STARTED:        return "Bridge not started";
    case TP_ERR_ALREADY_STARTED:    return "Bridge already started";
    case TP_ERR_NOT_FOUND:          return "Resource not found";
    case TP_ERR_ALREADY_EXISTS:     return "Resource already exists";
    case TP_ERR_NO_MEMORY:          return "Memory allocation failed";
    case TP_ERR_NETWORK:            return "Network error";
    case TP_ERR_TIMEOUT:            return "Operation timed out";
    case TP_ERR_REGISTRATION_FAILED: return "SIP registration failed";
    case TP_ERR_CALL_FAILED:        return "Call setup failed";
    case TP_ERR_MEDIA_FAILED:       return "Media setup failed";
    case TP_ERR_INTERNAL:           return "Internal error";
    default:                        return "Unknown error";
    }
}
