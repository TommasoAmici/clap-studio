#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef void *ClapVST3Module;
typedef void *ClapVST3Effect;
typedef void *ClapVST3Editor;
typedef void (*ClapVST3Resize)(void *context, int32_t width, int32_t height);
ClapVST3Module clap_vst3_module_open(const char *path);
void clap_vst3_module_close(ClapVST3Module module);
int32_t clap_vst3_class_count(ClapVST3Module module);
int32_t clap_vst3_class_info(ClapVST3Module module, int32_t index, char *id, char *name);
ClapVST3Effect clap_vst3_effect_create(ClapVST3Module module, const char *id);
void clap_vst3_effect_destroy(ClapVST3Effect effect);
int32_t clap_vst3_parameter_count(ClapVST3Effect effect);
int32_t clap_vst3_parameter_info(ClapVST3Effect effect, int32_t index, uint32_t *id, uint16_t *title, double *value, int32_t *steps);
void *clap_vst3_controller(ClapVST3Effect effect);
int32_t clap_vst3_parameter_set(ClapVST3Effect effect, uint32_t id, double value);
int32_t clap_vst3_state_get(ClapVST3Effect effect, int32_t controller, uint8_t **bytes, int32_t *size);
int32_t clap_vst3_state_set(ClapVST3Effect effect, int32_t controller, const uint8_t *bytes, int32_t size);
void clap_vst3_bytes_free(uint8_t *bytes);
ClapVST3Editor clap_vst3_editor_create(ClapVST3Effect effect);
int32_t clap_vst3_editor_attach(ClapVST3Editor editor, void *parent, ClapVST3Resize resize, void *context, int32_t *width, int32_t *height);
int32_t clap_vst3_editor_can_resize(ClapVST3Editor editor);
int32_t clap_vst3_editor_resize(ClapVST3Editor editor, int32_t *width, int32_t *height);
int16_t clap_vst3_editor_virtual_key(uint16_t apple_key);
int32_t clap_vst3_editor_key(ClapVST3Editor editor, uint16_t character, int16_t key, int16_t modifiers, int32_t down);
void clap_vst3_editor_focus(ClapVST3Editor editor, int32_t focused);
void clap_vst3_editor_destroy(ClapVST3Editor editor);
int32_t clap_vst3_prepare(ClapVST3Effect effect, double rate);
uint32_t clap_vst3_latency(ClapVST3Effect effect);
uint32_t clap_vst3_tail(ClapVST3Effect effect);
int32_t clap_vst3_process(ClapVST3Effect effect, float *left, float *right, int32_t frames, const uint32_t *ids, const double *values, int32_t parameterCount);
#ifdef __cplusplus
}
#endif
