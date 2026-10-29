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

#include <stdarg.h>
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
 * @brief Append formatted text to an AOR buffer
 */
static int aor_append(char *buf, size_t sz, size_t *len, const char *fmt, ...)
{
    va_list ap;
    int ret;

    va_start(ap, fmt);
    ret = re_vsnprintf(buf + *len, sz - *len, fmt, ap);
    va_end(ap);

    if (ret < 0 || (size_t)ret >= (sz - *len))
        return ENOMEM;

    *len += ret;
    return 0;
}

/**
 * @brief Build an AOR string from account config
 *
 * Format: <sip:user@domain;transport=tcp>;regint=600;...
 *
 * Credentials, auth user, outbound proxy and display name are applied
 * through the baresip account setters after the UA is created, so values
 * containing ';', '"' or '>' cannot corrupt the AOR.
 * The transport must be a URI parameter (inside the angle brackets);
 * baresip ignores it as an address parameter.
 */
static int build_aor(char *buf, size_t sz, const tp_account_config_t *config)
{
    size_t len = 0;
    int err = 0;

    if (!config->sip_uri || !config->password) {
        return EINVAL;
    }

    buf[0] = '\0';

    err |= aor_append(buf, sz, &len, "<%s", config->sip_uri);

    if (config->transport && config->transport[0] != '\0' &&
        !strstr(config->sip_uri, ";transport=")) {
        err |= aor_append(buf, sz, &len, ";transport=%s", config->transport);
    }

    err |= aor_append(buf, sz, &len, ">;regint=%u",
                      config->reg_interval ? config->reg_interval : 3600);

    if (config->stun_server && config->stun_server[0] != '\0')
        err |= aor_append(buf, sz, &len, ";stunserver=%s", config->stun_server);

    if (config->medianat && config->medianat[0] != '\0')
        err |= aor_append(buf, sz, &len, ";medianat=%s", config->medianat);

    if (config->media_encryption && config->media_encryption[0] != '\0')
        err |= aor_append(buf, sz, &len, ";mediaenc=%s", config->media_encryption);

    if (config->dtmf_mode && config->dtmf_mode[0] != '\0')
        err |= aor_append(buf, sz, &len, ";dtmfmode=%s", config->dtmf_mode);

    if (config->nat_pinhole)
        err |= aor_append(buf, sz, &len, ";natpinhole=yes");

    /* baresip subscribes to voicemail by default; make it explicit */
    err |= aor_append(buf, sz, &len, ";mwi=%s", config->mwi ? "yes" : "no");

    return err ? ENOMEM : 0;
}

/**
 * @brief Apply credentials and optional settings to a freshly created UA
 */
static int apply_account_settings(struct ua *ua, const tp_account_config_t *config)
{
    struct account *acc = ua_account(ua);
    int err = 0;

    if (!acc)
        return EINVAL;

    err |= account_set_auth_pass(acc, config->password);

    if (config->auth_user && config->auth_user[0] != '\0')
        err |= account_set_auth_user(acc, config->auth_user);

    if (config->display_name && config->display_name[0] != '\0')
        err |= account_set_display_name(acc, config->display_name);

    if (config->outbound_proxy && config->outbound_proxy[0] != '\0')
        err |= account_set_outbound(acc, config->outbound_proxy, 0);

    if (err)
        return err;

    /* Recreate register clients so the outbound proxy takes effect */
    return ua_update_account(ua);
}

/* =============================================================================
 * Account Functions
 *
 * Every public function that touches baresip objects runs inside
 * re_thread_enter()/re_thread_leave(): the SIP stack runs its main loop on
 * the bridge thread, and libre objects must never be used concurrently.
 * Lock order is always re lock first, then g_mutex.
 * ============================================================================= */

