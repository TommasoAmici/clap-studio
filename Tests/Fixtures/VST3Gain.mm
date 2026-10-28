// A deterministic VST3 fixture: stereo gain plus hidden state, with no SDK implementation dependencies.
#include "pluginterfaces/base/ipluginbase.h"
#include "pluginterfaces/base/ibstream.h"
#include "pluginterfaces/vst/ivstcomponent.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "pluginterfaces/vst/ivstparameterchanges.h"
#include "pluginterfaces/vst/vstspeaker.h"
#include <cstring>
#include <algorithm>
#include "pluginterfaces/gui/iplugview.h"
#import <AppKit/AppKit.h>
using namespace Steinberg;
using namespace Steinberg::Vst;
static const char classID[16] = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16};
struct Gain : IComponent, IAudioProcessor, IEditController {
    uint32 refs = 0;
    double gain = 1, hidden = 0;
    IComponentHandler *handler = nullptr;
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
    tresult PLUGIN_API setState(IBStream* s) override {
        uint64 header = 0; double state[2]; int32 n;
        if (s->read(&header,sizeof(header),&n) != kResultOk || header != 0x434C4150 || s->read(state,sizeof(state),&n) != kResultOk) return kResultFalse;
        gain = state[0]; hidden = state[1]; return kResultOk;
    }
    tresult PLUGIN_API getState(IBStream* s) override {
        // Reserve the header before writing, as real preset serializers often do.
        double state[2] = {gain, hidden}; uint64 header = 0x434C4150;
        if (s->seek(sizeof(header),IBStream::kIBSeekSet,nullptr) != kResultOk || s->write(state,sizeof(state),nullptr) != kResultOk) return kResultFalse;
        if (s->seek(0,IBStream::kIBSeekSet,nullptr) != kResultOk) return kResultFalse;
        return s->write(&header,sizeof(header),nullptr);
    }
    tresult PLUGIN_API setComponentState(IBStream* s) override { return setState(s); }
    tresult PLUGIN_API setBusArrangements(SpeakerArrangement* in, int32 ni, SpeakerArrangement* out, int32 no) override { return ni == 1 && no == 1 && in[0] == SpeakerArr::kStereo && out[0] == SpeakerArr::kStereo ? kResultOk : kResultFalse; }
    tresult PLUGIN_API getBusArrangement(BusDirection, int32, SpeakerArrangement& a) override { a = SpeakerArr::kStereo; return kResultOk; }
    tresult PLUGIN_API canProcessSampleSize(int32 s) override { return s == kSample32 ? kResultOk : kResultFalse; }
    uint32 PLUGIN_API getLatencySamples() override { return 0; }
    tresult PLUGIN_API setupProcessing(ProcessSetup& setup) override {
#ifdef CLAP_REALTIME_ONLY
        if (setup.processMode != kRealtime) return kResultFalse;
#endif
        return kResultOk;
    }
    tresult PLUGIN_API setProcessing(TBool) override { return kResultOk; }
    uint32 PLUGIN_API getTailSamples() override { return 0; }
    tresult PLUGIN_API process(ProcessData& d) override {
#ifdef CLAP_REALTIME_ONLY
        if (d.processMode != kRealtime) return kResultFalse;
#endif
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
    tresult PLUGIN_API setComponentHandler(IComponentHandler* h) override { handler = h; return kResultOk; }
    IPlugView* PLUGIN_API createView(FIDString) override;
};

#ifndef CLAP_NO_EDITOR
@interface GainControl : NSObject { @public Gain *gain; }
- (void)change:(NSSlider *)slider;
@end
@implementation GainControl
- (void)change:(NSSlider *)slider {
    gain->gain = slider.doubleValue;
    if (gain->handler) { gain->handler->beginEdit(1); gain->handler->performEdit(1,gain->gain); gain->handler->endEdit(1); }
}
@end
struct View : IPlugView {
    uint32 refs = 1; Gain *gain; IPlugFrame *frame = nullptr; NSView *content = nil; GainControl *control = nil;
    ViewRect size {0,0,640,280};
    explicit View(Gain *gain) : gain(gain) {}
    ~View() { removed(); }
    uint32 PLUGIN_API addRef() override { return ++refs; }
    uint32 PLUGIN_API release() override { auto r = --refs; if (!r) delete this; return r; }
    tresult PLUGIN_API queryInterface(const TUID iid, void **o) override { *o = nullptr; if (!memcmp(iid,INLINE_UID_OF(IPlugView),16) || !memcmp(iid,INLINE_UID_OF(FUnknown),16)) { *o = this; addRef(); return kResultOk; } return kNoInterface; }
    tresult PLUGIN_API isPlatformTypeSupported(FIDString type) override { return !strcmp(type,kPlatformTypeNSView) ? kResultOk : kResultFalse; }
    tresult PLUGIN_API attached(void *parent, FIDString type) override {
        if (isPlatformTypeSupported(type) != kResultOk) return kResultFalse;
        gain->gain = 0.25; gain->hidden = 0.125;
        content = [[NSView alloc] initWithFrame:NSMakeRect(0,0,640,280)];
        content.wantsLayer = YES; content.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
        NSTextField *title = [NSTextField labelWithString:@"Clap Test Gain — native VST3 editor"];
        title.font = [NSFont systemFontOfSize:22 weight:NSFontWeightSemibold]; title.frame = NSMakeRect(24,210,592,32); [content addSubview:title];
        NSTextField *subtitle = [NSTextField labelWithString:@"Gain and a hidden preset setting are saved together."];
        subtitle.frame = NSMakeRect(24,168,592,26); [content addSubview:subtitle];
        NSSlider *slider = [NSSlider sliderWithValue:gain->gain minValue:0 maxValue:1 target:nil action:nil];
        control = [[GainControl alloc] init]; control->gain = gain; slider.target = control; slider.action = @selector(change:);
        slider.frame = NSMakeRect(24,104,592,32); slider.autoresizingMask = NSViewWidthSizable; [content addSubview:slider];
        NSTextField *hint = [NSTextField labelWithString:@"Play a sample while editing; settings are kept for Bounce."];
        hint.frame = NSMakeRect(24,40,592,26); [content addSubview:hint];
        [(NSView *)parent addSubview:content];
        if (frame) frame->resizeView(this,&size);
        return kResultOk;
    }
    tresult PLUGIN_API removed() override { if (content) { [content removeFromSuperview]; [content release]; content = nil; } [control release]; control = nil; return kResultOk; }
    tresult PLUGIN_API onWheel(float) override { return kResultFalse; }
    tresult PLUGIN_API onKeyDown(char16, int16, int16) override { return kResultFalse; }
    tresult PLUGIN_API onKeyUp(char16, int16, int16) override { return kResultFalse; }
    tresult PLUGIN_API getSize(ViewRect *r) override { *r = size; return kResultOk; }
    tresult PLUGIN_API onSize(ViewRect *r) override { size = *r; if (content) content.frame = NSMakeRect(0,0,r->getWidth(),r->getHeight()); return kResultOk; }
    tresult PLUGIN_API onFocus(TBool) override { return kResultOk; }
    tresult PLUGIN_API setFrame(IPlugFrame *f) override { frame = f; return kResultOk; }
    tresult PLUGIN_API canResize() override { return kResultOk; }
    tresult PLUGIN_API checkSizeConstraint(ViewRect *r) override { r->right = r->left + std::max(640,r->getWidth()); r->bottom = r->top + std::max(280,r->getHeight()); return kResultOk; }
};
#endif
IPlugView *Gain::createView(FIDString) {
#ifdef CLAP_NO_EDITOR
    return nullptr;
#else
    return new View(this);
#endif
}
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
