/**
 * @file tp_log.c
 * @brief TonePhone Bridge - File logging implementation
 *
 * Implements file-based logging with rotation and level control.
 * Integrates with baresip's logging system.
 */

#include "tp_internal.h"
#include "tp_bridge.h"

#include <re.h>
#include <baresip.h>

#include <stdio.h>
#include <string.h>
#include <time.h>
#include <sys/stat.h>
#include <pthread.h>

/* =============================================================================
 * Constants
 * ============================================================================= */

#define LOG_MAX_SIZE        (5 * 1024 * 1024)  /* 5 MB max log file size */
#define LOG_MAX_FILES       3                   /* Keep 3 rotated files */
#define LOG_FILENAME        "tonephone.log"
#define LOG_BUFFER_SIZE     8192

/* =============================================================================
 * Module State
 * ============================================================================= */

static struct {
    FILE *file;
    char path[512];
    char dir[512];
    size_t current_size;
    tp_log_level_t level;
    bool initialized;
    pthread_mutex_t mutex;
    struct log baresip_log;  /* baresip log handler */
} g_log = {
    .file = NULL,
    .current_size = 0,
    .level = TP_LOG_INFO,
    .initialized = false,
    .mutex = PTHREAD_MUTEX_INITIALIZER,
};

/* =============================================================================
 * Internal Helpers
 * ============================================================================= */

/**
 * @brief Convert tp_log_level_t to baresip log level
 */
static enum log_level tp_to_baresip_level(tp_log_level_t level)
{
    switch (level) {
    case TP_LOG_ERROR:   return LEVEL_ERROR;
    case TP_LOG_WARNING: return LEVEL_WARN;
    case TP_LOG_INFO:    return LEVEL_INFO;
    case TP_LOG_DEBUG:
    case TP_LOG_TRACE:   return LEVEL_DEBUG;
    default:             return LEVEL_INFO;
    }
}

/**
 * @brief Convert baresip log level to tp_log_level_t
 */
static tp_log_level_t baresip_to_tp_level(uint32_t level)
{
    switch (level) {
    case LEVEL_ERROR: return TP_LOG_ERROR;
    case LEVEL_WARN:  return TP_LOG_WARNING;
    case LEVEL_INFO:  return TP_LOG_INFO;
    case LEVEL_DEBUG: return TP_LOG_DEBUG;
    default:          return TP_LOG_INFO;
    }
}

/**
 * @brief Get log level name string
 */
static const char *level_name(tp_log_level_t level)
{
    switch (level) {
    case TP_LOG_ERROR:   return "ERROR";
    case TP_LOG_WARNING: return "WARN ";
    case TP_LOG_INFO:    return "INFO ";
    case TP_LOG_DEBUG:   return "DEBUG";
    case TP_LOG_TRACE:   return "TRACE";
    default:             return "?????";
    }
}

/**
 * @brief Get current file size
 */
static size_t get_file_size(const char *path)
{
    struct stat st;
    if (stat(path, &st) == 0) {
        return (size_t)st.st_size;
    }
    return 0;
}

/**
 * @brief Rotate log files
 *
 * Renames tonephone.log -> tonephone.log.1 -> tonephone.log.2 -> ...
 * Deletes oldest if exceeds LOG_MAX_FILES.
 */
static void rotate_logs(void)
{
    char old_path[600];
    char new_path[600];

    /* Close current file */
    if (g_log.file) {
        fclose(g_log.file);
        g_log.file = NULL;
    }

    /* Delete oldest log if it exists */
    re_snprintf(old_path, sizeof(old_path), "%s.%d", g_log.path, LOG_MAX_FILES);
    (void)remove(old_path);

    /* Rotate existing logs */
    for (int i = LOG_MAX_FILES - 1; i >= 1; i--) {
        re_snprintf(old_path, sizeof(old_path), "%s.%d", g_log.path, i);
        re_snprintf(new_path, sizeof(new_path), "%s.%d", g_log.path, i + 1);
        (void)rename(old_path, new_path);
    }

    /* Rename current log to .1 */
    re_snprintf(new_path, sizeof(new_path), "%s.1", g_log.path);
    (void)rename(g_log.path, new_path);

    /* Open new log file */
    g_log.file = fopen(g_log.path, "a");
    g_log.current_size = 0;
}

/**
 * @brief Write a message to the log file
 */
