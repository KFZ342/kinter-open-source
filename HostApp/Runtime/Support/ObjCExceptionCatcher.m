#import "ObjCExceptionCatcher.h"

@implementation ObjCExceptionCatcher

+ (NSString *)catchException:(void (NS_NOESCAPE ^)(void))block {
    @try {
        block();
        return nil;
    }
    @catch (NSException *e) {
        return [NSString stringWithFormat:@"%@: %@", e.name, e.reason ?: @""];
    }
}

@end
