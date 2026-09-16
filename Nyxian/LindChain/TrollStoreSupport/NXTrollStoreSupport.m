#import "NXTrollStoreSupport.h"
#import <spawn.h>

#ifndef POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE
#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
#endif
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t * __restrict, uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t * __restrict, uid_t);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t * __restrict, uid_t);
#import <sys/stat.h>
#import <sys/wait.h>
#import <string.h>
#import <unistd.h>
#import <stdint.h>
#import <stdio.h>
#import <fcntl.h>

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)registerApplicationDictionary:(NSDictionary *)dictionary;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleIdentifier;
@end

@interface MCMContainer : NSObject
+ (id)containerWithIdentifier:(id)identifier createIfNecessary:(BOOL)create existed:(BOOL *)existed error:(NSError **)error;
@property (nonatomic, readonly) NSURL *url;
@end

static BOOL NXIsMachOFile(NSString *path)
{
    FILE *file = fopen(path.fileSystemRepresentation, "rb");
    if (!file) {
        return NO;
    }

    uint32_t magic = 0;
    fread(&magic, sizeof(uint32_t), 1, file);
    fclose(file);

    return magic == 0xfeedfacf || magic == 0xcffaedfe || magic == 0xcafebabe || magic == 0xbebafeca;
}

static NSString * const NXTrollStoreSupportErrorDomain = @"org.emexlabs.nyxian.trollstoresupport";
static NSString * const NXTrollStoreMarkerName = @"_TrollStore";

static int NXFdIsValid(int fd)
{
    return fcntl(fd, F_GETFD) != -1 || errno != EBADF;
}

static NSString *NXGetNSStringFromFile(int fd)
{
    NSMutableString *string = [NSMutableString new];
    ssize_t numRead;
    char c;
    if (!NXFdIsValid(fd)) return @"";
    while ((numRead = read(fd, &c, sizeof(c)))) {
        [string appendString:[NSString stringWithFormat:@"%c", c]];
        if (c == '\n') break;
    }
    return string.copy;
}

static int NXSpawnRoot(NSString *path, NSArray *args, NSString **stdOut, NSString **stdErr)
{
    NSMutableArray *argsM = args.mutableCopy ?: [NSMutableArray new];
    [argsM insertObject:path atIndex:0];

    NSUInteger argCount = argsM.count;
    char **argsC = (char **)malloc((argCount + 1) * sizeof(char *));
    for (NSUInteger i = 0; i < argCount; i++) {
        argsC[i] = strdup([[argsM objectAtIndex:i] UTF8String]);
    }
    argsC[argCount] = NULL;

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);

    posix_spawn_file_actions_t action;
    posix_spawn_file_actions_init(&action);

    int outErr[2];
    if (stdErr) {
        pipe(outErr);
        posix_spawn_file_actions_adddup2(&action, outErr[1], STDERR_FILENO);
        posix_spawn_file_actions_addclose(&action, outErr[0]);
    }

    int out[2];
    if (stdOut) {
        pipe(out);
        posix_spawn_file_actions_adddup2(&action, out[1], STDOUT_FILENO);
        posix_spawn_file_actions_addclose(&action, out[0]);
    }

    pid_t taskPid;
    int status = -200;
    int spawnError = posix_spawn(&taskPid, [path UTF8String], &action, &attr, (char *const *)argsC, NULL);
    posix_spawnattr_destroy(&attr);
    posix_spawn_file_actions_destroy(&action);

    if (stdErr) {
        close(outErr[1]);
    }
    if (stdOut) {
        close(out[1]);
    }

    for (NSUInteger i = 0; i < argCount; i++) {
        free(argsC[i]);
    }
    free(argsC);

    if (spawnError != 0) {
        return spawnError;
    }

    __block volatile BOOL isRunning = YES;
    NSMutableString *outString = [NSMutableString new];
    NSMutableString *errString = [NSMutableString new];
    dispatch_semaphore_t sema = 0;
    dispatch_queue_t logQueue;
    if (stdOut || stdErr) {
        logQueue = dispatch_queue_create("org.emexlabs.nyxian.TrollStore.LogCollector", NULL);
        sema = dispatch_semaphore_create(0);

        int outPipe = out[0];
        int outErrPipe = outErr[0];
        __block BOOL outEnabled = (BOOL)stdOut;
        __block BOOL errEnabled = (BOOL)stdErr;
        dispatch_async(logQueue, ^{
            while (isRunning) {
                @autoreleasepool {
                    if (outEnabled) {
                        [outString appendString:NXGetNSStringFromFile(outPipe)];
                    }
                    if (errEnabled) {
                        [errString appendString:NXGetNSStringFromFile(outErrPipe)];
                    }
                }
            }
            dispatch_semaphore_signal(sema);
        });
    }

    do {
        if (waitpid(taskPid, &status, 0) != -1) {
            isRunning = NO;
        }
    } while (isRunning);

    if (stdOut || stdErr) {
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        if (stdOut) {
            *stdOut = outString.copy;
        }
        if (stdErr) {
            *stdErr = errString.copy;
        }
    }

    return WEXITSTATUS(status);
}