static void write_log(tp_log_level_t level, const char *msg)
{
    if (!g_log.file || level < g_log.level)
        return;

    /* Get timestamp */
    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    char timestamp[32];
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", tm_info);

    /* Write to file */
    int written = fprintf(g_log.file, "%s [%s] %s",
                          timestamp, level_name(level), msg);

    /* Ensure newline */
    size_t msg_len = strlen(msg);
    if (msg_len > 0 && msg[msg_len - 1] != '\n') {
        fprintf(g_log.file, "\n");
        written++;
    }

    fflush(g_log.file);

    if (written > 0) {
        g_log.current_size += written;

        /* Check if rotation needed */
        if (g_log.current_size >= LOG_MAX_SIZE) {
            rotate_logs();
        }
    }
}

/**
 * @brief Baresip log handler callback
 */
static void baresip_log_handler(uint32_t level, const char *msg)
{
    pthread_mutex_lock(&g_log.mutex);
    write_log(baresip_to_tp_level(level), msg);
    pthread_mutex_unlock(&g_log.mutex);
}

/* =============================================================================
 * Public API
 * ============================================================================= */

tp_error_t tp_log_init(const char *log_dir)
{
    pthread_mutex_lock(&g_log.mutex);

    if (g_log.initialized) {
        pthread_mutex_unlock(&g_log.mutex);
        return TP_ERR_ALREADY_INITIALIZED;
    }

    if (!log_dir || log_dir[0] == '\0') {
        pthread_mutex_unlock(&g_log.mutex);
        return TP_ERR_INVALID_ARG;
    }

    /* Store directory and build path */
    re_snprintf(g_log.dir, sizeof(g_log.dir), "%s", log_dir);
    re_snprintf(g_log.path, sizeof(g_log.path), "%s/%s", log_dir, LOG_FILENAME);

    /* Open log file (append mode) */
    g_log.file = fopen(g_log.path, "a");
    if (!g_log.file) {
        warning("tp_log: failed to open log file: %s\n", g_log.path);
        pthread_mutex_unlock(&g_log.mutex);
        return TP_ERR_INTERNAL;
    }

    g_log.current_size = get_file_size(g_log.path);
    g_log.initialized = true;

    /* Register with baresip logging */
    g_log.baresip_log.h = baresip_log_handler;
    log_register_handler(&g_log.baresip_log);

    /* Configure baresip log level */
    log_level_set(tp_to_baresip_level(g_log.level));

    pthread_mutex_unlock(&g_log.mutex);

    /* Log startup message */
    tp_log_write(TP_LOG_INFO, "tp_log: logging initialized to %s", g_log.path);

    return TP_OK;
}

void tp_log_close(void)
{
    pthread_mutex_lock(&g_log.mutex);

    if (!g_log.initialized) {
        pthread_mutex_unlock(&g_log.mutex);
        return;
    }

    /* Unregister from baresip */
    log_unregister_handler(&g_log.baresip_log);

    /* Close file */
    if (g_log.file) {
        fclose(g_log.file);
        g_log.file = NULL;
    }

    g_log.initialized = false;

    pthread_mutex_unlock(&g_log.mutex);
}

tp_error_t tp_log_set_level(tp_log_level_t level)
{
    pthread_mutex_lock(&g_log.mutex);

    g_log.level = level;

    /* Update baresip log level */
    if (g_log.initialized) {
        log_level_set(tp_to_baresip_level(level));
    }

    pthread_mutex_unlock(&g_log.mutex);

    return TP_OK;
}

tp_log_level_t tp_log_get_level(void)
{
    return g_log.level;
}

void tp_log_write(tp_log_level_t level, const char *fmt, ...)
{
    char buf[LOG_BUFFER_SIZE];
    va_list ap;

    va_start(ap, fmt);
    re_vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);

    pthread_mutex_lock(&g_log.mutex);
    write_log(level, buf);
    pthread_mutex_unlock(&g_log.mutex);
}

tp_error_t tp_log_get_path(char *buf, size_t size)
{
    if (!buf || size == 0)
        return TP_ERR_INVALID_ARG;

    pthread_mutex_lock(&g_log.mutex);

    if (!g_log.initialized) {
        pthread_mutex_unlock(&g_log.mutex);
        return TP_ERR_NOT_INITIALIZED;
    }

    re_snprintf(buf, size, "%s", g_log.path);

    pthread_mutex_unlock(&g_log.mutex);

    return TP_OK;
}

tp_error_t tp_log_flush(void)
{
    pthread_mutex_lock(&g_log.mutex);

    if (g_log.file) {
        fflush(g_log.file);
    }

    pthread_mutex_unlock(&g_log.mutex);

    return TP_OK;
}
