/**
 * @file tp_bridge.h
 * @brief TonePhone Bridge API - Stable C interface for Swift interoperability
 *
 * This header defines the public C API that Swift code uses to interact with
 * baresip. All baresip internals are hidden behind this interface.
 *
 * Design principles:
 * - Functions return error codes, not exceptions
 * - Output parameters for created IDs
 * - Opaque handles (IDs) instead of pointers
 * - All strings are UTF-8, null-terminated
 * - Thread-safe for calls from main thread
 */

#ifndef TP_BRIDGE_H
#define TP_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* =============================================================================
 * Error Codes
 * ============================================================================= */

/**
 * @brief Error codes returned by bridge functions
 */
typedef enum {
    TP_OK = 0,                    /**< Success */
    TP_ERR_INVALID_ARG,           /**< Invalid argument */
    TP_ERR_NOT_INITIALIZED,       /**< Bridge not initialized */
    TP_ERR_ALREADY_INITIALIZED,   /**< Bridge already initialized */
    TP_ERR_NOT_STARTED,           /**< Bridge not started */
    TP_ERR_ALREADY_STARTED,       /**< Bridge already started */
    TP_ERR_NOT_FOUND,             /**< Resource not found */
    TP_ERR_ALREADY_EXISTS,        /**< Resource already exists */
    TP_ERR_NO_MEMORY,             /**< Memory allocation failed */
    TP_ERR_NETWORK,               /**< Network error */
    TP_ERR_TIMEOUT,               /**< Operation timed out */
    TP_ERR_REGISTRATION_FAILED,   /**< SIP registration failed */
    TP_ERR_CALL_FAILED,           /**< Call setup failed */
    TP_ERR_MEDIA_FAILED,          /**< Media setup failed */
    TP_ERR_INTERNAL,              /**< Internal error */
} tp_error_t;

/* =============================================================================
 * Opaque ID Types
 * ============================================================================= */

/**
 * @brief Opaque account identifier
 */
typedef uint32_t tp_account_id_t;

/**
 * @brief Opaque call identifier
 */
typedef uint32_t tp_call_id_t;

/**
 * @brief Invalid ID sentinel value
 */
#define TP_INVALID_ID ((uint32_t)0)

/* =============================================================================
 * Configuration Types
 * ============================================================================= */

/**
 * @brief Account configuration for adding a new SIP account
 */
typedef struct {
    const char *display_name;     /**< Display name (optional, may be NULL) */
    const char *sip_uri;          /**< SIP URI (e.g., "sip:user@domain.com") */
    const char *password;         /**< SIP password */
    const char *auth_user;        /**< Auth username (optional, defaults to URI user) */
    const char *outbound_proxy;   /**< Outbound proxy (optional, may be NULL) */
    const char *transport;        /**< Transport: "udp", "tcp", "tls" (optional) */
    const char *stun_server;      /**< STUN server (optional, e.g., "stun:stun.l.google.com:19302") */
    const char *medianat;         /**< NAT traversal method (optional, e.g., "ice", "stun") */
    bool nat_pinhole;             /**< Enable NAT pinhole keep-alive (recommended for NAT) */
    bool register_on_add;         /**< Register immediately after adding */
} tp_account_config_t;

/* =============================================================================
 * Event Types
 * ============================================================================= */

/**
 * @brief Event type identifiers
 */
typedef enum {
    TP_EVENT_CORE_STATE_CHANGED,      /**< Core state changed */
    TP_EVENT_ACCOUNT_STATE_CHANGED,   /**< Account registration state changed */
    TP_EVENT_CALL_STATE_CHANGED,      /**< Call state changed */
    TP_EVENT_CALL_MEDIA_CHANGED,      /**< Call media state changed */
    TP_EVENT_AUDIO_DEVICE_CHANGED,    /**< Audio device changed */
    TP_EVENT_LOG_MESSAGE,             /**< Log message */
} tp_event_type_t;

/**
 * @brief Core state
 */
typedef enum {
    TP_CORE_STATE_IDLE,           /**< Not started */
    TP_CORE_STATE_STARTING,       /**< Starting up */
    TP_CORE_STATE_RUNNING,        /**< Running */
    TP_CORE_STATE_STOPPING,       /**< Shutting down */
} tp_core_state_t;

