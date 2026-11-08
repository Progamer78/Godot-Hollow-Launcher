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
+ (void)setMouseEnabled:(BOOL)enabled;
+ (void)moveMouse:(CGPoint)point fromView:(UIView *)view relative:(BOOL)relative NS_SWIFT_NAME(moveMouse(_:from:relative:));
+ (CGPoint)mousePositionInView:(UIView *)view NS_SWIFT_NAME(mousePosition(in:));
+ (void)setMouseButton:(NSInteger)button pressed:(BOOL)pressed;
+ (void)scrollMouse:(NSInteger)direction;
+ (BOOL)mouseCaptured;
+ (BOOL)mouseCursorVisible;
+ (NSUInteger)mouseCursorRevision;
+ (nullable UIImage *)mouseCursorImage;
+ (CGPoint)mouseCursorHotspot;
@end
NS_ASSUME_NONNULL_END
