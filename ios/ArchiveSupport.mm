// Include the public memory definitions explicitly; do not depend on vector's
// transitive libc++ module imports for allocator destruction templates.
#include <memory>
#import "ArchiveSupport.h"
#include "ArchiveCore.inc"
#include "ExecutableCore.inc"
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonDigest.h>
static void archive_error(NSError **error, const std::string &message) {
    if (error) *error = [NSError errorWithDomain:@"GodotPlayer.Archive" code:1 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:message.c_str()] ?: @"Archive error"}];
}
@implementation GPArchive
+ (NSArray<NSData *> *)candidateKeys:(NSString *)path error:(NSError **)error {
    FILE *file=std::fopen(path.fileSystemRepresentation,"rb");
    if(!file) { archive_error(error,"Cannot read original executable."); return nil; }
    if(fseeko(file,0,SEEK_END)!=0) { std::fclose(file); archive_error(error,"Cannot seek executable."); return nil; }
    off_t length=ftello(file); rewind(file);
    if(length<64 || length>128*1024*1024) { std::fclose(file); archive_error(error,"EXE inspection supports files up to 128 MB."); return nil; }
    std::vector<uint8_t> bytes(size_t(length),0); bool read=std::fread(bytes.data(),1,bytes.size(),file)==bytes.size(); std::fclose(file);
    std::vector<std::array<uint8_t,32>> keys; std::string message;
    if(!read || !PlayerExecutable::candidates(bytes,keys,message)) { archive_error(error,read?message:"Truncated executable."); return nil; }
    NSMutableArray *result=[NSMutableArray arrayWithCapacity:keys.size()];
    for(auto &key:keys) [result addObject:[NSData dataWithBytes:key.data() length:32]];
    return result;
}
+ (NSData *)decryptScript:(NSData *)bytes key:(NSData *)key error:(NSError **)error {
    auto fail=[&]() -> NSData* { archive_error(error,"The original executable does not match these encrypted scripts, or its encryption format is unsupported."); return nil; };
    if(key.length!=32 || bytes.length<48 || bytes.length>16*1024*1024) return fail();
    const uint8_t *p=(const uint8_t*)bytes.bytes;
    if(std::memcmp(p,"GDEC",4)!=0 || p[4]!=1 || p[5] || p[6] || p[7]) return fail();
    uint64_t length=0; for(int i=0;i<8;i++) length|=uint64_t(p[24+i])<<(8*i);
    if(length<8 || length>16*1024*1024 || ((length+15)&~uint64_t(15))!=bytes.length-32) return fail();
    NSMutableData *plain=[NSMutableData dataWithLength:bytes.length-32]; size_t moved=0;
    if(CCCrypt(kCCDecrypt,kCCAlgorithmAES,kCCOptionECBMode,key.bytes,32,nullptr,p+32,bytes.length-32,plain.mutableBytes,plain.length,&moved)!=kCCSuccess || moved<length) return fail();
    plain.length=NSUInteger(length); unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(plain.bytes,CC_LONG(plain.length),digest);
    if(std::memcmp(digest,p+8,16)!=0 || std::memcmp(plain.bytes,"GDSC",4)!=0) return fail();
    return plain;
}
+ (NSData *)decryptGodot4:(NSData *)bytes key:(NSData *)key magic:(BOOL)magic error:(NSError **)error {
    auto fail=[&]() -> NSData* { archive_error(error,"Godot 4 data could not be decrypted and verified with this original runtime key."); return nil; };
    const NSUInteger prefix=magic?4:0, header=prefix+40;
    if(key.length!=32 || bytes.length<header || bytes.length>64*1024*1024+64) return fail();
    const uint8_t *p=(const uint8_t*)bytes.bytes;
    if(magic && std::memcmp(p,"GDEC",4)!=0) return fail();
    uint64_t length=0;for(int i=0;i<8;i++) length|=uint64_t(p[prefix+16+i])<<(8*i);
    if(length>64*1024*1024 || ((length+15)&~uint64_t(15))!=bytes.length-header) return fail();
    CCCryptorRef cryptor=nullptr;
    if(CCCryptorCreateWithMode(kCCDecrypt,kCCModeCFB,kCCAlgorithmAES,ccNoPadding,p+prefix+24,key.bytes,32,nullptr,0,0,0,&cryptor)!=kCCSuccess) return fail();
    NSMutableData *plain=[NSMutableData dataWithLength:bytes.length-header+16];size_t moved=0,tail=0;
    CCCryptorStatus status=CCCryptorUpdate(cryptor,p+header,bytes.length-header,plain.mutableBytes,plain.length,&moved);
    if(status==kCCSuccess) status=CCCryptorFinal(cryptor,(uint8_t*)plain.mutableBytes+moved,plain.length-moved,&tail);
    CCCryptorRelease(cryptor);
    if(status!=kCCSuccess || moved+tail<length) return fail();
    plain.length=NSUInteger(length);unsigned char digest[CC_MD5_DIGEST_LENGTH];CC_MD5(plain.bytes,CC_LONG(plain.length),digest);
    if(std::memcmp(digest,p+prefix,16)!=0) return fail();
    return plain;
}
+ (NSArray<NSDictionary *> *)entriesAtPath:(NSString *)path error:(NSError **)error {
    std::vector<PlayerArchive::Entry> entries; std::string message;
    if (!PlayerArchive::list(path.fileSystemRepresentation, entries, message)) { archive_error(error, message); return nil; }
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:entries.size()];
    for (const auto &entry : entries) {
        NSString *name = [[NSString alloc] initWithBytes:entry.name.data() length:entry.name.size() encoding:NSUTF8StringEncoding];
        if (!name) { archive_error(error, "ZIP paths must use UTF-8."); return nil; }
        [result addObject:@{@"name":name, @"size":@(entry.size), @"directory":@(entry.directory), @"position":@(entry.position), @"index":@(entry.index)}];
    }
    return result;
}
+ (BOOL)extractPath:(NSString *)path entry:(NSString *)entry destination:(NSString *)destination limit:(uint64_t)limit position:(uint64_t)position index:(uint64_t)index error:(NSError **)error {
    std::string message;
    if (!PlayerArchive::extract(path.fileSystemRepresentation, entry.UTF8String, destination.fileSystemRepresentation, limit, message, position, index)) { archive_error(error, message); return NO; }
    return YES;
}
+ (BOOL)createPath:(NSString *)path files:(NSArray<NSString *> *)files names:(NSArray<NSString *> *)names error:(NSError **)error {
    std::vector<std::string> paths, entries; std::string message;
    for (NSString *file in files) paths.push_back(file.fileSystemRepresentation);
    for (NSString *name in names) entries.push_back(name.UTF8String);
    if (!PlayerArchive::create(path.fileSystemRepresentation, paths, entries, message)) { archive_error(error, message); return NO; }
    return YES;
}
@end
