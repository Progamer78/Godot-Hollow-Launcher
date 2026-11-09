#include "ExecutableCore.inc"
#include <fstream>
#include <iostream>
int main(int argc,char **argv) {
    if(argc<2) return 2;
    std::ifstream file(argv[1],std::ios::binary|std::ios::ate);
    if(!file || file.tellg()<0 || file.tellg()>128*1024*1024) return 2;
    std::vector<uint8_t> b(size_t(file.tellg())); file.seekg(0);
    file.read(reinterpret_cast<char*>(b.data()),b.size());
    std::vector<std::array<uint8_t,32>> keys; std::string error;
    if(!PlayerExecutable::candidates(b,keys,error)) { std::cout<<"unsupported\n"; return 1; }
    bool match=false;
    if(argc>2) {
        size_t at=std::stoull(argv[2]);
        if(at<=b.size() && b.size()-at>=32) for(auto &key:keys) if(std::memcmp(key.data(),b.data()+at,32)==0) match=true;
    }
    std::cout<<"candidates="<<keys.size()<<" expected_location_matches="<<match<<"\n";
    return argc>2 && !match ? 3:0;
}
