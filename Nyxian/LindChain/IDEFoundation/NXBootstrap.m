/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab

 This file is part of Nyxian.

 Nyxian is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Nyxian is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with Nyxian. If not, see <https://www.gnu.org/licenses/>.
*/

#import <LindChain/IDEFoundation/NXBootstrap.h>
#import <LindChain/Utils/Zip.h>
#import <LindChain/Downloader/fdownload.h>
#import <LindChain/ProcEnvironment/Surface/extra/relax.h>
#import <MobileDevelopmentKit/MDKThreadPool.h>
#import <UI/XCodeButton.h>
#import <Nyxian-Swift.h>

BOOL PEURLIsContainedIn(NSURL *candidate,
                        NSURL *root)
{
    NSURL *candidateSatnderized = candidate.URLByResolvingSymlinksInPath.URLByStandardizingPath;
    NSURL *rootSatnderized = root.URLByResolvingSymlinksInPath.URLByStandardizingPath;
    
    NSString *candidatePath = candidateSatnderized.path;
    NSString *rootPath = rootSatnderized.path;
    
    if(![rootPath hasSuffix:@"/"])
    {
        rootPath = [rootPath stringByAppendingString:@"/"];
    }
    NSString *canditateSlash = [candidatePath hasSuffix:@"/"] ? candidatePath : [candidatePath stringByAppendingString:@"/"];
    return [canditateSlash isEqualToString:rootPath] || [canditateSlash hasPrefix:rootPath];
}

@interface NXBootstrap ()

@property (readwrite) UInt64 version;
@property (readwrite) BOOL hasFailed;

@end

@implementation NXBootstrap {
    NSURL *_rootURL;
    dispatch_once_t _gatherRootURLOnce;
}

- (instancetype)init
{
    self = [super init];
    return self;
}

+ (instancetype)shared
{
    static NXBootstrap *bootstrapSingleton = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bootstrapSingleton = [[NXBootstrap alloc] init];
    });
    return bootstrapSingleton;
}

- (NSURL*)rootURL
{
    dispatch_once(&_gatherRootURLOnce, ^{
        NSString *home = NSHomeDirectory();
        NSString *docs = [home stringByAppendingPathComponent:@"Documents"];
        if(![docs hasPrefix:@"/private"] && [[NSFileManager defaultManager] fileExistsAtPath:[@"/private" stringByAppendingPathComponent:docs]])
        {
            docs = [@"/private" stringByAppendingPathComponent:docs];
        }
        _rootURL = [NSURL fileURLWithPath:docs];
    });
    return _rootURL;
}

- (NSURL*)sdkURL
{
    return [self.rootURL URLByAppendingPathComponent:@"SDK/iPhoneOS26.5.sdk"];
}

- (NSURL*)includeURL
{
    return [self.rootURL URLByAppendingPathComponent:@"Include"];
}

- (NSURL*)projectsURL
{
    return [self.rootURL URLByAppendingPathComponent:@"Projects"];
}

- (NSURL*)cacheURL
{
    return [self.rootURL URLByAppendingPathComponent:@"Cache"];
}

- (NSURL*)bootstrapPlistURL
{
    return [self.rootURL URLByAppendingPathComponent:@"bootstrap.plist"];
}

- (NSURL*)swiftURL
{
    return [self.rootURL URLByAppendingPathComponent:@"swift"];
}

- (NSURL*)swiftModuleCacheURL
{
    return [self.rootURL URLByAppendingPathComponent:@"ModuleCache"];
}

- (NSURL*)rootfsURL
{
    NSURL *rootfsURL = [self.rootURL URLByAppendingPathComponent:@"rootfs"];
    [[NSFileManager defaultManager] createDirectoryAtURL:rootfsURL withIntermediateDirectories:NO attributes:nil error:nil];
    return rootfsURL;
}

- (UInt64)version
{
    NSDictionary *bootstrapPlist = [NSDictionary dictionaryWithContentsOfURL:self.bootstrapPlistURL];
    if(bootstrapPlist == nil)
    {
        /* plist doesn't exist or is malformed? */
        return 0;
    }
    
    NSNumber *versionNumber = bootstrapPlist[@"BootstrapVersion"];
    if(![versionNumber isKindOfClass:NSNumber.class])
    {
        /* illegal object */
        return 0;
    }
    
    return [versionNumber unsignedLongValue];
}

