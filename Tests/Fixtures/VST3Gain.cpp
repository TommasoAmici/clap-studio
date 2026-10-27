// A deterministic VST3 fixture: stereo gain plus hidden state, with no SDK implementation dependencies.
#include "pluginterfaces/base/ipluginbase.h"
#include "pluginterfaces/base/ibstream.h"
#include "pluginterfaces/vst/ivstcomponent.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "pluginterfaces/vst/ivstparameterchanges.h"
#include "pluginterfaces/vst/vstspeaker.h"
#include <cstring>
using namespace Steinberg;
using namespace Steinberg::Vst;
static const char classID[16] = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16};
struct Gain : IComponent, IAudioProcessor, IEditController {
    uint32 refs = 0;
    double gain = 1, hidden = 0;
    uint32 PLUGIN_API addRef() override { return ++refs; }
    uint32 PLUGIN_API release() override { auto r = --refs; if (!r) delete this; return r; }
    tresult PLUGIN_API queryInterface(const TUID iid, void **obj) override {
        *obj = nullptr;
        if (!memcmp(iid, INLINE_UID_OF(IComponent),16) || !memcmp(iid, INLINE_UID_OF(FUnknown),16)) *obj = static_cast<IComponent*>(this);
        else if (!memcmp(iid, INLINE_UID_OF(IAudioProcessor),16)) *obj = static_cast<IAudioProcessor*>(this);
        else if (!memcmp(iid, INLINE_UID_OF(IEditController),16)) *obj = static_cast<IEditController*>(this);
        if (*obj) { addRef(); return kResultOk; } return kNoInterface;
    }
    tresult PLUGIN_API initialize(FUnknown*) override { return kResultOk; }
    tresult PLUGIN_API terminate() override { return kResultOk; }
    tresult PLUGIN_API getControllerClassId(TUID) override { return kResultFalse; }
    tresult PLUGIN_API setIoMode(IoMode) override { return kResultOk; }
    int32 PLUGIN_API getBusCount(MediaType type, BusDirection) override { return type == kAudio ? 1 : 0; }
    tresult PLUGIN_API getBusInfo(MediaType type, BusDirection dir, int32 i, BusInfo& info) override {
        if (type != kAudio || i != 0) return kInvalidArgument;
        info = {}; info.mediaType = type; info.direction = dir; info.channelCount = 2; info.busType = kMain; return kResultOk;
    }
    tresult PLUGIN_API getRoutingInfo(RoutingInfo&, RoutingInfo&) override { return kNotImplemented; }
    tresult PLUGIN_API activateBus(MediaType, BusDirection, int32, TBool) override { return kResultOk; }
    tresult PLUGIN_API setActive(TBool) override { return kResultOk; }
    tresult PLUGIN_API setState(IBStream* s) override { double state[2]; int32 n; if (s->read(state, sizeof(state), &n) != kResultOk) return kResultFalse; gain = state[0]; hidden = state[1]; return kResultOk; }
    tresult PLUGIN_API getState(IBStream* s) override { double state[2] = {gain, hidden}; return s->write(state, sizeof(state), nullptr); }
    tresult PLUGIN_API setComponentState(IBStream* s) override { return setState(s); }
    tresult PLUGIN_API setBusArrangements(SpeakerArrangement* in, int32 ni, SpeakerArrangement* out, int32 no) override { return ni == 1 && no == 1 && in[0] == SpeakerArr::kStereo && out[0] == SpeakerArr::kStereo ? kResultOk : kResultFalse; }
    tresult PLUGIN_API getBusArrangement(BusDirection, int32, SpeakerArrangement& a) override { a = SpeakerArr::kStereo; return kResultOk; }
    tresult PLUGIN_API canProcessSampleSize(int32 s) override { return s == kSample32 ? kResultOk : kResultFalse; }
    uint32 PLUGIN_API getLatencySamples() override { return 0; }
    tresult PLUGIN_API setupProcessing(ProcessSetup&) override { return kResultOk; }
    tresult PLUGIN_API setProcessing(TBool) override { return kResultOk; }
    uint32 PLUGIN_API getTailSamples() override { return 0; }
    tresult PLUGIN_API process(ProcessData& d) override {
        if (d.inputParameterChanges && d.inputParameterChanges->getParameterCount()) {
            auto q = d.inputParameterChanges->getParameterData(0); int32 offset; q->getPoint(0,offset,gain);
        }
        for (int channel = 0; channel < 2; ++channel) for (int frame = 0; frame < d.numSamples; ++frame)
            d.outputs[0].channelBuffers32[channel][frame] = d.inputs[0].channelBuffers32[channel][frame] * gain + hidden;
        return kResultOk;
    }
    int32 PLUGIN_API getParameterCount() override { return 1; }
    tresult PLUGIN_API getParameterInfo(int32 i, ParameterInfo& p) override {
        if (i) return kInvalidArgument; p = {}; p.id = 1; memcpy(p.title,u"Gain",10); p.defaultNormalizedValue = 1; p.flags = ParameterInfo::kCanAutomate; return kResultOk;
    }
    tresult PLUGIN_API getParamStringByValue(ParamID, ParamValue, String128) override { return kNotImplemented; }
    tresult PLUGIN_API getParamValueByString(ParamID, TChar*, ParamValue&) override { return kNotImplemented; }
    ParamValue PLUGIN_API normalizedParamToPlain(ParamID, ParamValue v) override { return v; }
    ParamValue PLUGIN_API plainParamToNormalized(ParamID, ParamValue v) override { return v; }
    ParamValue PLUGIN_API getParamNormalized(ParamID) override { return gain; }
    tresult PLUGIN_API setParamNormalized(ParamID, ParamValue v) override { gain = v; return kResultOk; }
    tresult PLUGIN_API setComponentHandler(IComponentHandler*) override { return kResultOk; }
    IPlugView* PLUGIN_API createView(FIDString) override { return nullptr; }
};
struct Factory : IPluginFactory {
    uint32 PLUGIN_API addRef() override { return 1; }
    uint32 PLUGIN_API release() override { return 1; }
    tresult PLUGIN_API queryInterface(const TUID iid, void** o) override { *o = nullptr; if (!memcmp(iid,INLINE_UID_OF(IPluginFactory),16) || !memcmp(iid,INLINE_UID_OF(FUnknown),16)) { *o = this; return kResultOk; } return kNoInterface; }
    tresult PLUGIN_API getFactoryInfo(PFactoryInfo* i) override { *i = {}; strcpy(i->vendor,"Clap Studio Tests"); return kResultOk; }
    int32 PLUGIN_API countClasses() override { return 1; }
    tresult PLUGIN_API getClassInfo(int32 i, PClassInfo* p) override { if (i) return kInvalidArgument; *p = {}; memcpy(p->cid,classID,16); strcpy(p->category,kVstAudioEffectClass); strcpy(p->name,"Clap Test Gain"); return kResultOk; }
    tresult PLUGIN_API createInstance(FIDString cid, FIDString iid, void** o) override {
        *o = nullptr; if (memcmp(cid,classID,16)) return kInvalidArgument; auto gain = new Gain; auto result = gain->queryInterface(iid,o); if (result != kResultOk) delete gain; return result;
    }
};
extern "C" bool bundleEntry(void*) { return true; }
extern "C" bool bundleExit() { return true; }
extern "C" IPluginFactory* GetPluginFactory() { static Factory factory; return &factory; }