@implementation NXTrollStoreSupport

+ (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description
{
    return [NSError errorWithDomain:NXTrollStoreSupportErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: description ?: @"Unknown TrollStore support error"}];
}

+ (nullable NSString *)projectEntitlementsPathForProjectPath:(NSString *)projectPath error:(NSError **)error
{
    NSArray<NSString *> *candidates = @[
        [projectPath stringByAppendingPathComponent:@"Config/Entitlements.plist"],
        [projectPath stringByAppendingPathComponent:@"Config/entitlements.plist"],
        [projectPath stringByAppendingPathComponent:@"Entitlements.plist"],
        [projectPath stringByAppendingPathComponent:@"entitlements.plist"]
    ];

    NSFileManager *fileManager = NSFileManager.defaultManager;
    for (NSString *candidate in candidates) {
        BOOL isDirectory = NO;
        if ([fileManager fileExistsAtPath:candidate isDirectory:&isDirectory] && !isDirectory) {
            return candidate;
        }
    }

    NSString *fallback = [NSTemporaryDirectory() stringByAppendingPathComponent:@"DefaultEntitlements.plist"];
    NSDictionary *defaultEnts = @{
        @"get-task-allow": @YES
    };
    if ([defaultEnts writeToFile:fallback atomically:YES]) {
        return fallback;
    }

    if (error) {
        *error = [self errorWithCode:1 description:@"Missing project Config/Entitlements.plist or Config/entitlements.plist"];
    }
    return nil;
}

+ (NSString *)preferredLdidPath
{
    NSString *bundled = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"ldid"];
    if ([NSFileManager.defaultManager fileExistsAtPath:bundled]) {
        return bundled;
    }
    NSArray<NSString *> *candidates = @[
        [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/ldid"],
        @"/var/jb/usr/bin/ldid",
        @"/usr/local/bin/ldid",
        @"/usr/bin/ldid"
    ];
    for (NSString *candidate in candidates) {
        if ([NSFileManager.defaultManager fileExistsAtPath:candidate]) {
            return candidate;
        }
    }
    return bundled;
}

+ (NSString *)helperPath
{
    NSString *bundled = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"trollstorehelper"];
    if ([NSFileManager.defaultManager fileExistsAtPath:bundled]) {
        return bundled;
    }
    NSArray<NSString *> *systemPaths = @[
        @"/Applications/TrollStore.app/trollstorehelper",
        @"/var/jb/Applications/TrollStore.app/trollstorehelper"
    ];
    for (NSString *p in systemPaths) {
        if ([NSFileManager.defaultManager fileExistsAtPath:p]) {
            return p;
        }
    }
    Class appContainerClass = NSClassFromString(@"MCMAppContainer");
    if (appContainerClass) {
        MCMContainer *tsContainer = [appContainerClass containerWithIdentifier:@"com.opa334.TrollStore" createIfNecessary:NO existed:nil error:nil];
        if (tsContainer && tsContainer.url.path) {
            NSString *tsHelper = [tsContainer.url.path stringByAppendingPathComponent:@"TrollStore.app/trollstorehelper"];
            if ([NSFileManager.defaultManager fileExistsAtPath:tsHelper]) {
                return tsHelper;
            }
        }
    }
    return bundled;
}

