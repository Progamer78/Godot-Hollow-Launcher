#pragma once
#import <UIKit/UIKit.h>

// Only UIKit/Foundation and fixed-size values cross engine images. No Godot
// objects, C++ types, allocators or singletons cross this ABI.
typedef struct {
    uint32_t version;
    UIViewController *(*start)(NSString *, NSString *, NSString *, NSString *, NSError **);
    void (*key)(NSString *, BOOL);
    void (*releaseInputs)(void);
    void (*mouseEnabled)(BOOL);
    void (*moveMouse)(CGPoint, UIView *, BOOL);
    CGPoint (*mousePosition)(UIView *);
    void (*mouseButton)(NSInteger, BOOL);
    void (*scroll)(NSInteger);
    BOOL (*captured)(void);
    BOOL (*cursorVisible)(void);
    double (*aspectRatio)(void);
    NSString *(*tools)(NSString *);
} GP3API;
typedef const GP3API *(*GP3GetAPIFunction)(void);
