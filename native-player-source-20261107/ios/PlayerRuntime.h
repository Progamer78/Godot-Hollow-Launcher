#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
// This boundary belongs to the Godot 4 adapter. A future Godot 3 adapter must
// provide an isolated implementation, not link another engine into this image.
@interface PlayerRuntime : NSObject
+ (nullable UIViewController *)startPack:(NSString *)packPath
                               savePath:(NSString *)savePath
                               renderer:(NSString *)renderer
                                  error:(NSError * _Nullable * _Nullable)error;
+ (void)setKey:(NSString *)key pressed:(BOOL)pressed;
+ (void)releaseKeys;
@end
NS_ASSUME_NONNULL_END
