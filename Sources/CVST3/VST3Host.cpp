#include "CVST3.h"
#include "HostMessages.hpp"
#include "pluginterfaces/base/ipluginbase.h"
#include "pluginterfaces/base/ibstream.h"
#include "pluginterfaces/vst/ivstcomponent.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "pluginterfaces/vst/ivsthostapplication.h"
#include "pluginterfaces/vst/ivstparameterchanges.h"
#include "pluginterfaces/vst/ivstprocesscontext.h"
#include "pluginterfaces/vst/vstspeaker.h"
#include <CoreFoundation/CoreFoundation.h>
#include <algorithm>
#include <vector>
#include <cstring>
#include <cstdio>
using namespace Steinberg;
using namespace Steinberg::Vst;
namespace {
// These host-owned interfaces live longer than the plugin and never delete themselves.
#define HOST_REFS uint32 PLUGIN_API addRef() override { return 1; } uint32 PLUGIN_API release() override { return 1; }
#define HOST_QUERY(TYPE) tresult PLUGIN_API queryInterface(const TUID iid, void **obj) override { \
    if (!obj) return kInvalidArgument; *obj = nullptr; \
    if (!memcmp(iid, INLINE_UID_OF(TYPE), 16) || !memcmp(iid, INLINE_UID_OF(FUnknown), 16)) { *obj = static_cast<TYPE *>(this); return kResultOk; } return kNoInterface; }
