//
//  ObjCExceptionCatcher.m
//  Stori
//
//  Bridges Objective-C exception handling into Swift.
//

#import "ObjCExceptionCatcher.h"

BOOL ObjCExceptionCatcherTryBlock(void (NS_NOESCAPE ^_Nonnull block)(void),
                                   NSError *_Nullable *_Nullable error) {
    @try {
        block();
        return YES;
    }
    @catch (NSException *exception) {
        if (error) {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            userInfo[NSLocalizedDescriptionKey] =
                [NSString stringWithFormat:@"Objective-C exception: %@ — %@",
                 exception.name, exception.reason ?: @"(no reason)"];
            if (exception.userInfo) {
                userInfo[@"ExceptionUserInfo"] = exception.userInfo;
            }
            if (exception.callStackSymbols) {
                userInfo[@"CallStackSymbols"] = exception.callStackSymbols;
            }
            *error = [NSError errorWithDomain:@"com.tellurstori.ObjCException"
                                         code:-1
                                     userInfo:userInfo];
        }
        return NO;
    }
}
