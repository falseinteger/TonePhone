/**
 * @file tp_account.c
 * @brief TonePhone Bridge - Account management implementation
 *
 * Implements account lifecycle functions wrapping baresip's User Agent (UA) system.
 */

#include "tp_internal.h"
#include "tp_bridge.h"

#include <re.h>
#include <baresip.h>

#include <string.h>
#include <stdlib.h>

/* =============================================================================
 * Constants
 * ============================================================================= */

#define MAX_ACCOUNTS 16
#define MAX_AOR_LEN 512

/* =============================================================================
 * Module State
 * ============================================================================= */

/**
 * @brief Account entry mapping our IDs to baresip UAs
 */
typedef struct {
    tp_account_id_t id;
    struct ua *ua;
    bool in_use;
} account_entry_t;

static struct {
    account_entry_t accounts[MAX_ACCOUNTS];
    tp_account_id_t next_id;
    tp_account_id_t default_id;
} g_accounts = {
    .next_id = 1,  /* Start at 1, 0 is invalid */
    .default_id = TP_INVALID_ID,
};

/* =============================================================================
 * Internal Helpers
 * ============================================================================= */

/**
 * @brief Post an account failure event
 *
 * Used when registration fails immediately (before baresip can fire an event).
 */
static void post_account_failure_event(tp_account_id_t id, const char *reason)
{
    tp_event_callback_t cb;
    void *ctx;

    tp_get_event_callback(&cb, &ctx);
    if (!cb)
        return;

    tp_event_t event = {
        .type = TP_EVENT_ACCOUNT_STATE_CHANGED,
        .data.account = {
            .id = id,
            .state = TP_ACCOUNT_STATE_FAILED,
            .reason = reason,
        },
    };

    info("tp_account: posting failure event for account %u: %s\n", id, reason);
    cb(&event, ctx);
}

/**
 * @brief Find an account entry by ID
 */
static account_entry_t *find_account(tp_account_id_t id)
{
    for (int i = 0; i < MAX_ACCOUNTS; i++) {
        if (g_accounts.accounts[i].in_use && g_accounts.accounts[i].id == id) {
            return &g_accounts.accounts[i];
        }
    }
    return NULL;
}

/**
 * @brief Find a free account slot
 */
static account_entry_t *find_free_slot(void)
{
    for (int i = 0; i < MAX_ACCOUNTS; i++) {
        if (!g_accounts.accounts[i].in_use) {
            return &g_accounts.accounts[i];
        }
    }
    return NULL;
}

/**
 * @brief Build an AOR string from account config
 *
 * Format: "Display Name" <sip:user@domain>;auth_pass=password
 */
static int build_aor(char *buf, size_t sz, const tp_account_config_t *config)
{
    int ret;

    /* Basic validation */
    if (!config->sip_uri || !config->password) {
        return EINVAL;
    }

    /* Build AOR with credentials */
    if (config->display_name && config->display_name[0] != '\0') {
        ret = re_snprintf(buf, sz, "\"%s\" <%s>;auth_pass=%s",
                         config->display_name,
                         config->sip_uri,
                         config->password);
    } else {
        ret = re_snprintf(buf, sz, "<%s>;auth_pass=%s",
                         config->sip_uri,
                         config->password);
    }

    if (ret < 0 || (size_t)ret >= sz) {
        return ENOMEM;
    }

    /* Add optional parameters */
    size_t len = strlen(buf);

    if (config->outbound_proxy && config->outbound_proxy[0] != '\0') {
        ret = re_snprintf(buf + len, sz - len, ";outbound=\"%s\"",
                         config->outbound_proxy);
        if (ret < 0)
            return ENOMEM;
        len += ret;
    }

    if (config->auth_user && config->auth_user[0] != '\0') {
        ret = re_snprintf(buf + len, sz - len, ";auth_user=%s",
                         config->auth_user);
        if (ret < 0)
            return ENOMEM;
        len += ret;
    }

    if (config->transport && config->transport[0] != '\0') {
        ret = re_snprintf(buf + len, sz - len, ";transport=%s",
                         config->transport);
        if (ret < 0)
            return ENOMEM;
        len += ret;
    }

    /* Add registration interval to enable registration */
    ret = re_snprintf(buf + len, sz - len, ";regint=3600");
    if (ret < 0)
        return ENOMEM;

    return 0;
}

/* =============================================================================
 * Account Functions
 * ============================================================================= */