- (void)setVersion:(UInt64)version
{
    [XCButton updateProgressWithValue:NXBOOTSTRAP_CSTEP * version];
    [@{ @"BootstrapVersion":[NSNumber numberWithUnsignedLong:version] } writeToURL:self.bootstrapPlistURL error:nil];
}

- (BOOL)isInstalled
{
    return self.version > 0;
}

- (void)bootstrap
{
    NSLog(@"checking upon nyxian bootstrap :3");
    
    MDKPthreadDispatch(^{
        NSError *error = nil;
        
        goto skip_error_report;
        
    report_error:
        {
            NSLog(@"bootstrapping sadly failed :c (%@)", error.localizedDescription);
            self.hasFailed = YES;
            [NotificationServer NotifyUserWithLevel:NotifLevelError notification:[NSString stringWithFormat:@"Bootstrapping failed: %@", error.localizedDescription] delay:1.0];
            return;
        }
        
    skip_error_report:
        self.hasFailed = NO;
        
        /*
         * checking weither we have to create the
         * bootstraps root path.
         */
        if(![[NSFileManager defaultManager] fileExistsAtPath:self.rootURL.path])
        {
            [[NSFileManager defaultManager] createDirectoryAtURL:self.rootURL withIntermediateDirectories:YES attributes:nil error:&error];
            if(error != nil)
            {
                abort();
            }
        }
        
        NSLog(@"install status: %d", self.isInstalled);
        NSLog(@"version: %llu", self.version);
        
        if(!self.isInstalled || self.version != NXBOOTSTRAP_NEWEST_VERSION)
        {
            /*
             * need to clear the entire path if its not installed
             * otherwise garbage might be in the container.
             * we also have to clear it in case a newer version
             * of the bootstrap is installed.
             */
            if(!self.isInstalled || self.version > NXBOOTSTRAP_NEWEST_VERSION)
            {
                NSLog(@"bootstrap might be too new or not installed, clearing");
                [self clearURL:self.rootURL];
            }
            
            /*
             * now installing or upgrading the bootstrap, this is the part
             * that has to work although nobody is going to use Nyxian today
             * lol.
             */
            if(self.version < 9)
            {
                /*
                 * creating bootstrap base structure
                 * all base folders n such, you name it.
                 */
                NSLog(@"bootstrapping directory structure");
                
                [[NSFileManager defaultManager] createDirectoryAtURL:self.projectsURL withIntermediateDirectories:YES attributes:nil error:&error];
                
                if(![[NSFileManager defaultManager] createDirectoryAtURL:self.cacheURL withIntermediateDirectories:YES attributes:nil error:&error])
                {
                    goto report_error;
                }
                
                self.version = 9;
            }
            
            if(self.version < 10)
            {
                /*
                 * this step is for the rt static library
                 * which is needed for availability checks
                 * using @available in objc for example.
                 */
                NSLog(@"bootstrapping libraries");
                [[NSFileManager defaultManager] removeItemAtURL:[self.rootURL URLByAppendingPathComponent:@"lib"] error:nil];
                
                if(!unzipArchiveAtPath([NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:@"Shared/lib.zip"].path, self.rootURL.path))
                {
                    error = [NSError errorWithDomain:@"" code:0 userInfo:@{ NSLocalizedDescriptionKey: @"extracting \"lib.zip\" failed" }];
                    goto report_error;
                }
                
                self.version = 10;
            }
            
            if(self.version < 15)
            {
                /*
                 * there was a DOS vulnerability in a prior
                 * version of Nyxian where a zip could of caused
                 * DOS in project import functionality. so we
                 * have to fixup paths in case they were affected.
                 * as patching the DOS entry it self does not
                 * prevent it to still cause DOS as damage
                 * might already happened.
                 */
                NSURL *tmpUrl = [NSURL fileURLWithPath:NSTemporaryDirectory()];
                NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:tmpUrl includingPropertiesForKeys:nil options:0 errorHandler:nil];
                if(enumerator == nil)
                {
                    error = [NSError errorWithDomain:@"" code:0 userInfo:@{ NSLocalizedDescriptionKey: @"failed to create enumerator" }];
                    goto report_error;
                }
                
                if(![[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @(0755) } ofItemAtPath:tmpUrl.path error:&error])
                {
                    goto report_error;
                }
                
                for(NSURL *fileURL in enumerator)
                {
                    BOOL isDirectory = NO;
                    if(![[NSFileManager defaultManager] fileExistsAtPath:fileURL.path isDirectory:&isDirectory])
                    {
                        continue;
                    }
                    
                    if(![[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: isDirectory ? @(0755) : @(0644)} ofItemAtPath:fileURL.path error:&error])
                    {
                        goto report_error;
                    }
                }
                
                self.version = 15;
            }
            
            if(self.version < 23)
            {
                /*
                 * this is necessary so simd and normal
                 * c code work perfectly.
                 */
                NSLog(@"bootstrapping clang include and swift resources");
                [[NSFileManager defaultManager] removeItemAtURL:self.includeURL error:nil];
                [[NSFileManager defaultManager] removeItemAtURL:self.swiftURL error:nil];
                
                if(!unzipArchiveAtPath([NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:@"Shared/include.zip"].path, [self.rootURL URLByAppendingPathComponent:@"Include"].path))
                {
                    error = [NSError errorWithDomain:@"" code:0 userInfo:@{ NSLocalizedDescriptionKey: @"extracting \"include.zip\" failed" }];
                    goto report_error;
                }
                
                /*
                 * this is necessary so swift works
                 */
                if(!unzipArchiveAtPath([NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:@"Shared/swift.zip"].path, self.rootURL.path))
                {
                    error = [NSError errorWithDomain:@"" code:0 userInfo:@{ NSLocalizedDescriptionKey: @"extracting \"swift.zip\" failed" }];
                    goto report_error;
                }
                
                self.version = 23;
            }
            
            if(self.version < 27)
            {
                /*
                 * the SDK is very important to use iOS API which
                 * is very cool.
                 */
                NSLog(@"bootstrapping SDK");
                [[NSFileManager defaultManager] removeItemAtURL:[self.rootURL URLByAppendingPathComponent:@"SDK"] error:nil];
                [[NSFileManager defaultManager] removeItemAtURL:self.swiftModuleCacheURL error:nil];    /* clearing module cache */
                
                NSString *sdkZipTemp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"sdk.zip"];
                [[NSFileManager defaultManager] removeItemAtPath:sdkZipTemp error:nil];
                
                NSURL *bundledSDK = [NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:@"Shared/iPhoneOS26.5.sdk.zip"];
                NSString *sdkSourceZip = nil;
                if([[NSFileManager defaultManager] fileExistsAtPath:bundledSDK.path])
                {
                    sdkSourceZip = bundledSDK.path;
                }
                else
                {
                    if(!fdownload(@"https://nyxian.app/bootstrap/iPhoneOS26.5.sdk.zip", sdkZipTemp))
                    {
                        error = [NSError errorWithDomain:@"" code:0 userInfo:@{ NSLocalizedDescriptionKey: @"downloading \"https://nyxian.app/bootstrap/iPhoneOS26.5.sdk.zip\" failed" }];
                        goto report_error;
                    }
                    sdkSourceZip = sdkZipTemp;
                }
                
                NSString *sdkDestDir = [self.rootURL URLByAppendingPathComponent:@"SDK"].path;
                [[NSFileManager defaultManager] createDirectoryAtPath:sdkDestDir withIntermediateDirectories:YES attributes:nil error:nil];
                
                if(!unzipArchiveAtPath(sdkSourceZip, sdkDestDir))
                {
                    error = [NSError errorWithDomain:@"" code:0 userInfo:@{ NSLocalizedDescriptionKey: @"extracting \"sdk.zip\" failed" }];
                    goto report_error;
                }
                
                if([sdkSourceZip isEqualToString:sdkZipTemp])
                {
                    [[NSFileManager defaultManager] removeItemAtPath:sdkZipTemp error:nil];
                }
                
                NSArray<NSURL*> *symlinkSDKs = @[
                    [self.rootURL URLByAppendingPathComponent:@"/SDK/iPhoneOS26.2.sdk"],
                    [self.rootURL URLByAppendingPathComponent:@"/SDK/iPhoneOS26.4.1.sdk"],
                    [self.rootURL URLByAppendingPathComponent:@"/SDK/iPhoneOS26.4.sdk"]
                ];
                
                for(NSURL *symlink in symlinkSDKs)
                {
                    [[NSFileManager defaultManager] removeItemAtPath:symlink.path error:nil];
                    if(![[NSFileManager defaultManager] createSymbolicLinkAtPath:symlink.path withDestinationPath:self.sdkURL.lastPathComponent error:&error])
                    {
                        goto report_error;
                    }
                }
                
                self.version = 27;
            }
            
            if(self.version < 28)
            {
                NSLog(@"bootstrapping rootca folder");
                
                NSURL *rootCADir = [self.rootURL URLByAppendingPathComponent:@"RootCAs"];
                [[NSFileManager defaultManager] createDirectoryAtURL:rootCADir withIntermediateDirectories:YES attributes:nil error:nil];
                
                NSString *rootCADestPath = [rootCADir URLByAppendingPathComponent:@"org.emexlabs.rootca.v1.pub.nxt2c"].path;
                NSURL *bundledRootCA = [NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:@"Shared/org.emexlabs.rootca.v1.pub.nxt2c"];
                
                BOOL installedRootCA = NO;
                if([[NSFileManager defaultManager] fileExistsAtPath:bundledRootCA.path])
                {
                    [[NSFileManager defaultManager] removeItemAtPath:rootCADestPath error:nil];
                    if([[NSFileManager defaultManager] copyItemAtPath:bundledRootCA.path toPath:rootCADestPath error:nil])
                    {
                        installedRootCA = YES;
                        NSLog(@"[NXBootstrap] installed rootca from bundle");
                    }
                }
                
                if(!installedRootCA)
                {
                    [[NSFileManager defaultManager] removeItemAtPath:rootCADestPath error:nil];
                    if(!fdownload(@"https://nyxian.app/bootstrap/org.emexlabs.rootca.v1.pub.nxt2c", rootCADestPath))
                    {
                        error = [NSError errorWithDomain:@"" code:0 userInfo:@{ NSLocalizedDescriptionKey: @"downloading \"https://nyxian.app/bootstrap/org.emexlabs.rootca.v1.pub.nxt2c\" failed" }];
                        goto report_error;
                    }
                    installedRootCA = YES;
                    NSLog(@"[NXBootstrap] downloaded and installed rootca");
                }
                
                ksurface_keychain_update();
                
                self.version = 28;
            }
        }
        
        NSLog(@"done");
    });
}

