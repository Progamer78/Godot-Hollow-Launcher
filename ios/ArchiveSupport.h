#pragma once
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface GPArchive : NSObject
+ (nullable NSArray<NSDictionary *> *)entriesAtPath:(NSString *)path error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(entries(at:));
+ (BOOL)extractPath:(NSString *)path entry:(NSString *)entry destination:(NSString *)destination limit:(uint64_t)limit position:(uint64_t)position index:(uint64_t)index error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(extract(_:entry:destination:limit:position:index:));
+ (BOOL)createPath:(NSString *)path files:(NSArray<NSString *> *)files names:(NSArray<NSString *> *)names error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(create(_:files:names:));
@end
NS_ASSUME_NONNULL_END