/**
 * @brief Account registration state
 */
typedef enum {
    TP_ACCOUNT_STATE_UNREGISTERED,    /**< Not registered */
    TP_ACCOUNT_STATE_REGISTERING,     /**< Registration in progress */
    TP_ACCOUNT_STATE_REGISTERED,      /**< Successfully registered */
    TP_ACCOUNT_STATE_FAILED,          /**< Registration failed */
} tp_account_state_t;

/**
 * @brief Call state
 */
typedef enum {
    TP_CALL_STATE_IDLE,           /**< No call */
    TP_CALL_STATE_OUTGOING,       /**< Outgoing call, ringing remote */
    TP_CALL_STATE_INCOMING,       /**< Incoming call, ringing locally */
    TP_CALL_STATE_EARLY,          /**< Early media (ringback) */
    TP_CALL_STATE_ESTABLISHED,    /**< Call connected */
    TP_CALL_STATE_HELD,           /**< Call on hold */
    TP_CALL_STATE_ENDED,          /**< Call ended */
} tp_call_state_t;

/**
 * @brief Log level
 */
typedef enum {
    TP_LOG_ERROR,
    TP_LOG_WARNING,
    TP_LOG_INFO,
    TP_LOG_DEBUG,
    TP_LOG_TRACE,
} tp_log_level_t;

/**
 * @brief Event structure passed to callback
 */
typedef struct {
    tp_event_type_t type;         /**< Event type */
    union {
        struct {
            tp_core_state_t state;
        } core;
        struct {
            tp_account_id_t id;
            tp_account_state_t state;
            const char *reason;   /**< Error reason if failed (may be NULL) */
        } account;
        struct {
            tp_call_id_t id;
            tp_call_state_t state;
            const char *remote_uri;   /**< Remote party URI */
            const char *reason;       /**< Hangup reason if ended (may be NULL) */
        } call;
        struct {
            tp_call_id_t id;
            bool audio_established;
            bool video_established;
            bool encrypted;
        } media;
        struct {
            tp_log_level_t level;
            const char *message;
        } log;
    } data;
} tp_event_t;

/**
 * @brief Event callback function type
 * @param event The event data (valid only for duration of callback)
 * @param ctx User context pointer passed to tp_set_event_callback
 */
typedef void (*tp_event_callback_t)(const tp_event_t *event, void *ctx);

/* =============================================================================
 * Lifecycle Functions
 * ============================================================================= */

/**
 * @brief Initialize the TonePhone bridge
 * @param config_path Path to configuration directory (NULL for default)
 * @param log_path Path to log file (NULL for default)
 * @return TP_OK on success, error code otherwise
 *
 * Must be called before any other bridge functions.
 * Call tp_shutdown() to clean up.
 */
tp_error_t tp_init(const char *config_path, const char *log_path);

/**
 * @brief Start the bridge (begins network operations)
 * @return TP_OK on success, error code otherwise
 *
 * After calling tp_start(), registered accounts will begin registration
 * and the bridge will be ready to make/receive calls.
 */
tp_error_t tp_start(void);

/**
 * @brief Stop the bridge (stops network operations)
 * @return TP_OK on success, error code otherwise
 *
 * Ends all active calls and unregisters all accounts.
 * The bridge remains initialized and can be started again.
 */
tp_error_t tp_stop(void);

/**
 * @brief Shut down the bridge and release all resources
 *
 * After calling tp_shutdown(), tp_init() must be called again
 * before using other bridge functions.
 */
void tp_shutdown(void);

/* =============================================================================
 * Account Functions
 * ============================================================================= */

/**
 * @brief Add a new SIP account
 * @param config Account configuration
 * @param out_id Output: assigned account ID
 * @return TP_OK on success, error code otherwise
 */
tp_error_t tp_account_add(const tp_account_config_t *config,
                          tp_account_id_t *out_id);

/**
 * @brief Remove an account
 * @param id Account ID to remove
 * @return TP_OK on success, error code otherwise
 */
tp_error_t tp_account_remove(tp_account_id_t id);

