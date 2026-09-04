/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2023 - 2026 LiveContainer
 Copyright (C) 2026 emexlab

 This file is part of LiveContainer.

 LiveContainer is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 LiveContainer is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with Nyxian. If not, see <https://www.gnu.org/licenses/>.
*/

#import <LindChain/Private/FoundationPrivate.h>
#import <LindChain/ProcEnvironment/LiveContainer/LCMachOUtils.h>
#import <LindChain/ProcEnvironment/LiveContainer/utils.h>

#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <objc/runtime.h>

#include <dlfcn.h>
#include <execinfo.h>
#include <signal.h>
#include <sys/mman.h>
#include <stdlib.h>
#import <LindChain/ProcEnvironment/litehook/litehook.h>
#import <LindChain/ProcEnvironment/LiveContainer/Tweaks/Tweaks.h>
#include <mach-o/ldsyms.h>
#import <LindChain/Services/applicationmgmtd/LDEApplicationObject.h>
#import <LindChain/ProcEnvironment/Surface/surface.h>
#import <LindChain/ProcEnvironment/LiveContainer/LCBootstrap.h>
#import <malloc/malloc.h>
#import <LindChain/Utils/CFTools.h>
#import <LiveShim/LiveShimSyscall.h>
#include <ksurface_config.h>
#include <ksurface_abi.h>

int hook__NSGetExecutablePath_overwriteExecPath(char*** dyldApiInstancePtr, char* newPath, uint32_t* bufsize)
{
    assert(dyldApiInstancePtr != 0);
    char** dyldConfig = dyldApiInstancePtr[1];
    assert(dyldConfig != 0);
    
    char** mainExecutablePathPtr = 0;
    // mainExecutablePath is at 0x10 for iOS 15~18.3.2, 0x20 for iOS 18.4+
    if(dyldConfig[2] != 0 && dyldConfig[2][0] == '/')
    {
        mainExecutablePathPtr = dyldConfig + 2;
    }
    else if(dyldConfig[4] != 0 && dyldConfig[4][0] == '/')
    {
        mainExecutablePathPtr = dyldConfig + 4;
    }
    else
    {
        assert(mainExecutablePathPtr != 0);
    }

    kern_return_t ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)mainExecutablePathPtr, sizeof(mainExecutablePathPtr), false, PROT_READ | PROT_WRITE);
    if(ret != KERN_SUCCESS)
    {
        if(os_tpro_is_supported())
        {
            os_thread_self_restrict_tpro_to_rw();
        }
    }
    /* MARK: setting a copy of the path as the new pointer (required cuz objc NSString UTF8String pointers are not safe and can become stale) */
    *mainExecutablePathPtr = strdup(newPath);
    if(ret != KERN_SUCCESS)
    {
        if(os_tpro_is_supported())
        {
            os_thread_self_restrict_tpro_to_ro();
        }
    }

    return 0;
}

void LCOverwriteExecutablePath(NSString *executablePath)
{
    /* literally swapping CFBundle CFRuntime instances */
    CFBundleRef currentMainCFBundle = CFBundleGetMainBundle();
    assert(currentMainCFBundle != NULL);
    CFAllocatorRef allocator = CFGetAllocator(currentMainCFBundle); /* doesnt matter if zero */
    assert(allocator != NULL);
    CFURLRef urlRef = CFURLCreateWithFileSystemPath(allocator, (__bridge CFStringRef)[executablePath stringByDeletingLastPathComponent], kCFURLPOSIXPathStyle, true);
    assert(urlRef != NULL);
    CFBundleRef guestMainCFBundle = CFBundleCreate(allocator, urlRef);
    CFRelease(urlRef);  /* took a reference of it most probably */
    assert(guestMainCFBundle != NULL);
    
    /*
     * Swaps both bundles simply, not leaking any memory
     * as both internal states are stable by CFRuntime it
     * self we can safely exploit that angle to swap both
     * and release the original bundle. To my knowledge
     * CFBundle also doesn't cary any extra inline
     * buffers but relies on other CF types.
     */
    assert(CFSwap(currentMainCFBundle, guestMainCFBundle));
    CFRelease(guestMainCFBundle);                   /* destroys the real bundle, sounds like swizzling x3 */
    
    /*
     * dyld4 stores executable path in a different place (iOS 15.0 +)
     * https://github.com/apple-oss-distributions/dyld/blob/ce1cc2088ef390df1c48a1648075bbd51c5bbc6a/dyld/DyldAPIs.cpp#L802
     */
    int (*orig__NSGetExecutablePath)(void* dyldPtr, char* buf, uint32_t* bufsize);
    performHookDyldApi("_NSGetExecutablePath", 2, (void**)&orig__NSGetExecutablePath, hook__NSGetExecutablePath_overwriteExecPath);
    _NSGetExecutablePath((char*)[executablePath UTF8String], NULL);
    /* put the original function back */
    performHookDyldApi("_NSGetExecutablePath", 2, nil, orig__NSGetExecutablePath);
        
    /* overwriting remaining upper systems */
    NSString *procName = [executablePath lastPathComponent];
    NSProcessInfo.processInfo.processName = procName;
    *_CFGetProgname() = strdup(procName.UTF8String);
    *_CFGetProcessPath() = strdup(executablePath.UTF8String);
    Class swiftNSProcessInfo = NSClassFromString(@"_NSSwiftProcessInfo");
    if(swiftNSProcessInfo)
    {
        /* swizzle the arguments method to return the ObjC arguments */
        SEL selector = @selector(arguments);
        method_setImplementation(class_getInstanceMethod(swiftNSProcessInfo, selector), class_getMethodImplementation(NSProcessInfo.class, selector));
    }
}

