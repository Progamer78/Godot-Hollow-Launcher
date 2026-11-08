// Include the public memory definitions explicitly; do not depend on vector's
// transitive libc++ module imports for allocator destruction templates.
#include <memory>
#import "ArchiveSupport.h"
#include "ArchiveCore.inc"
static void archive_error(NSError **error, const std::string &message) {
    if (error) *error = [NSError errorWithDomain:@"GodotPlayer.Archive" code:1 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:message.c_str()] ?: @"Archive error"}];
}
@implementation GPArchive
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
