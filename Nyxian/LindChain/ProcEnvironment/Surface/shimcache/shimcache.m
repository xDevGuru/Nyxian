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

#include <LindChain/ProcEnvironment/Surface/shimcache/shimcache.h>
#include <LindChain/ProcEnvironment/Surface/fs/fs.h>
#include <LindChain/ProcEnvironment/Surface/fs/mount.h>
#include <stdio.h>
#include <os/lock.h>
#import <Foundation/Foundation.h>
#import <MobileDevelopmentKit/MobileDevelopmentKit.h>
#import <LindChain/IDEFoundation/NXBootstrap.h>
#import <LindChain/IDEFoundation/NXProject.h>
#import <LindChain/ProcEnvironment/Utils/klog.h>
#import <LindChain/ProcEnvironment/LiveContainer/LCUtils.h>

static os_unfair_lock g_shimcache_lock = OS_UNFAIR_LOCK_INIT;

static shimcache_segment_t *g_shimcache_seg;
static int g_shimcache_seg_cnt = 0;

kern_return_t ksurface_shimcache_append_code(CCFileType fileType,
                                             const char *code)
{
    os_unfair_lock_lock(&g_shimcache_lock);
    
    /* we need a slot */
    int index = g_shimcache_seg_cnt++;
    void *newptr = realloc(g_shimcache_seg, sizeof(shimcache_segment_t) * g_shimcache_seg_cnt);
    if(newptr)
    {
        g_shimcache_seg = newptr;
    }
    else
    {
        g_shimcache_seg_cnt--;
        os_unfair_lock_unlock(&g_shimcache_lock);
        return KERN_FAILURE;
    }
    
    /* now we fill the slot */
    g_shimcache_seg[index].code = strdup(code);
    if(g_shimcache_seg[index].code == NULL)
    {
        g_shimcache_seg_cnt--;
        os_unfair_lock_unlock(&g_shimcache_lock);
        return KERN_FAILURE;
    }
    g_shimcache_seg[index].fileType = fileType;
    
    os_unfair_lock_unlock(&g_shimcache_lock);
    return KERN_SUCCESS;
}

kern_return_t ksurface_shimcache_build(void)
{
    os_unfair_lock_lock(&g_shimcache_lock);
    NSURL *shimcacheBuildURL = [[NSURL fileURLWithPath:NSHomeDirectory()] URLByAppendingPathComponent:@"/Library/Shimcache.builder"];
    [[NSFileManager defaultManager] removeItemAtURL:shimcacheBuildURL error:nil];
    if(![[NSFileManager defaultManager] createDirectoryAtURL:shimcacheBuildURL withIntermediateDirectories:YES attributes:@{} error:nil])
    {
        klog_log("shimcache:build", "couldn't create build directory");
        os_unfair_lock_unlock(&g_shimcache_lock);
        return KERN_FAILURE;
    }
    
    /* write out code files */
    NSMutableArray<NSString*> *codeFiles = [NSMutableArray array];
    for(int index = 0; index < g_shimcache_seg_cnt; index++)
    {
        NSString *fileExtension;
        switch(g_shimcache_seg[index].fileType)
        {
            case kCCFileTypeC:
                fileExtension = @"c";
                break;
            case kCCFileTypeCXX:
                fileExtension = @"cpp";
                break;
            case kCCFileTypeObjC:
                fileExtension = @"m";
                break;
            case kCCFileTypeObjCXX:
                fileExtension = @"mm";
                break;
            default:
                klog_log("shimcache:build", "file type %d is not supported yet", g_shimcache_seg[index].fileType);
                goto just_continue;
        }
        
        {
            NSURL *codeFileURL = [shimcacheBuildURL URLByAppendingPathComponent:[[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:fileExtension]];
            NSString *codeString = @(g_shimcache_seg[index].code);
            if(codeFileURL && codeString)
            {
                [codeString writeToURL:codeFileURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
                [codeFiles addObject:codeFileURL.path];
            }
        }
        
    just_continue:
        continue;
    }
    
    if([codeFiles count] <= 0)
    {
        os_unfair_lock_unlock(&g_shimcache_lock);
        return KERN_SUCCESS;
    }
    
    /* now we need to compile them together to one shimcache */
    NSString *shimCacheDylib = [[shimcacheBuildURL URLByAppendingPathComponent:@"shimcache.dylib"] path];
    
    NSMutableArray<NSString*> *driverFlags = [NSMutableArray array];
    [driverFlags addObjectsFromArray:[NXProjectConfig sdkCompilerFlags]];
    [driverFlags addObject:@"-target"];
    [driverFlags addObject:@"apple-arm64-ios17.0"];
    [driverFlags addObjectsFromArray:codeFiles];
    [driverFlags addObject:@"-o"];
    [driverFlags addObject:shimCacheDylib];
    [driverFlags addObject:@"-shared"];
    [driverFlags addObject:@"-ObjC"];
    [driverFlags addObject:@"-fobjc"];
    [driverFlags addObject:@"-Wl,-undefined,dynamic_lookup"];
    
    MDKDriver *driver = [MDKDriver driverWithArguments:driverFlags withType:kCCDriverTypeClang];
    if(driver == NULL)
    {
        os_unfair_lock_unlock(&g_shimcache_lock);
        return KERN_FAILURE;
    }
    
    NSArray<MDKJob*> *jobs = [driver generateJobs];
    for(MDKJob *job in jobs)
    {
        NSArray<MDKDiagnostic*> *outDiagnostic = nil;
        NSString *mainSourceFile = nil;
        if(![job executeJobWithOutDiagnostics:&outDiagnostic withOutMainSource:&mainSourceFile])
        {
            klog_log("shimcache:build:error", "%@:", mainSourceFile);
            for(MDKDiagnostic *diagnostic in outDiagnostic)
            {
                klog_log("shimcache:build:error", "    %@", diagnostic.message);
            }
            os_unfair_lock_unlock(&g_shimcache_lock);
            return KERN_FAILURE;
        }
    }
    
    /* sign it */
    if(![LCUtils signMachOWithoutPatchAtURL:[NSURL fileURLWithPath:shimCacheDylib]])
    {
        klog_log("shimcache:build", "couldn't sign shimcache");
        os_unfair_lock_unlock(&g_shimcache_lock);
        return KERN_SUCCESS;
    }
    
    /* mount shim to correct place */
    ksurface_fs_mount2(kFSMountAttrRead, "/dev/nounlink", [shimCacheDylib UTF8String]);
    ksurface_fs_mount2(kFSMountAttrRead, [shimCacheDylib UTF8String], [[[[[NXBootstrap shared] rootURL] URLByAppendingPathComponent:@"/mntfs/bootfs/shimcache.dylib"] path] UTF8String]);
    
    os_unfair_lock_unlock(&g_shimcache_lock);
    return KERN_SUCCESS;
}