struct Host : IHostApplication {
    HOST_REFS HOST_QUERY(IHostApplication)
    tresult PLUGIN_API getName(String128 name) override { const char *s = "Clap Studio"; int i = 0; for (; s[i]; ++i) name[i] = s[i]; name[i] = 0; return kResultOk; }
    tresult PLUGIN_API createInstance(TUID cid, TUID iid, void **obj) override {
        if (!obj) return kInvalidArgument; *obj = nullptr;
        if (!memcmp(cid, INLINE_UID_OF(IMessage), 16) && !memcmp(iid, INLINE_UID_OF(IMessage), 16)) *obj = new ClapHost::Message;
        else if (!memcmp(cid, INLINE_UID_OF(IAttributeList), 16) && !memcmp(iid, INLINE_UID_OF(IAttributeList), 16)) *obj = new ClapHost::Attributes;
        return *obj ? kResultOk : kNoInterface;
    }
};
struct Stream : IBStream {
    std::vector<uint8_t> bytes; int64 position = 0;
    HOST_REFS HOST_QUERY(IBStream)
    tresult PLUGIN_API read(void *b, int32 n, int32 *actual) override {
        if (n < 0 || !b) return kInvalidArgument;
        int32 count = static_cast<int32>(std::min<int64>(n, bytes.size() - position));
        if (count) memcpy(b, bytes.data() + position, count); position += count;
        if (actual) *actual = count; return count == n ? kResultOk : kResultFalse;
    }
    tresult PLUGIN_API write(void *b, int32 n, int32 *actual) override {
        if (n < 0 || !b || position + n > 64 * 1024 * 1024) return kInvalidArgument;
        bytes.resize(std::max<int64>(bytes.size(), position + n)); memcpy(bytes.data() + position, b, n); position += n;
        if (actual) *actual = n; return kResultOk;
    }
    tresult PLUGIN_API seek(int64 p, int32 mode, int64 *result) override {
        int64 target = p + (mode == kIBSeekCur ? position : mode == kIBSeekEnd ? bytes.size() : 0);
        if (target < 0 || target > static_cast<int64>(bytes.size())) return kInvalidArgument;
        position = target; if (result) *result = position; return kResultOk;
    }
    tresult PLUGIN_API tell(int64 *p) override { if (!p) return kInvalidArgument; *p = position; return kResultOk; }
};
struct Queue : IParamValueQueue {
    ParamID id; double value;
    Queue(ParamID id, double value) : id(id), value(value) {}
    HOST_REFS HOST_QUERY(IParamValueQueue)
    ParamID PLUGIN_API getParameterId() override { return id; }
    int32 PLUGIN_API getPointCount() override { return 1; }
    tresult PLUGIN_API getPoint(int32 index, int32 &offset, ParamValue &v) override { if (index != 0) return kInvalidArgument; offset = 0; v = value; return kResultOk; }
    tresult PLUGIN_API addPoint(int32, ParamValue, int32 &) override { return kNotImplemented; }
};
struct Changes : IParameterChanges {
    std::vector<Queue> queues;
    HOST_REFS HOST_QUERY(IParameterChanges)
    int32 PLUGIN_API getParameterCount() override { return static_cast<int32>(queues.size()); }
    IParamValueQueue *PLUGIN_API getParameterData(int32 i) override { return i >= 0 && i < getParameterCount() ? &queues[i] : nullptr; }
    IParamValueQueue *PLUGIN_API addParameterData(const ParamID &, int32 &) override { return nullptr; }
};
struct Module {
    CFBundleRef bundle = nullptr; IPluginFactory *factory = nullptr; bool entered = false;
    ~Module() {
        if (factory) factory->release();
        if (bundle) {
            auto exit = reinterpret_cast<bool (*)()>(CFBundleGetFunctionPointerForName(bundle, CFSTR("bundleExit")));
            if (entered && exit) exit();
            CFBundleUnloadExecutable(bundle); CFRelease(bundle);
        }
    }
};
struct Effect {
    Host host; IComponent *component = nullptr; IAudioProcessor *processor = nullptr;
    IEditController *controller = nullptr; bool initialized = false, separateController = false, active = false, processing = false;
    IConnectionPoint *componentConnection = nullptr, *controllerConnection = nullptr;
    double rate = 44100; int64 position = 0;
    ~Effect() {
        if (processing) processor->setProcessing(false);
        if (active) component->setActive(false);
        if (componentConnection && controllerConnection) { componentConnection->disconnect(controllerConnection); controllerConnection->disconnect(componentConnection); }
        if (componentConnection) componentConnection->release();
        if (controllerConnection) controllerConnection->release();
        if (controller) { if (separateController) controller->terminate(); controller->release(); }
        if (processor) processor->release();
        if (component) { if (initialized) component->terminate(); component->release(); }
    }
};
}
extern "C" {
ClapVST3Module clap_vst3_module_open(const char *path) {
    if (!path) return nullptr;
    auto m = new Module;
    auto url = CFURLCreateFromFileSystemRepresentation(nullptr, reinterpret_cast<const UInt8 *>(path), strlen(path), true);
    m->bundle = url ? CFBundleCreate(nullptr, url) : nullptr; if (url) CFRelease(url);
    if (!m->bundle || !CFBundleLoadExecutable(m->bundle)) { delete m; return nullptr; }
    auto entry = reinterpret_cast<bool (*)(CFBundleRef)>(CFBundleGetFunctionPointerForName(m->bundle, CFSTR("bundleEntry")));
    if (entry && !entry(m->bundle)) { delete m; return nullptr; } m->entered = true;
    auto factory = reinterpret_cast<IPluginFactory *(*)()>(CFBundleGetFunctionPointerForName(m->bundle, CFSTR("GetPluginFactory")));
    m->factory = factory ? factory() : nullptr;
    if (!m->factory) { delete m; return nullptr; } return m;
}
void clap_vst3_module_close(ClapVST3Module m) { delete static_cast<Module *>(m); }
int32_t clap_vst3_class_count(ClapVST3Module m) { return m ? static_cast<Module *>(m)->factory->countClasses() : 0; }
int32_t clap_vst3_class_info(ClapVST3Module m, int32_t index, char *id, char *name) {
    PClassInfo info{}; if (!m || static_cast<Module *>(m)->factory->getClassInfo(index, &info) != kResultOk || strcmp(info.category, kVstAudioEffectClass)) return 0;
    for (int i = 0; i < 16; ++i) snprintf(id + i * 2, 3, "%02X", static_cast<unsigned char>(info.cid[i]));
    memcpy(name, info.name, 64); name[63] = 0; return 1;
}
ClapVST3Effect clap_vst3_effect_create(ClapVST3Module m, const char *id) {
    if (!m || !id || strlen(id) != 32) return nullptr;
    TUID cid; for (int i = 0; i < 16; ++i) { unsigned int byte; if (sscanf(id + i * 2, "%2x", &byte) != 1) return nullptr; cid[i] = byte; }
    auto e = new Effect;
    auto factory = static_cast<Module *>(m)->factory;
    if (factory->createInstance(cid, INLINE_UID_OF(IComponent), reinterpret_cast<void **>(&e->component)) != kResultOk || !e->component) { delete e; return nullptr; }
    if (e->component->initialize(&e->host) != kResultOk) { delete e; return nullptr; } e->initialized = true;
    if (e->component->queryInterface(INLINE_UID_OF(IAudioProcessor), reinterpret_cast<void **>(&e->processor)) != kResultOk) { delete e; return nullptr; }
    e->component->queryInterface(INLINE_UID_OF(IEditController), reinterpret_cast<void **>(&e->controller));
    if (!e->controller) {
        TUID controllerID;
        if (e->component->getControllerClassId(controllerID) == kResultOk && factory->createInstance(controllerID, INLINE_UID_OF(IEditController), reinterpret_cast<void **>(&e->controller)) == kResultOk && e->controller) {
            if (e->controller->initialize(&e->host) != kResultOk) { e->controller->release(); e->controller = nullptr; }
            else e->separateController = true;
        }
    }
    if (e->separateController) {
        e->component->queryInterface(INLINE_UID_OF(IConnectionPoint), reinterpret_cast<void **>(&e->componentConnection));
        e->controller->queryInterface(INLINE_UID_OF(IConnectionPoint), reinterpret_cast<void **>(&e->controllerConnection));
        if (e->componentConnection && e->controllerConnection) { e->componentConnection->connect(e->controllerConnection); e->controllerConnection->connect(e->componentConnection); }
    }
    if (e->controller) { Stream stream; if (e->component->getState(&stream) == kResultOk) { stream.position = 0; e->controller->setComponentState(&stream); } }
    return e;
}
void clap_vst3_effect_destroy(ClapVST3Effect e) { delete static_cast<Effect *>(e); }
int32_t clap_vst3_parameter_count(ClapVST3Effect e) { auto p = static_cast<Effect *>(e); return p && p->controller ? p->controller->getParameterCount() : 0; }
int32_t clap_vst3_parameter_info(ClapVST3Effect e, int32_t index, uint32_t *id, uint16_t *title, double *value, int32_t *steps) {
    auto p = static_cast<Effect *>(e); ParameterInfo info{};
    if (!p || !p->controller || p->controller->getParameterInfo(index, info) != kResultOk || (info.flags & ParameterInfo::kIsReadOnly) || (info.flags & ParameterInfo::kIsHidden)) return 0;
    *id = info.id; memcpy(title, info.title, sizeof(info.title)); *value = p->controller->getParamNormalized(info.id); *steps = info.stepCount; return 1;
}
int32_t clap_vst3_prepare(ClapVST3Effect effect, double rate) {
    auto e = static_cast<Effect *>(effect); if (!e || e->active || e->component->getBusCount(kAudio, kInput) < 1 || e->component->getBusCount(kAudio, kOutput) < 1) return 0;
    std::vector<SpeakerArrangement> inputs(e->component->getBusCount(kAudio, kInput), SpeakerArr::kEmpty), outputs(e->component->getBusCount(kAudio, kOutput), SpeakerArr::kEmpty);
    inputs[0] = outputs[0] = SpeakerArr::kStereo;
    if (e->processor->setBusArrangements(inputs.data(), static_cast<int32>(inputs.size()), outputs.data(), static_cast<int32>(outputs.size())) != kResultOk) return 0;
    for (int direction : {kInput, kOutput}) for (int i = 1; i < e->component->getBusCount(kAudio, direction); ++i) e->component->activateBus(kAudio, direction, i, false);
    if (e->processor->canProcessSampleSize(kSample32) != kResultOk) return 0;
    if (e->component->activateBus(kAudio, kInput, 0, true) != kResultOk || e->component->activateBus(kAudio, kOutput, 0, true) != kResultOk) return 0;
    for (int direction : {kInput, kOutput}) for (int i = 0; i < e->component->getBusCount(kEvent, direction); ++i) e->component->activateBus(kEvent, direction, i, false);
    ProcessSetup setup{}; setup.processMode = kOffline; setup.symbolicSampleSize = kSample32; setup.maxSamplesPerBlock = 512; setup.sampleRate = rate;
    if (e->processor->setupProcessing(setup) != kResultOk || e->component->setActive(true) != kResultOk) return 0;
    e->active = true; if (e->processor->setProcessing(true) != kResultOk) return 0;
    e->processing = true; e->rate = rate; return 1;
}
uint32_t clap_vst3_latency(ClapVST3Effect e) { return static_cast<Effect *>(e)->processor->getLatencySamples(); }
uint32_t clap_vst3_tail(ClapVST3Effect e) { return static_cast<Effect *>(e)->processor->getTailSamples(); }
int32_t clap_vst3_process(ClapVST3Effect effect, float *left, float *right, int32_t frames, const uint32_t *ids, const double *values, int32_t count) {
    auto e = static_cast<Effect *>(effect); if (!e || !e->processing || frames < 1 || frames > 512) return 0;
    float *input[2] = {left, right}; float outputL[512]{}, outputR[512]{}; float *output[2] = {outputL, outputR};
    std::vector<AudioBusBuffers> in(e->component->getBusCount(kAudio, kInput)), out(e->component->getBusCount(kAudio, kOutput));
    for (auto &b : in) { b.numChannels = 0; b.silenceFlags = ~uint64(0); b.channelBuffers32 = nullptr; }
    for (auto &b : out) { b.numChannels = 0; b.silenceFlags = ~uint64(0); b.channelBuffers32 = nullptr; }
    in[0].numChannels = out[0].numChannels = 2; in[0].channelBuffers32 = input; out[0].channelBuffers32 = output; in[0].silenceFlags = out[0].silenceFlags = 0;
    Changes changes; changes.queues.reserve(count); for (int i = 0; i < count; ++i) changes.queues.emplace_back(ids[i], values[i]);
    ProcessContext context{}; context.sampleRate = e->rate; context.projectTimeSamples = e->position; context.tempo = 120; context.timeSigNumerator = context.timeSigDenominator = 4;
    context.state = ProcessContext::kPlaying | ProcessContext::kTempoValid | ProcessContext::kTimeSigValid;
    ProcessData data; data.processMode = kOffline; data.symbolicSampleSize = kSample32; data.numSamples = frames; data.numInputs = static_cast<int32>(in.size()); data.numOutputs = static_cast<int32>(out.size());
    data.inputs = in.data(); data.outputs = out.data(); data.inputParameterChanges = &changes; data.processContext = &context;
    if (e->processor->process(data) != kResultOk) return 0;
    memcpy(left, outputL, frames * sizeof(float)); memcpy(right, outputR, frames * sizeof(float)); e->position += frames; return 1;
}
}
