#include "ExecutableCore.h"
#include <algorithm>
#include <cstring>
#include <set>
namespace PlayerExecutable {
bool candidates(const std::vector<uint8_t> &b, std::vector<std::array<uint8_t, 32>> &keys, std::string &error) {
    keys.clear(); error = "Unsupported executable layout. Select the original Godot 3 or 4 Windows x64 EXE and its PCK together.";
    auto fits = [&](uint64_t at, uint64_t n) { return at <= b.size() && n <= b.size() - at; };
    auto u16 = [&](size_t at) { return uint16_t(b[at]) | uint16_t(b[at+1]) << 8; };
    auto u32 = [&](size_t at) { return uint32_t(b[at]) | uint32_t(b[at+1]) << 8 | uint32_t(b[at+2]) << 16 | uint32_t(b[at+3]) << 24; };
    if (!fits(0, 64) || b.size() > 128*1024*1024 || b[0] != 'M' || b[1] != 'Z') return false;
    uint64_t nt = u32(60);
    if (!fits(nt, 24) || u32(nt) != 0x4550 || u16(nt+4) != 0x8664) return false;
    uint64_t optional = nt+24, count = u16(nt+6), optional_size = u16(nt+20);
    if (count == 0 || count > 96 || optional_size < 112 || !fits(optional, optional_size + count*40) || u16(optional) != 0x20b) return false;
    struct Section { std::string name; uint32_t rva, size, offset; };
    std::vector<Section> sections;
    for (size_t i=0;i<count;i++) {
        size_t at=optional+optional_size+i*40;
        char name[9]={}; std::memcpy(name,b.data()+at,8);
        Section s={name,u32(at+12),u32(at+16),u32(at+20)};
        if (!fits(s.offset,s.size) || uint64_t(s.rva)+s.size > UINT32_MAX) return false;
        sections.push_back(s);
    }
    auto find = [&](const char *name) -> const Section* { for (auto &s:sections) if(s.name==name) return &s; return nullptr; };
    auto *text=find(".text"), *pdata=find(".pdata");
    if (!text || !pdata || pdata->size/12 > 1000000) return false;
    std::set<uint32_t> anchors;
    for (auto &s:sections) {
        if (s.name!=".rdata") continue;
        auto begin=b.begin()+s.offset, end=begin+s.size;
        for (const char *needle : {"GDScript::load_byte_code", "PackedSourcePCK::try_open_pack"}) {
            size_t length=std::strlen(needle);
            for (auto it=std::search(begin,end,needle,needle+length);it!=end;it=std::search(it+1,end,needle,needle+length)) {
                anchors.insert(s.rva+uint32_t(it-begin)); if(anchors.size()>32) return false;
            }
        }
    }
    if (anchors.empty()) return false;
    std::vector<std::pair<uint32_t,uint32_t>> functions;
    for (size_t p=pdata->offset;p+12<=uint64_t(pdata->offset)+pdata->size;p+=12) {
        uint32_t start=u32(p),end=u32(p+4);
        if (start>=text->rva && end>start && uint64_t(end)<=uint64_t(text->rva)+text->size) functions.push_back({start,end});
    }
    std::sort(functions.begin(),functions.end());
    std::set<std::pair<uint32_t,uint32_t>> loaders;
    auto lea = [&](size_t at) { return (b[at]==0x48 || b[at]==0x4c) && b[at+1]==0x8d && (b[at+2]&0xc7)==5; };
    auto target = [&](size_t at) { return int64_t(text->rva)+int64_t(at-text->offset)+7+int32_t(u32(at+3)); };
    for (size_t at=text->offset;at+7<=uint64_t(text->offset)+text->size;at++) {
        if (!lea(at) || !anchors.count(uint32_t(target(at)))) continue;
        uint32_t rva=text->rva+uint32_t(at-text->offset);
        auto f=std::upper_bound(functions.begin(),functions.end(),std::make_pair(rva,UINT32_MAX));
        if(f==functions.begin()) continue; --f;
        if(rva<f->second && f->second-f->first<=65536) loaders.insert(*f);
        if(loaders.size()>64) return false;
    }
    std::set<std::array<uint8_t,32>> unique;
    for (auto &f:loaders) for (size_t at=text->offset+f.first-text->rva;at+8<=uint64_t(text->offset)+f.second-text->rva;at++) {
        int64_t rva;
        if(lea(at)) rva=target(at);
        else if((b[at]==0x66 || b[at]==0xf3) && b[at+1]==0x0f && (b[at+2]==0x6f || b[at+2]==0x10) && (b[at+3]&0xc7)==5)
            rva=int64_t(text->rva)+int64_t(at-text->offset)+8+int32_t(u32(at+4));
        else continue;
        for(auto &section:sections) {
            if(section.name!=".data" && section.name!=".rdata") continue;
            for(int delta : {0,-16,16}) {
                int64_t start=rva+delta;
                if(start<section.rva || uint64_t(start)+32>uint64_t(section.rva)+section.size) continue;
                std::array<uint8_t,32> key; std::memcpy(key.data(),b.data()+section.offset+(start-section.rva),32);
                unique.insert(key); if(unique.size()>256) return false;
            }
        }
    }
    keys.assign(unique.begin(),unique.end());
    if(keys.empty()) return false;
    error.clear(); return true;
}
}
