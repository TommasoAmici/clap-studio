#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef void *ClapVST3Module;
typedef void *ClapVST3Effect;
ClapVST3Module clap_vst3_module_open(const char *path);
void clap_vst3_module_close(ClapVST3Module module);
int32_t clap_vst3_class_count(ClapVST3Module module);
int32_t clap_vst3_class_info(ClapVST3Module module, int32_t index, char *id, char *name);
ClapVST3Effect clap_vst3_effect_create(ClapVST3Module module, const char *id);
void clap_vst3_effect_destroy(ClapVST3Effect effect);
int32_t clap_vst3_parameter_count(ClapVST3Effect effect);
int32_t clap_vst3_parameter_info(ClapVST3Effect effect, int32_t index, uint32_t *id, uint16_t *title, double *value, int32_t *steps);
int32_t clap_vst3_prepare(ClapVST3Effect effect, double rate);
uint32_t clap_vst3_latency(ClapVST3Effect effect);
uint32_t clap_vst3_tail(ClapVST3Effect effect);
int32_t clap_vst3_process(ClapVST3Effect effect, float *left, float *right, int32_t frames, const uint32_t *ids, const double *values, int32_t parameterCount);
#ifdef __cplusplus
}
#endif
