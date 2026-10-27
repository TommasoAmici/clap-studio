#pragma once
#include "pluginterfaces/vst/ivstmessage.h"
#include "pluginterfaces/vst/ivstattributes.h"
#include <atomic>
#include <map>
#include <string>
#include <vector>
#include <cstring>
namespace ClapHost {
using namespace Steinberg;
using namespace Steinberg::Vst;
#define MESSAGE_UNKNOWN(TYPE) \
    std::atomic<uint32> refs{1}; \
    uint32 PLUGIN_API addRef() override { return ++refs; } \
    uint32 PLUGIN_API release() override { auto n = --refs; if (!n) delete this; return n; } \
    tresult PLUGIN_API queryInterface(const TUID iid, void **obj) override { \
        if (!obj) return kInvalidArgument; *obj = nullptr; \
        if (!memcmp(iid, INLINE_UID_OF(TYPE), 16) || !memcmp(iid, INLINE_UID_OF(FUnknown), 16)) { *obj = static_cast<TYPE *>(this); addRef(); return kResultOk; } return kNoInterface; }
struct Attributes : IAttributeList {
    MESSAGE_UNKNOWN(IAttributeList)
    std::map<std::string, int64> ints;
    std::map<std::string, double> floats;
    std::map<std::string, std::u16string> strings;
    std::map<std::string, std::vector<uint8>> binaries;
    tresult PLUGIN_API setInt(AttrID id, int64 value) override { if (!id) return kInvalidArgument; ints[id] = value; return kResultOk; }
    tresult PLUGIN_API getInt(AttrID id, int64 &value) override { if (!id || !ints.count(id)) return kResultFalse; value = ints[id]; return kResultOk; }
    tresult PLUGIN_API setFloat(AttrID id, double value) override { if (!id) return kInvalidArgument; floats[id] = value; return kResultOk; }
    tresult PLUGIN_API getFloat(AttrID id, double &value) override { if (!id || !floats.count(id)) return kResultFalse; value = floats[id]; return kResultOk; }
    tresult PLUGIN_API setString(AttrID id, const TChar *s) override { if (!id || !s) return kInvalidArgument; strings[id] = reinterpret_cast<const char16_t *>(s); return kResultOk; }
    tresult PLUGIN_API getString(AttrID id, TChar *s, uint32 bytes) override {
        if (!id || !s || bytes < 2 || !strings.count(id)) return kResultFalse;
        auto &value = strings[id]; auto count = std::min<size_t>(value.size(), bytes / 2 - 1);
        memcpy(s, value.data(), count * 2); s[count] = 0; return kResultOk;
    }
    tresult PLUGIN_API setBinary(AttrID id, const void *data, uint32 bytes) override {
        if (!id || (!data && bytes)) return kInvalidArgument;
        auto &v = binaries[id]; v.resize(bytes); if (bytes) memcpy(v.data(), data, bytes); return kResultOk;
    }
    tresult PLUGIN_API getBinary(AttrID id, const void *&data, uint32 &bytes) override {
        if (!id || !binaries.count(id)) return kResultFalse; auto &v = binaries[id]; data = v.data(); bytes = static_cast<uint32>(v.size()); return kResultOk;
    }
};
struct Message : IMessage {
    MESSAGE_UNKNOWN(IMessage)
    std::string id; Attributes *attributes = new Attributes;
    ~Message() { attributes->release(); }
    FIDString PLUGIN_API getMessageID() override { return id.c_str(); }
    void PLUGIN_API setMessageID(FIDString value) override { id = value ? value : ""; }
    IAttributeList *PLUGIN_API getAttributes() override { return attributes; }
};
#undef MESSAGE_UNKNOWN
}
