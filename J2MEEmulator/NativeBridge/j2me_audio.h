#ifndef J2ME_AUDIO_H
#define J2ME_AUDIO_H

#include "jvm.h"

#ifdef __cplusplus
extern "C" {
#endif

/// Register audio-related native methods with the JVM.
void j2me_audio_reg_natives(MiniJVM *jvm);

/// Stop and release all active audio players. Call between game sessions.
void j2me_audio_stop_all(void);

/// Mute/unmute players belonging to one MiniJVM session without stopping them.
void j2me_audio_set_active_jvm(MiniJVM *jvm);

#ifdef __cplusplus
}
#endif

#endif /* J2ME_AUDIO_H */