/**
 * @brief Register an account with the SIP server
 * @param id Account ID
 * @return TP_OK on success, error code otherwise
 *
 * Registration happens asynchronously. Monitor TP_EVENT_ACCOUNT_STATE_CHANGED
 * events to track registration status.
 */
tp_error_t tp_account_register(tp_account_id_t id);

/**
 * @brief Unregister an account from the SIP server
 * @param id Account ID
 * @return TP_OK on success, error code otherwise
 */
tp_error_t tp_account_unregister(tp_account_id_t id);

/**
 * @brief Set the default account for outgoing calls
 * @param id Account ID
 * @return TP_OK on success, error code otherwise
 */
tp_error_t tp_account_set_default(tp_account_id_t id);

/**
 * @brief Get current registration state of an account
 * @param id Account ID
 * @param out_state Output: current account state
 * @return TP_OK on success, error code otherwise
 */
tp_error_t tp_account_get_state(tp_account_id_t id, tp_account_state_t *out_state);

/**
 * @brief Get the default account ID
 * @param out_id Output: default account ID (TP_INVALID_ID if none)
 * @return TP_OK on success, error code otherwise
 */
tp_error_t tp_account_get_default(tp_account_id_t *out_id);

/**
 * @brief Get the number of configured accounts
 * @return Number of active accounts
 */
uint32_t tp_account_count(void);

/**
 * @brief Get account ID by index
 * @param index Zero-based index (0 to tp_account_count()-1)
 * @param out_id Output: account ID at this index
 * @return TP_OK on success, TP_ERR_NOT_FOUND if index out of range
 */
tp_error_t tp_account_get_id_at_index(uint32_t index, tp_account_id_t *out_id);

/* =============================================================================
 * Call Functions
 * ============================================================================= */

/**
 * @brief Start an outgoing call
 * @param uri SIP URI to call (e.g., "sip:user@domain.com")
 * @param out_id Output: assigned call ID
 * @return TP_OK on success, error code otherwise
 *
 * Uses the default account. Call state changes are reported via
 * TP_EVENT_CALL_STATE_CHANGED events.
 */
tp_error_t tp_call_start(const char *uri, tp_call_id_t *out_id);

/**
 * @brief Answer an incoming call
 * @param id Call ID
 * @return TP_OK on success, error code otherwise
 */
tp_error_t tp_call_answer(tp_call_id_t id);

/**
 * @brief Hang up a call
 * @param id Call ID
 * @return TP_OK on success, error code otherwise
 */
tp_error_t tp_call_hangup(tp_call_id_t id);

/**
 * @brief Hold or resume a call
 * @param id Call ID
 * @param hold true to hold, false to resume
 * @return TP_OK on success, error code otherwise
 */
tp_error_t tp_call_hold(tp_call_id_t id, bool hold);

/**
 * @brief Mute or unmute a call
 * @param id Call ID
 * @param mute true to mute, false to unmute
 * @return TP_OK on success, error code otherwise
 */
tp_error_t tp_call_mute(tp_call_id_t id, bool mute);

/**
 * @brief Send DTMF tones
 * @param id Call ID
 * @param digits DTMF digits to send (0-9, *, #, A-D)
 * @return TP_OK on success, error code otherwise
 */
tp_error_t tp_call_send_dtmf(tp_call_id_t id, const char *digits);

/* =============================================================================
 * Event Callback
 * ============================================================================= */

/**
 * @brief Set the event callback
 * @param callback Callback function (NULL to disable)
 * @param ctx User context passed to callback
 *
 * Only one callback can be registered at a time.
 * Events are delivered on a bridge-managed thread; the callback
 * should dispatch to the main thread if needed.
 */
void tp_set_event_callback(tp_event_callback_t callback, void *ctx);

/* =============================================================================
 * Logging Functions
 * ============================================================================= */

/**
 * @brief Initialize file logging
 * @param log_dir Directory where log files will be stored
 * @return TP_OK on success, error code otherwise
 *
 * Log files are automatically rotated when they exceed 5 MB.
 * Up to 3 rotated files are kept (tonephone.log.1, .2, .3).
 */
tp_error_t tp_log_init(const char *log_dir);