+ (BOOL)ldidExistsAtPath:(NSString *)path
{
    BOOL isDirectory = NO;
    return [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] && !isDirectory;
}

+ (nullable NSString *)ensureLdidInstalledWithError:(NSError **)error
{
    NSString *preferredPath = [self preferredLdidPath];
    if ([self ldidExistsAtPath:preferredPath]) {
        chmod(preferredPath.fileSystemRepresentation, 0755);
        return preferredPath;
    }

    if (error) {
        *error = [self errorWithCode:2 description:@"Missing bundled ldid in app bundle"];
    }
    return nil;
}

+ (NSString *)stringFromFileDescriptor:(int)fd
{
    NSMutableData *data = [NSMutableData data];
    char buffer[4096];
    ssize_t bytesRead = 0;
    while ((bytesRead = read(fd, buffer, sizeof(buffer))) > 0) {
        [data appendBytes:buffer length:(NSUInteger)bytesRead];
    }
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return string ?: @"";
}

+ (nullable NSDictionary *)infoDictionaryForAppBundleAtPath:(NSString *)bundlePath error:(NSError **)error
{
    NSDictionary *infoDictionary = [NSDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"Info.plist"]];
    if (![infoDictionary isKindOfClass:NSDictionary.class]) {
        if (error) {
            *error = [self errorWithCode:6 description:@"The app bundle is missing Info.plist"];
        }
        return nil;
    }

    NSString *bundleIdentifier = infoDictionary[@"CFBundleIdentifier"];
    NSString *executableName = infoDictionary[@"CFBundleExecutable"];
    if (![bundleIdentifier isKindOfClass:NSString.class] || bundleIdentifier.length == 0 ||
        ![executableName isKindOfClass:NSString.class] || executableName.length == 0) {
        if (error) {
            *error = [self errorWithCode:6 description:@"The app bundle Info.plist is missing required values"];
        }
        return nil;
    }
    return infoDictionary;
}

+ (BOOL)copyItemReplacingExistingPath:(NSString *)sourcePath toPath:(NSString *)destinationPath error:(NSError **)error
{
    [NSFileManager.defaultManager removeItemAtPath:destinationPath error:nil];
    return [NSFileManager.defaultManager copyItemAtPath:sourcePath toPath:destinationPath error:error];
}

+ (BOOL)fixPermissionsForAppBundleAtPath:(NSString *)bundlePath error:(NSError **)error
{
    NSDirectoryEnumerator<NSString *> *enumerator = [NSFileManager.defaultManager enumeratorAtPath:bundlePath];
    for (NSString *relativePath in enumerator) {
        NSString *path = [bundlePath stringByAppendingPathComponent:relativePath];
        BOOL isDirectory = NO;
        [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory];
        NSDictionary *attributes = @{NSFilePosixPermissions: @(isDirectory || NXIsMachOFile(path) ? 0755 : 0644)};
        if (![NSFileManager.defaultManager setAttributes:attributes ofItemAtPath:path error:error]) {
            return NO;
        }
        chown(path.fileSystemRepresentation, 33, 33);
    }
    chown(bundlePath.fileSystemRepresentation, 33, 33);
    return [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @(0755)} ofItemAtPath:bundlePath error:error];
}