tp_error_t tp_account_add(const tp_account_config_t *config,
                          tp_account_id_t *out_id)
{
    int err;
    char aor[MAX_AOR_LEN];
    struct ua *ua = NULL;
    account_entry_t *entry;

    if (!config || !out_id) {
        return TP_ERR_INVALID_ARG;
    }

    if (!config->sip_uri || !config->password) {
        return TP_ERR_INVALID_ARG;
    }

    *out_id = TP_INVALID_ID;

    pthread_mutex_lock(&g_mutex);

    /* Find free slot */
    entry = find_free_slot();
    if (!entry) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_NO_MEMORY;
    }

    /* Build AOR string */
    err = build_aor(aor, sizeof(aor), config);
    if (err) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_INVALID_ARG;
    }

    info("tp_account: creating UA with AOR: %s\n", aor);
    info("tp_account: conf_cur() = %p, conf_config() = %p\n",
         conf_cur(), conf_config());

    /* Allocate UA */
    err = ua_alloc(&ua, aor);
    if (err) {
        warning("tp_account: ua_alloc failed: %m\n", err);
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_INTERNAL;
    }

    /* Assign ID and store */
    entry->id = g_accounts.next_id++;
    entry->ua = ua;
    entry->in_use = true;

    /* Set as default if it's the first account */
    if (g_accounts.default_id == TP_INVALID_ID) {
        g_accounts.default_id = entry->id;
    }

    *out_id = entry->id;

    pthread_mutex_unlock(&g_mutex);

    info("tp_account: added account %u\n", entry->id);

    /* Register if requested
     * Note: ua_alloc should have already started registration if the AOR
     * is properly configured. We only call ua_register explicitly if needed.
     */
    if (config->register_on_add) {
        /* Check if already registering/registered */
        if (!ua_isregistered(ua)) {
            info("tp_account: calling ua_register for account %u, uag_sip=%p\n",
                 entry->id, uag_sip());
            int reg_err = ua_register(ua);
            if (reg_err) {
                warning("tp_account: ua_register failed: %m\n", reg_err);
                /* Fire a failure event manually since baresip won't */
                post_account_failure_event(entry->id, "Registration failed");
            }
        } else {
            info("tp_account: account %u already registered\n", entry->id);
        }
    }

    return TP_OK;
}

tp_error_t tp_account_remove(tp_account_id_t id)
{
    account_entry_t *entry;
    struct ua *ua_to_remove = NULL;

    if (id == TP_INVALID_ID) {
        return TP_ERR_INVALID_ARG;
    }

    pthread_mutex_lock(&g_mutex);

    entry = find_account(id);
    if (!entry) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_NOT_FOUND;
    }

    /* Save UA pointer and clear from entry */
    if (entry->ua) {
        ua_to_remove = entry->ua;
        entry->ua = NULL;
    }

    entry->in_use = false;

    /* Update default if needed */
    if (g_accounts.default_id == id) {
        g_accounts.default_id = TP_INVALID_ID;
        /* Find another account to be default */
        for (int i = 0; i < MAX_ACCOUNTS; i++) {
            if (g_accounts.accounts[i].in_use) {
                g_accounts.default_id = g_accounts.accounts[i].id;
                break;
            }
        }
    }

    pthread_mutex_unlock(&g_mutex);

    /* Unregister and free UA outside of mutex to avoid deadlock */
    if (ua_to_remove) {
        ua_unregister(ua_to_remove);
        mem_deref(ua_to_remove);
    }

    info("tp_account: removed account %u\n", id);

    return TP_OK;
}

tp_error_t tp_account_register(tp_account_id_t id)
{
    int err;
    account_entry_t *entry;

    if (id == TP_INVALID_ID) {
        return TP_ERR_INVALID_ARG;
    }

    pthread_mutex_lock(&g_mutex);

    entry = find_account(id);
    if (!entry) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_NOT_FOUND;
    }

    if (!entry->ua) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_INTERNAL;
    }

    struct ua *ua = entry->ua;
    pthread_mutex_unlock(&g_mutex);

    /* Check if already registered */
    if (ua_isregistered(ua)) {
        info("tp_account: account %u already registered\n", id);
        return TP_OK;
    }

    /* Register with server */
    info("tp_account: registering account %u\n", id);
    err = ua_register(ua);
    if (err) {
        warning("tp_account: ua_register failed: %m\n", err);
        return TP_ERR_REGISTRATION_FAILED;
    }

    return TP_OK;
}

tp_error_t tp_account_unregister(tp_account_id_t id)
{
    account_entry_t *entry;
    struct ua *ua;

    if (id == TP_INVALID_ID) {
        return TP_ERR_INVALID_ARG;
    }

    pthread_mutex_lock(&g_mutex);

    entry = find_account(id);
    if (!entry) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_NOT_FOUND;
    }

    if (!entry->ua) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_INTERNAL;
    }

    /* Copy UA pointer and release mutex before calling baresip
     * to avoid deadlock with event callbacks */
    ua = entry->ua;
    pthread_mutex_unlock(&g_mutex);

    info("tp_account: unregistering account %u\n", id);
    ua_unregister(ua);

    return TP_OK;
}

tp_error_t tp_account_set_default(tp_account_id_t id)
{
    account_entry_t *entry;

    if (id == TP_INVALID_ID) {
        return TP_ERR_INVALID_ARG;
    }

    pthread_mutex_lock(&g_mutex);

    entry = find_account(id);
    if (!entry) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_NOT_FOUND;
    }

    if (!entry->ua) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_INTERNAL;
    }

    g_accounts.default_id = id;

    pthread_mutex_unlock(&g_mutex);

    info("tp_account: set default account %u\n", id);

    return TP_OK;
}

/* =============================================================================
 * ID Lookup (for event system)
 * ============================================================================= */

tp_account_id_t tp_account_find_id_by_ua(const struct ua *ua)
{
    tp_account_id_t result = TP_INVALID_ID;

    if (!ua) {
        return TP_INVALID_ID;
    }

    pthread_mutex_lock(&g_mutex);

    for (int i = 0; i < MAX_ACCOUNTS; i++) {
        if (g_accounts.accounts[i].in_use && g_accounts.accounts[i].ua == ua) {
            result = g_accounts.accounts[i].id;
            break;
        }
    }

    pthread_mutex_unlock(&g_mutex);

    return result;
}