/**
 * @brief Close file logging
 *
 * Flushes and closes the log file. Called automatically by tp_shutdown().
 */
void tp_log_close(void);

/**
 * @brief Set the log level
 * @param level Minimum level for messages to be logged
 * @return TP_OK on success
 *
 * Messages below this level are discarded.
 * Default level is TP_LOG_INFO.
 */
tp_error_t tp_log_set_level(tp_log_level_t level);

/**
 * @brief Get the current log level
 * @return Current log level
 */
tp_log_level_t tp_log_get_level(void);

/**
 * @brief Get the current log file path
 * @param buf Buffer to store the path
 * @param size Size of the buffer
 * @return TP_OK on success, error code otherwise
 */
tp_error_t tp_log_get_path(char *buf, size_t size);

/**
 * @brief Flush log buffers to disk
 * @return TP_OK on success
 */
tp_error_t tp_log_flush(void);

/* =============================================================================
 * Audio Device Types
 * ============================================================================= */

/**
 * @brief Audio device type (input or output)
 */
typedef enum {
    TP_AUDIO_DEVICE_INPUT,    /**< Input device (microphone) */
    TP_AUDIO_DEVICE_OUTPUT,   /**< Output device (speaker) */
} tp_audio_device_type_t;

/**
 * @brief Information about an audio device
 */
typedef struct {
    char name[128];           /**< Human-readable device name */
    char uid[128];            /**< Unique device identifier */
    tp_audio_device_type_t type;  /**< Device type */
    bool is_default;          /**< Whether this is the system default */
} tp_audio_device_t;

/**
 * @brief List of audio devices
 */
typedef struct {
    tp_audio_device_t *devices;   /**< Array of devices (caller must free with tp_audio_device_list_free) */
    uint32_t count;               /**< Number of devices in the array */
} tp_audio_device_list_t;

/* =============================================================================
 * Audio Device Functions
 * ============================================================================= */

/**
 * @brief Get list of available input devices (microphones)
 * @param out_list Output: list of input devices
 * @return TP_OK on success, error code otherwise
 *
 * Caller must free the list with tp_audio_device_list_free().
 */
tp_error_t tp_audio_get_input_devices(tp_audio_device_list_t *out_list);

/**
 * @brief Get list of available output devices (speakers)
 * @param out_list Output: list of output devices
 * @return TP_OK on success, error code otherwise
 *
 * Caller must free the list with tp_audio_device_list_free().
 */
tp_error_t tp_audio_get_output_devices(tp_audio_device_list_t *out_list);

/**
 * @brief Free a device list returned by tp_audio_get_*_devices
 * @param list The list to free
 */
void tp_audio_device_list_free(tp_audio_device_list_t *list);

/**
 * @brief Get the current input device name
 * @param buf Buffer to store the device name
 * @param size Size of the buffer
 * @return TP_OK on success, error code otherwise
 *
 * Returns empty string if using system default.
 */
tp_error_t tp_audio_get_current_input(char *buf, size_t size);

/**
 * @brief Get the current output device name
 * @param buf Buffer to store the device name
 * @param size Size of the buffer
 * @return TP_OK on success, error code otherwise
 *
 * Returns empty string if using system default.
 */
tp_error_t tp_audio_get_current_output(char *buf, size_t size);

/**
 * @brief Set the input device (microphone)
 * @param device_name Device name (empty string or NULL for system default)
 * @return TP_OK on success, error code otherwise
 *
 * Takes effect immediately for active calls.
 */
tp_error_t tp_audio_set_input_device(const char *device_name);

/**
 * @brief Set the output device (speaker)
 * @param device_name Device name (empty string or NULL for system default)
 * @return TP_OK on success, error code otherwise
 *
 * Takes effect immediately for active calls.
 */
tp_error_t tp_audio_set_output_device(const char *device_name);

/* =============================================================================
 * Utility Functions
 * ============================================================================= */

/**
 * @brief Get a human-readable description of an error code
 * @param error Error code
 * @return Static string describing the error
 */
const char *tp_error_string(tp_error_t error);

#ifdef __cplusplus
}
#endif

#endif /* TP_BRIDGE_H */
