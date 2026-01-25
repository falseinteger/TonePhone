//
//  tp_bridge.h
//  TonePhone
//
//  Stable C API bridge layer for Swift interoperability.
//  This header exposes only the public API that Swift code should use.
//
//  Note: This is currently a thin wrapper around baresip internals.
//  A proper bridge implementation with tp_* functions will replace
//  these direct includes in future iterations.
//

#ifndef tp_bridge_h
#define tp_bridge_h

#ifdef __cplusplus
extern "C" {
#endif

// TODO: Replace these internal header includes with stable tp_* API declarations
// once the bridge layer is implemented. For now, expose baresip APIs directly.
#include <re/re.h>
#include <baresip.h>

// Future bridge API declarations will go here:
// int tp_init(void);
// void tp_close(void);
// int tp_account_add(const char *uri, const char *password);
// int tp_call_start(const char *uri);
// void tp_call_hangup(void);
// ... etc

#ifdef __cplusplus
}
#endif

#endif /* tp_bridge_h */