+ (BOOL)installAppBundleAtPath:(NSString *)bundlePath error:(NSError **)error
{
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:bundlePath isDirectory:&isDirectory] || !isDirectory) {
        if (error) {
            *error = [self errorWithCode:7 description:@"Missing app bundle for TrollStore installation"];
        }
        return NO;
    }

    NSDictionary *infoDictionary = [self infoDictionaryForAppBundleAtPath:bundlePath error:error];
    if (!infoDictionary) {
        return NO;
    }
    NSString *bundleIdentifier = infoDictionary[@"CFBundleIdentifier"];

    Class appContainerClass = NSClassFromString(@"MCMAppContainer");
    Class appDataContainerClass = NSClassFromString(@"MCMAppDataContainer");
    if (!appContainerClass || !appDataContainerClass) {
        if (error) {
            *error = [self errorWithCode:8 description:@"MobileContainerManager classes are unavailable"];
        }
        return NO;
    }

    NSError *containerError = nil;
    MCMContainer *appContainer = [appContainerClass containerWithIdentifier:bundleIdentifier createIfNecessary:YES existed:nil error:&containerError];
    if (!appContainer || containerError) {
        if (error) {
            *error = containerError ?: [self errorWithCode:8 description:@"Failed to create app container"];
        }
        return NO;
    }

    MCMContainer *dataContainer = [appDataContainerClass containerWithIdentifier:bundleIdentifier createIfNecessary:YES existed:nil error:nil];
    NSString *dataContainerPath = dataContainer.url.path;
    if (dataContainerPath.length) {
        [NSFileManager.defaultManager createDirectoryAtPath:[dataContainerPath stringByAppendingPathComponent:@"tmp"] withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSString *markerPath = [appContainer.url.path stringByAppendingPathComponent:NXTrollStoreMarkerName];
    if (![NSFileManager.defaultManager fileExistsAtPath:markerPath]) {
        [NSData.data writeToFile:markerPath atomically:NO];
    }

    NSString *destinationPath = [appContainer.url.path stringByAppendingPathComponent:bundlePath.lastPathComponent];
    NSError *copyError = nil;
    if (![self copyItemReplacingExistingPath:bundlePath toPath:destinationPath error:&copyError]) {
        if (error) {
            *error = copyError ?: [self errorWithCode:9 description:@"Failed to copy app bundle into app container"];
        }
        return NO;
    }

    NSError *permissionError = nil;
    if (![self fixPermissionsForAppBundleAtPath:destinationPath error:&permissionError]) {
        if (error) {
            *error = permissionError ?: [self errorWithCode:10 description:@"Failed to fix app bundle permissions"];
        }
        return NO;
    }

    NSMutableDictionary *registration = [NSMutableDictionary dictionary];
    registration[@"ApplicationType"] = @"System";
    registration[@"CFBundleIdentifier"] = bundleIdentifier;
    registration[@"CodeInfoIdentifier"] = bundleIdentifier;
    registration[@"CompatibilityState"] = @0;
    registration[@"IsContainerized"] = @YES;
    if (dataContainerPath.length) {
        registration[@"Container"] = dataContainerPath;
        registration[@"EnvironmentVariables"] = @{
            @"CFFIXED_USER_HOME": dataContainerPath,
            @"HOME": dataContainerPath,
            @"TMPDIR": [dataContainerPath stringByAppendingPathComponent:@"tmp"]
        };
    }
    registration[@"IsDeletable"] = @YES;
    registration[@"Path"] = destinationPath;
    registration[@"SignerOrganization"] = @"Apple Inc.";
    registration[@"SignatureVersion"] = @132352;
    registration[@"SignerIdentity"] = @"Apple iPhone OS Application Signing";
    registration[@"IsAdHocSigned"] = @YES;
    registration[@"LSInstallType"] = @1;
    registration[@"HasMIDBasedSINF"] = @0;
    registration[@"MissingSINF"] = @0;
    registration[@"FamilyID"] = @0;
    registration[@"IsOnDemandInstallCapable"] = @0;

    @try {
        if (![[LSApplicationWorkspace defaultWorkspace] registerApplicationDictionary:registration]) {
            if (error) {
                *error = [self errorWithCode:11 description:@"Failed to register installed app"];
            }
            return NO;
        }
    } @catch (NSException *exception) {
        if (error) {
            *error = [self errorWithCode:11 description:[NSString stringWithFormat:@"Register app failed: %@", exception.reason ?: exception.name]];
        }
        return NO;
    }

    return YES;
}

+ (BOOL)signExecutableAtPath:(NSString *)executablePath entitlementsPath:(NSString *)entitlementsPath error:(NSError **)error
{
    NSString *ldidPath = [self ensureLdidInstalledWithError:error];
    if (!ldidPath) {
        return NO;
    }

    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:executablePath isDirectory:&isDirectory] || isDirectory) {
        if (error) {
            *error = [self errorWithCode:14 description:@"Missing executable to sign"];
        }
        return NO;
    }
    if (![NSFileManager.defaultManager fileExistsAtPath:entitlementsPath isDirectory:&isDirectory] || isDirectory) {
        if (error) {
            *error = [self errorWithCode:15 description:@"Missing entitlements plist to sign executable"];
        }
        return NO;
    }

    NSString *signArg = [@"-S" stringByAppendingString:entitlementsPath];
    NSString *stderrOutput = nil;
    int ret = NXSpawnRoot(ldidPath, @[signArg, executablePath], nil, &stderrOutput);
    if (ret != 0) {
        if (error) {
            NSString *message = stderrOutput.length ? stderrOutput : [NSString stringWithFormat:@"ldid returned %d", ret];
            *error = [self errorWithCode:5 description:message];
        }
        return NO;
    }

    return YES;
}

