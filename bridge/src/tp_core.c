/**
 * @file tp_core.c
 * @brief TonePhone Bridge - Core lifecycle implementation
 *
 * Implements the lifecycle functions that wrap baresip initialization,
 * main loop management, and shutdown.
 */

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
    STATE_INITIALIZED,
    STATE_STARTING,
    STATE_RUNNING,
    STATE_STOPPING,
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

/* Initialize mutex statically */
static pthread_mutex_t g_mutex = PTHREAD_MUTEX_INITIALIZER;

/* =============================================================================
 * Internal Helpers
 * ============================================================================= */

/**
 * @brief Post a core state change event
 */
static void post_core_state_event(tp_core_state_t state)
{
    if (g_bridge.event_cb) {
        tp_event_t event = {
            .type = TP_EVENT_CORE_STATE_CHANGED,
            .data.core.state = state,
        };
        g_bridge.event_cb(&event, g_bridge.event_ctx);
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

    pthread_mutex_unlock(&g_mutex);

    /* Initialize libre */
    err = libre_init();
    if (err) {
        warning("tp_core: libre_init failed: %m\n", err);
        return TP_ERR_INTERNAL;
    }

    /* Set configuration path if provided */
    if (config_path && config_path[0] != '\0') {
        err = conf_path_set(config_path);
        if (err) {
            warning("tp_core: conf_path_set failed: %m\n", err);
            libre_close();
            return TP_ERR_INVALID_ARG;
        }
    }

    /* Configure from config files */
    err = conf_configure();
    if (err) {
        warning("tp_core: conf_configure failed: %m\n", err);
        libre_close();
        return TP_ERR_INTERNAL;
    }

    /* Initialize async worker threads */
    err = re_thread_async_init(TP_ASYNC_WORKERS);
    if (err) {
        warning("tp_core: re_thread_async_init failed: %m\n", err);
        conf_close();
        libre_close();
        return TP_ERR_INTERNAL;
    }

    /* Initialize baresip core */
    err = baresip_init(conf_config());
    if (err) {
        warning("tp_core: baresip_init failed: %m\n", err);
        re_thread_async_close();
        conf_close();
        libre_close();
        return TP_ERR_INTERNAL;
    }

    /* Initialize User Agent system */
    err = ua_init(TP_SOFTWARE_NAME, true, true, true);
    if (err) {
        warning("tp_core: ua_init failed: %m\n", err);
        baresip_close();
        re_thread_async_close();
        conf_close();
        libre_close();
        return TP_ERR_INTERNAL;
    }

    /* Set exit handler */
    uag_set_exit_handler(ua_exit_handler, NULL);

    /* Load configured modules */
    err = conf_modules();
    if (err) {
        warning("tp_core: conf_modules failed: %m\n", err);
        ua_close();
        baresip_close();
        re_thread_async_close();
        conf_close();
        libre_close();
        return TP_ERR_INTERNAL;
    }

    /* Handle log_path - baresip logging is handled via config */
    (void)log_path;

    pthread_mutex_lock(&g_mutex);
    g_bridge.state = STATE_INITIALIZED;
    g_bridge.thread_started = false;
    pthread_mutex_unlock(&g_mutex);

    info("tp_core: initialized\n");

    return TP_OK;
}

tp_error_t tp_start(void)
{
    int err;

    pthread_mutex_lock(&g_mutex);

    if (g_bridge.state == STATE_UNINITIALIZED) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_NOT_INITIALIZED;
    }

    if (g_bridge.state == STATE_RUNNING || g_bridge.state == STATE_STARTING) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_ALREADY_STARTED;
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

    info("tp_core: started\n");

    return TP_OK;
}

tp_error_t tp_stop(void)
{
    pthread_mutex_lock(&g_mutex);

    if (g_bridge.state == STATE_UNINITIALIZED) {
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

    info("tp_core: stopped\n");

    return TP_OK;
}

void tp_shutdown(void)
{
    pthread_mutex_lock(&g_mutex);
    bridge_state_t current_state = g_bridge.state;
    pthread_mutex_unlock(&g_mutex);

    if (current_state == STATE_UNINITIALIZED) {
        return;
    }

    /* If running, stop first */
    if (current_state == STATE_RUNNING || current_state == STATE_STARTING) {
        tp_stop();
    }

    info("tp_core: shutting down...\n");

    /* Shutdown in reverse order of initialization */
    ua_close();
    module_app_unload();
    conf_close();
    baresip_close();
    mod_close();
    re_thread_async_close();
    libre_close();

    pthread_mutex_lock(&g_mutex);
    g_bridge.state = STATE_UNINITIALIZED;
    g_bridge.thread_started = false;
    g_bridge.event_cb = NULL;
    g_bridge.event_ctx = NULL;
    pthread_mutex_unlock(&g_mutex);

    info("tp_core: shutdown complete\n");
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
