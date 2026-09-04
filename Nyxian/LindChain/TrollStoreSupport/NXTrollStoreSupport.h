#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NXTrollStoreSupport : NSObject

+ (nullable NSString *)projectEntitlementsPathForProjectPath:(NSString *)projectPath error:(NSError **)error;
+ (BOOL)signExecutableAtPath:(NSString *)executablePath entitlementsPath:(NSString *)entitlementsPath error:(NSError **)error;
+ (BOOL)installIpaAtPath:(NSString *)ipaPath error:(NSError **)error;
+ (BOOL)installAppBundleAtPath:(NSString *)bundlePath error:(NSError **)error;
+ (BOOL)openApplicationWithBundleIdentifier:(NSString *)bundleIdentifier error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