+ (BOOL)installIpaAtPath:(NSString *)ipaPath error:(NSError **)error
{
    NSString *helperPath = [self helperPath];
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:helperPath isDirectory:&isDirectory] || isDirectory) {
        if (error) {
            *error = [self errorWithCode:13 description:@"Missing trollstorehelper in app bundle"];
        }
        return NO;
    }
    chmod(helperPath.fileSystemRepresentation, 0755);

    NSString *stderrOutput = nil;
    int ret = NXSpawnRoot(helperPath, @[@"install", @"force", ipaPath], nil, &stderrOutput);
    if (ret != 0) {
        if (error) {
            NSString *message = stderrOutput.length ? stderrOutput : [NSString stringWithFormat:@"trollstorehelper returned %d", ret];
            *error = [self errorWithCode:5 description:message];
        }
        return NO;
    }

    return YES;
}

+ (BOOL)openApplicationWithBundleIdentifier:(NSString *)bundleIdentifier error:(NSError **)error
{
    if (bundleIdentifier.length == 0) {
        if (error) {
            *error = [self errorWithCode:9 description:@"Missing bundle identifier"];
        }
        return NO;
    }

    for (NSInteger attempt = 0; attempt < 10; attempt++) {
        if ([[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:bundleIdentifier]) {
            return YES;
        }
        [NSThread sleepForTimeInterval:0.5];
    }

    if (error) {
        *error = [self errorWithCode:10 description:@"Installed app but failed to open it"];
    }
    return NO;
}

+ (NSString *)preferredInstallNameToolPath
{
    NSArray<NSString *> *candidates = @[
        [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"install_name_tool"],
        @"/var/jb/usr/bin/install_name_tool",
        @"/usr/bin/install_name_tool",
        @"/var/jb/usr/bin/llvm-install-name-tool-16"
    ];
    for (NSString *path in candidates) {
        BOOL isDir = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDir] && !isDir) {
            return path;
        }
    }
    return @"/var/jb/usr/bin/install_name_tool";
}

