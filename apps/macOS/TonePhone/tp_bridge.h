//
//  tp_bridge.h
//  TonePhone
//
//  Stable C API bridge layer for Swift interoperability.
//  This header exposes only the public API that Swift code should use.
//
//  Note: baresip internals are NOT exposed here. Swift code should only
//  use the tp_* functions declared below. The implementation files will
//  include baresip headers internally.
//

#ifndef tp_bridge_h
#define tp_bridge_h

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// TonePhone Bridge API
// =============================================================================
//
// This is the stable C API boundary between Swift and baresip.
// All baresip functionality should be accessed through these functions.
//
// TODO: Implement the following bridge functions:
//
// Lifecycle
// int tp_init(void);
// void tp_close(void);
//
// Account Management
// int tp_account_add(const char *uri, const char *password);
// int tp_account_remove(const char *uri);
//
// Call Control
// int tp_call_start(const char *uri);
// void tp_call_answer(void);
// void tp_call_hangup(void);
//
// Audio Control
// void tp_audio_mute(int mute);
// void tp_audio_set_volume(float volume);
//
// Events (callback registration)
// typedef void (*tp_event_callback)(int event_type, const char *data);
// void tp_set_event_callback(tp_event_callback cb);

#ifdef __cplusplus
}
#endif

#endif /* tp_bridge_h */