static tp_error_t account_add(const tp_account_config_t *config,
                              tp_account_id_t *out_id)
{
    int err;
    char aor[MAX_AOR_LEN];
    struct ua *ua = NULL;
    account_entry_t *entry;

    pthread_mutex_lock(&g_mutex);

    /* Find free slot */
    entry = find_free_slot();
    if (!entry) {
        pthread_mutex_unlock(&g_mutex);
        return TP_ERR_NO_MEMORY;
    }

    pthread_mutex_unlock(&g_mutex);

    /* Build AOR string */
    err = build_aor(aor, sizeof(aor), config);
    if (err) {
        return TP_ERR_INVALID_ARG;
    }

    /* Log configuration (AOR never contains the password) */
    info("tp_account: creating UA %s\n", aor);
    info("tp_account: auth_user=%s, outbound=%s\n",
         (config->auth_user && config->auth_user[0]) ? config->auth_user : "(uri user)",
         (config->outbound_proxy && config->outbound_proxy[0]) ? config->outbound_proxy : "(none)");

    /* Allocate UA */
    err = ua_alloc(&ua, aor);
    if (err) {
        warning("tp_account: ua_alloc failed: %m\n", err);
        return TP_ERR_INVALID_ARG;
    }

    err = apply_account_settings(ua, config);
    if (err) {
        warning("tp_account: applying account settings failed: %m\n", err);
        mem_deref(ua);
        return TP_ERR_INVALID_ARG;
    }

    pthread_mutex_lock(&g_mutex);

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

    if (config->register_on_add && !ua_isregistered(ua)) {
        info("tp_account: registering account %u\n", entry->id);
        int reg_err = ua_register(ua);
        if (reg_err) {
            warning("tp_account: ua_register failed: %m\n", reg_err);
            /* Fire a failure event manually since baresip won't */
            post_account_failure_event(entry->id, "Could not send registration request");
        }
    }

    return TP_OK;
}

tp_error_t tp_account_add(const tp_account_config_t *config,
                          tp_account_id_t *out_id)
{
    tp_error_t result;

    if (!config || !out_id) {
        return TP_ERR_INVALID_ARG;
    }

    if (!config->sip_uri || !config->password) {
        return TP_ERR_INVALID_ARG;
    }

    *out_id = TP_INVALID_ID;

    re_thread_enter();
    result = account_add(config, out_id);
    re_thread_leave();

    return result;
}

static tp_error_t account_remove_locked(tp_account_id_t id)
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
        /* End the account's calls first so each one emits CALL_CLOSED */
        struct le *le = list_head(ua_calls(ua_to_remove));
        while (le) {
            struct call *call = le->data;
            le = le->next;
            ua_hangup(ua_to_remove, call, 0, "Account removed");
        }

        ua_unregister(ua_to_remove);

        /* ua_destroy (not mem_deref) unlinks the UA so it stops taking
         * calls, and emits BEVENT_SHUTDOWN so modules holding a reference
         * (mwi) unsubscribe and let go of it */
        ua_destroy(ua_to_remove);
    }

    /* Clear removing state (entry is already cleared above) */
    entry->removing_ua = NULL;
    entry->removing = false;

    info("tp_account: removed account %u\n", id);

    return TP_OK;
}

tp_error_t tp_account_remove(tp_account_id_t id)
{
    tp_error_t result;

    re_thread_enter();
    result = account_remove_locked(id);
    re_thread_leave();

    return result;
}

static tp_error_t account_register_locked(tp_account_id_t id)
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

tp_error_t tp_account_register(tp_account_id_t id)
{
    tp_error_t result;

    re_thread_enter();
    result = account_register_locked(id);
    re_thread_leave();

    return result;
}

static tp_error_t account_unregister_locked(tp_account_id_t id)
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

tp_error_t tp_account_unregister(tp_account_id_t id)
{
    tp_error_t result;

    re_thread_enter();
    result = account_unregister_locked(id);
    re_thread_leave();

    return result;
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

static tp_error_t account_get_state_locked(tp_account_id_t id, tp_account_state_t *out_state)
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

tp_error_t tp_account_get_state(tp_account_id_t id, tp_account_state_t *out_state)
{
    tp_error_t result;

    re_thread_enter();
    result = account_get_state_locked(id, out_state);
    re_thread_leave();

    return result;
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
