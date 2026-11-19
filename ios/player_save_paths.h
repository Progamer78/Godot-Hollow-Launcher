#pragma once
#import <Foundation/Foundation.h>

// Hollow redirects Godot's own log to player.log in the save root. Games and
// addons can still use the standard user://logs directory independently.
// Prepare it before autoload constructors, including on restored older saves.
static inline BOOL HollowPrepareSaveDirectory(NSString *path, NSError **error) {
    return [NSFileManager.defaultManager createDirectoryAtPath:[path stringByAppendingPathComponent:@"logs"]
        withIntermediateDirectories:YES attributes:nil error:error];
}
