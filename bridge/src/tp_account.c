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
    struct ua *removing_ua;  /* UA pointer kept for event lookup during removal */
    bool in_use;
    bool removing;  /* Account is being removed, still valid for event lookups */
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
 * @param include_removing If true, also return accounts being removed
 */
static account_entry_t *find_account_ex(tp_account_id_t id, bool include_removing)
{
    for (int i = 0; i < MAX_ACCOUNTS; i++) {
        account_entry_t *e = &g_accounts.accounts[i];
        if (e->id == id) {
            if (e->in_use && !e->removing) {
                return e;
            }
            if (include_removing && (e->in_use || e->removing)) {
                return e;
            }
        }
    }
    return NULL;
}

/**
 * @brief Find an account entry by ID (excludes accounts being removed)
 */
static account_entry_t *find_account(tp_account_id_t id)
{
    return find_account_ex(id, false);
}

/**
 * @brief Find a free account slot
 */
static account_entry_t *find_free_slot(void)
{
    for (int i = 0; i < MAX_ACCOUNTS; i++) {
        /* Skip slots that are in use or being removed */
        if (!g_accounts.accounts[i].in_use && !g_accounts.accounts[i].removing) {
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
        if (ret < 0 || (size_t)ret >= (sz - len))
            return ENOMEM;
        len += ret;
    }

    if (config->auth_user && config->auth_user[0] != '\0') {
        ret = re_snprintf(buf + len, sz - len, ";auth_user=%s",
                         config->auth_user);
        if (ret < 0 || (size_t)ret >= (sz - len))
            return ENOMEM;
        len += ret;
    }

    if (config->transport && config->transport[0] != '\0') {
        ret = re_snprintf(buf + len, sz - len, ";transport=%s",
                         config->transport);
        if (ret < 0 || (size_t)ret >= (sz - len))
            return ENOMEM;
        len += ret;
    }

    /* Add STUN server for NAT traversal */
    if (config->stun_server && config->stun_server[0] != '\0') {
        ret = re_snprintf(buf + len, sz - len, ";stunserver=%s",
                         config->stun_server);
        if (ret < 0 || (size_t)ret >= (sz - len))
            return ENOMEM;
        len += ret;
    }

    /* Add medianat for NAT traversal method */
    if (config->medianat && config->medianat[0] != '\0') {
        ret = re_snprintf(buf + len, sz - len, ";medianat=%s",
                         config->medianat);
        if (ret < 0 || (size_t)ret >= (sz - len))
            return ENOMEM;
        len += ret;
    }

    /* Add NAT pinhole keep-alive if enabled */
    if (config->nat_pinhole) {
        ret = re_snprintf(buf + len, sz - len, ";natpinhole=yes");
        if (ret < 0 || (size_t)ret >= (sz - len))
            return ENOMEM;
        len += ret;
    }

    /* Add registration interval to enable registration */
    ret = re_snprintf(buf + len, sz - len, ";regint=3600");
    if (ret < 0 || (size_t)ret >= (sz - len))
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

    /* Log configuration (without password) */
    info("tp_account: creating UA for %s\n", config->sip_uri);
    info("tp_account: transport=%s, stun=%s, medianat=%s, natpinhole=%s\n",
         config->transport ? config->transport : "(none)",
         config->stun_server ? config->stun_server : "(none)",
         config->medianat ? config->medianat : "(none)",
         config->nat_pinhole ? "yes" : "no");
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

    /* Already being removed? */
    if (entry->removing) {
        pthread_mutex_unlock(&g_mutex);
        return TP_OK;
    }

    /* Move UA to removing_ua for event lookups, clear main ua */
    ua_to_remove = entry->ua;
    entry->removing_ua = entry->ua;  /* Keep for event lookup (no extra ref needed) */
    entry->ua = NULL;
    entry->in_use = false;
    entry->removing = true;

    /* Update default if needed */
    if (g_accounts.default_id == id) {
        g_accounts.default_id = TP_INVALID_ID;
        /* Find another account to be default */
        for (int i = 0; i < MAX_ACCOUNTS; i++) {
            if (g_accounts.accounts[i].in_use && !g_accounts.accounts[i].removing) {
                g_accounts.default_id = g_accounts.accounts[i].id;
                break;
            }
        }
    }

    pthread_mutex_unlock(&g_mutex);

    /* Unregister UA outside of mutex - this may fire events.
     * Events can still find account via removing_ua pointer match. */
    if (ua_to_remove) {
        ua_unregister(ua_to_remove);
        mem_deref(ua_to_remove);
    }

    /* Clear removing state (entry is already cleared above) */
    entry->removing_ua = NULL;
    entry->removing = false;

    info("tp_account: removed account %u\n", id);

    return TP_OK;
}

tp_error_t tp_account_register(tp_account_id_t id)
{
    int err;
    account_entry_t *entry;
    struct ua *ua;
    tp_error_t result = TP_OK;

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

    /* Acquire reference to UA before unlocking to prevent use-after-free */
    ua = mem_ref(entry->ua);
    pthread_mutex_unlock(&g_mutex);

    /* Check if already registered */
    if (ua_isregistered(ua)) {
        info("tp_account: account %u already registered\n", id);
        mem_deref(ua);
        return TP_OK;
    }

    /* Register with server */
    info("tp_account: registering account %u\n", id);
    err = ua_register(ua);
    if (err) {
        warning("tp_account: ua_register failed: %m\n", err);
        result = TP_ERR_REGISTRATION_FAILED;
    }

    mem_deref(ua);
    return result;
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

    /* Acquire reference to UA before unlocking to prevent use-after-free */
    ua = mem_ref(entry->ua);
    pthread_mutex_unlock(&g_mutex);

    info("tp_account: unregistering account %u\n", id);
    ua_unregister(ua);

    mem_deref(ua);
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

tp_error_t tp_account_get_state(tp_account_id_t id, tp_account_state_t *out_state)
{
    account_entry_t *entry;
    struct ua *ua;

    if (id == TP_INVALID_ID || !out_state) {
        return TP_ERR_INVALID_ARG;
    }

    pthread_mutex_lock(&g_mutex);

    entry = find_account(id);
    if (!entry) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_NOT_FOUND;
    }

    ua = entry->ua;
    if (!ua) {
        pthread_mutex_unlock(&g_mutex);
        *out_state = TP_ACCOUNT_STATE_UNREGISTERED;
        return TP_OK;
    }

    /* Query baresip for registration state.
     *
     * Note: baresip doesn't expose ua_isregistering(), so we cannot detect
     * the transitional "registering" state synchronously. The REGISTERING
     * state is tracked via events (TP_EVENT_ACCOUNT_STATE_CHANGED).
     * This function returns UNREGISTERED for accounts that are in the
     * process of registering. Use events for real-time state tracking.
     */
    if (ua_isregistered(ua)) {
        *out_state = TP_ACCOUNT_STATE_REGISTERED;
    } else if (ua_regfailed(ua)) {
        *out_state = TP_ACCOUNT_STATE_FAILED;
    } else {
        *out_state = TP_ACCOUNT_STATE_UNREGISTERED;
    }

    pthread_mutex_unlock(&g_mutex);

    return TP_OK;
}

tp_error_t tp_account_get_default(tp_account_id_t *out_id)
{
    if (!out_id) {
        return TP_ERR_INVALID_ARG;
    }

    pthread_mutex_lock(&g_mutex);
    *out_id = g_accounts.default_id;
    pthread_mutex_unlock(&g_mutex);

    return TP_OK;
}

uint32_t tp_account_count(void)
{
    uint32_t count = 0;

    pthread_mutex_lock(&g_mutex);

    for (int i = 0; i < MAX_ACCOUNTS; i++) {
        if (g_accounts.accounts[i].in_use && !g_accounts.accounts[i].removing) {
            count++;
        }
    }

    pthread_mutex_unlock(&g_mutex);

    return count;
}

tp_error_t tp_account_get_id_at_index(uint32_t index, tp_account_id_t *out_id)
{
    uint32_t current = 0;

    if (!out_id) {
        return TP_ERR_INVALID_ARG;
    }

    *out_id = TP_INVALID_ID;

    pthread_mutex_lock(&g_mutex);

    for (int i = 0; i < MAX_ACCOUNTS; i++) {
        if (g_accounts.accounts[i].in_use && !g_accounts.accounts[i].removing) {
            if (current == index) {
                *out_id = g_accounts.accounts[i].id;
                pthread_mutex_unlock(&g_mutex);
                return TP_OK;
            }
            current++;
        }
    }

    pthread_mutex_unlock(&g_mutex);

    return TP_ERR_NOT_FOUND;
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
        account_entry_t *e = &g_accounts.accounts[i];

        /* Check active accounts */
        if (e->in_use && e->ua == ua) {
            result = e->id;
            break;
        }

        /* Check accounts being removed (match against removing_ua) */
        if (e->removing && e->removing_ua == ua) {
            result = e->id;
            break;
        }
    }

    pthread_mutex_unlock(&g_mutex);

    return result;
}

struct ua *tp_account_get_default_ua(void)
{
    struct ua *ua = NULL;

    pthread_mutex_lock(&g_mutex);

    if (g_accounts.default_id != TP_INVALID_ID) {
        account_entry_t *entry = find_account(g_accounts.default_id);
        if (entry && entry->ua) {
            ua = mem_ref(entry->ua);
        }
    }

    pthread_mutex_unlock(&g_mutex);

    return ua;
}
