//
//  ObjCExceptionCatcher.h
//  Stori
//
//  Bridges Objective-C exception handling into Swift.
//  Swift's do-catch cannot catch NSException (only Swift Error),
//  so we need this ObjC helper for AVAudioEngine/AUAudioUnit operations
//  that may throw ObjC exceptions instead of Swift errors.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Executes a block and catches any Objective-C NSException.
/// Returns YES if the block executed successfully, NO if an exception was caught.
/// If an exception is caught, the error out-parameter is populated with details.
BOOL ObjCExceptionCatcherTryBlock(void (NS_NOESCAPE ^_Nonnull block)(void),
                                   NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END
