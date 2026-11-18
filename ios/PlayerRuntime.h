#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
// Select one engine per process. Godot 3 lives in a separate bundled image.
@interface PlayerRuntime : NSObject
+ (BOOL)configureScriptKey:(nullable NSData *)key;
+ (void)configureController:(BOOL)enabled;
+ (nullable UIViewController *)startPack:(NSString *)packPath
                               savePath:(NSString *)savePath
                               renderer:(NSString *)renderer
                            engineMajor:(NSInteger)major
                            orientation:(NSString *)orientation
                                  error:(NSError * _Nullable * _Nullable)error;
+ (double)gameAspectRatio;
+ (NSString *)toolsRequest:(NSString *)json;
+ (void)setKey:(NSString *)key pressed:(BOOL)pressed;
+ (void)releaseKeys;
+ (void)logRuntimeConfiguration;
+ (void)recordStartupStage:(NSString *)stage;
+ (NSString *)launchFailureMessage;
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