+ (BOOL)patchSwiftUICoreIfNeededAtPath:(NSString *)executablePath deploymentTarget:(nullable NSString *)deploymentTarget error:(NSError **)error
{
    BOOL isDir = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:executablePath isDirectory:&isDir] || isDir) {
        return YES;
    }

    NSMutableData *data = [NSMutableData dataWithContentsOfFile:executablePath options:NSDataReadingMappedIfSafe error:error];
    if (!data || data.length < 32) {
        return YES;
    }

    uint8_t *bytes = (uint8_t *)data.mutableBytes;
    uint32_t magic = *(uint32_t *)bytes;
    if (magic != 0xfeedfacf) { // Only 64-bit ARM Mach-O binaries
        return YES;
    }

    uint32_t ncmds = *(uint32_t *)(bytes + 16);
    uint32_t offset = 32;

    uint32_t cf_off = 0;
    uint32_t cf_size = 0;

    int swiftuicore_ord = 0;
    int swiftui_ord = 0;
    int dylib_count = 0;

    for (uint32_t i = 0; i < ncmds && offset + 8 <= data.length; i++) {
        uint32_t cmd = *(uint32_t *)(bytes + offset);
        uint32_t cmdsize = *(uint32_t *)(bytes + offset + 4);
        if (cmdsize < 8 || offset + cmdsize > data.length) {
            break;
        }

        if (cmd == 0x80000034) { // LC_DYLD_CHAINED_FIXUPS
            cf_off = *(uint32_t *)(bytes + offset + 8);
            cf_size = *(uint32_t *)(bytes + offset + 12);
        } else if (cmd == 0x0c || cmd == 0x80000018) { // LC_LOAD_DYLIB or LC_LOAD_WEAK_DYLIB
            dylib_count++;
            uint32_t name_off = *(uint32_t *)(bytes + offset + 8);
            if (name_off < cmdsize && offset + name_off < data.length) {
                const char *name = (const char *)(bytes + offset + name_off);
                if (strstr(name, "SwiftUICore.framework")) {
                    swiftuicore_ord = dylib_count;
                    if (cmd == 0x0c) {
                        *(uint32_t *)(bytes + offset) = 0x80000018; // Convert to LC_LOAD_WEAK_DYLIB
                        NSLog(@"[NXTrollStoreSupport] Converted SwiftUICore (ord %d) to LC_LOAD_WEAK_DYLIB", swiftuicore_ord);
                    }
                } else if (strstr(name, "SwiftUI.framework")) {
                    swiftui_ord = dylib_count;
                }
            }
        }
        offset += cmdsize;
    }

    // Remap chained fixups imports pointing to SwiftUICore over to SwiftUI
    if (cf_off > 0 && cf_size >= 28 && cf_off + 28 <= data.length && swiftuicore_ord > 0 && swiftui_ord > 0) {
        uint32_t imports_offset = *(uint32_t *)(bytes + cf_off + 8);
        uint32_t imports_count = *(uint32_t *)(bytes + cf_off + 16);
        uint32_t imports_format = *(uint32_t *)(bytes + cf_off + 20);

        uint32_t imp_base = cf_off + imports_offset;
        int remapped = 0;

        if (imports_format == 1) { // DYLD_CHAINED_IMPORT (4 bytes per import)
            for (uint32_t i = 0; i < imports_count && imp_base + (i + 1) * 4 <= data.length; i++) {
                uint32_t *import_ptr = (uint32_t *)(bytes + imp_base + i * 4);
                uint32_t val = *import_ptr;
                uint8_t lib_ord = (uint8_t)(val & 0xFF);
                if (lib_ord == swiftuicore_ord) {
                    *import_ptr = (val & ~0xFF) | (uint32_t)swiftui_ord;
                    remapped++;
                }
            }
        } else if (imports_format == 2) { // DYLD_CHAINED_IMPORT_ADDEND (8 bytes per import)
            for (uint32_t i = 0; i < imports_count && imp_base + (i + 1) * 8 <= data.length; i++) {
                uint32_t *import_ptr = (uint32_t *)(bytes + imp_base + i * 8);
                uint32_t val = *import_ptr;
                uint8_t lib_ord = (uint8_t)(val & 0xFF);
                if (lib_ord == swiftuicore_ord) {
                    *import_ptr = (val & ~0xFF) | (uint32_t)swiftui_ord;
                    remapped++;
                }
            }
        }

        if (remapped > 0) {
            NSLog(@"[NXTrollStoreSupport] Remapped %d chained fixups from SwiftUICore to SwiftUI for universal iOS 14-18+ compatibility", remapped);
        }
    }

    // Write back modified binary directly in-place
    BOOL success = [data writeToFile:executablePath atomically:NO];
    if (success) {
        chmod(executablePath.fileSystemRepresentation, 0755);
        NSLog(@"[NXTrollStoreSupport] Successfully saved universal binary to %@", executablePath);
    } else {
        NSLog(@"[NXTrollStoreSupport] ERROR: Failed to write universal binary to %@", executablePath);
    }
    return success;
}

+ (void)postBuildNotificationWithAppName:(NSString *)appName success:(BOOL)success message:(nullable NSString *)customMessage
{
    NSString *title = success ? [NSString stringWithFormat:@"Nyxian: %@", appName] : [NSString stringWithFormat:@"Nyxian: ❌ %@", appName];
    NSString *body = customMessage ?: (success ? @"Build succeeded & installed via TrollStore!" : @"Build failed with compiler errors.");

    NSURL *url = [NSURL URLWithString:@"https://ntfy.sh/nyxian_abdo_xs"];
    if (!url) return;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    [request setValue:title forHTTPHeaderField:@"Title"];
    [request setValue:@"default" forHTTPHeaderField:@"Priority"];
    [request setValue:@"hammer_and_wrench,rocket" forHTTPHeaderField:@"Tags"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:nil];
    [task resume];
}

@end
