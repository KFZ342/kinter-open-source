#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ObjCExceptionCatcher : NSObject
/// 执行 block，捕获 ObjC 异常。返回 nil 表示成功，否则返回异常信息。
+ (nullable NSString *)catchException:(void (NS_NOESCAPE ^)(void))block;
@end

NS_ASSUME_NONNULL_END