- (NSString*)relativeToBootstrapWithAbsolutePath:(NSString*)path
{
    NSURL *absolutURL = [NSURL fileURLWithPath:path];
    if(![absolutURL.path hasPrefix:[self.rootURL.path stringByAppendingString:@"/"]] &&
       ![absolutURL.path isEqualToString:self.rootURL.path])
    {
        return nil;
    }
    return [absolutURL.path stringByReplacingOccurrencesOfString:[self.rootURL.path stringByAppendingString:@"/"] withString:@""];
}

- (void)clearURL:(NSURL*)url
{
    NSArray<NSURL*> *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:0 error:nil];
    if(entries == nil)
    {
        return;
    }
    
    for(NSURL *entry in entries)
    {
        if(!(url == self.rootURL && ([entry.lastPathComponent isEqualToString:@"Projects"] ||
                                     [entry.lastPathComponent isEqualToString:@"rootfs"] ||
                                     [entry.lastPathComponent isEqualToString:@"mntfs"] ||
                                     [entry.lastPathComponent isEqualToString:@"klog.txt"])))
        {
            [[NSFileManager defaultManager] removeItemAtURL:entry error:nil];
        }
    }
}

- (void)waitTillDone
{
    if(self.version == NXBOOTSTRAP_NEWEST_VERSION)
    {
        return;
    }
    
    [XCButton switchImageWithSystemName:@"archivebox.fill" animated:YES];
    [XCButton updateProgressWithValue:0.1];
    
    while(self.version != NXBOOTSTRAP_NEWEST_VERSION && !self.hasFailed)
    {
        usleep(100000); // 100ms sleep prevents 100% CPU lockup and watchdog crash
    }
    
    [XCButton switchImageWithSystemName:@"hammer.fill" animated:YES];
}

- (BOOL)isNewest
{
    return self.version == NXBOOTSTRAP_NEWEST_VERSION;
}

@end