static void *LCGetMachOEntryPoint(void *handle)
{
    const struct mach_header_64 *header = (const struct mach_header_64 *)getGuestAppHeader();
    const struct load_command *cmd = (const struct load_command *) ((uintptr_t)header + sizeof(struct mach_header_64));

    for(uint32_t i = 0; i < header->ncmds; i++)
    {
        if(__builtin_expect(cmd->cmd == LC_MAIN, 0))
        {
            const struct entry_point_command *ec = (const struct entry_point_command *)cmd;
            assert(ec->entryoff > 0);
            return (void *)((uintptr_t)header + ec->entryoff);
        }
        cmd = (const struct load_command *)((uintptr_t)cmd + cmd->cmdsize);
    }

    return NULL;
}

static void LCInsertLibrariesIfNeeded(void)
{
    const char *librariesToInsert = getenv("DYLD_INSERT_LIBRARIES");
    if(librariesToInsert == NULL)
    {
        return;
    }
    
    NSString *nsLibrariesToInsert = [NSString stringWithCString:librariesToInsert encoding:NSUTF8StringEncoding];
    NSArray<NSString*> *librariesToInsertArray = [nsLibrariesToInsert componentsSeparatedByString:@":"];
    
    for(NSString *library in librariesToInsertArray)
    {
        void *handle = dlopen([library UTF8String], RTLD_GLOBAL | RTLD_NOW);
        if(handle == NULL)
        {
            const char *error = dlerror();
            fprintf(stderr, "%s\n", error);
            exit(1);
        }
    }
}

int LCBootstrapMain(NSString *executablePath,
                    int argc,
                    char *argv[])
{
    if(executablePath == nil)
    {
        return 1;
    }
    
    /* preload executable to bypass RT_NOLOAD */
    char cdhash[USER_FSIGNATURES_CDHASH_LEN];
    int64_t ret = liveshim_syscall(SYS_pectl, kPECTLCategoryCodeSigning, kPECTLCodeSigningGetCDHash, cdhash, NULL, MACH_PORT_NULL);
    appMainImageIndex = _dyld_image_count();
    /* makes sure the binary gets loaded that is meant to have the ksurface capabilities */
    void *appHandle = dlopenBypassingLockWithTrust(executablePath.fileSystemRepresentation, RTLD_LAZY | RTLD_GLOBAL | RTLD_FIRST | RTLD_NODELETE, ret != 0 ? NULL : cdhash);
    appExecutableHandle = appHandle;
    if(!appHandle || (uint64_t)appHandle > 0xf00000000000)
    {
        printf("%s\n", dlerror());
        return 1;
    }
    
    /* find main */
    int (*entry)(int, char**) = LCGetMachOEntryPoint(appHandle);
    assert(entry);
    
    /*
     * now we load the executable of the bundle, as it doesn't
     * matter anymore from now on what CF does we can safely
     * load it as it is loaded already and complete the safe
     * initilization of the bundle swap LCOverwriteExecutablePath
     * did. This is necessary cause of NSBundle's internal state,
     * it can also fix known issues with the old implementation
     * of Duy Tran. Not only the app cares about this bundle,
     * the frameworks the app uses do aswell.
     */
    CFBundleRef bundle = CFBundleGetMainBundle();
    if(CFBundleLoadExecutable(bundle))
    {
        CFBundleSetBinaryType(bundle, __CFBundleDYLDExecutableBinary);
    }
    
    /* now applying LC hooks */
    NUDGuestHooksInit();
    NSFMGuestHooksInit();
    UIKitGuestHooksInit();
    initDead10ccFix();
    DyldHooksInit();
    LCInsertLibrariesIfNeeded();
    
    return entry(argc, argv);
}
