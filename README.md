<div align="center">
  <h1><b>Nyxian</b></h1>
  <p><i>A full native IDE and a userspace microkernel for building and running iOS apps entirely on-device. offline, unjailbroken, iOS 17.0 through iOS 27 Beta 4</i></p>
  <p><b><a href="./PATCH_NOTES.md">📖 iOS 17.0 & TrollStore Patch Notes & Rebase Guide</a></b></p>
</div>
<h6 align="center">
  <a target="_blank" href="https://discord.gg/H96bhkAHjB"><img src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fdiscord.com%2Fapi%2Fv9%2Finvites%2FH96bhkAHjB&amp;query=profile.member_count&amp;suffix=%20Members&amp;style=for-the-badge&amp;logo=discord&amp;logoColor=fff&amp;label=emexLabs%20Discord&amp;labelColor=000&amp;color=fff" alt="Discord invite"></a>
  <a href="https://github.com/emexlab/emexDE/actions/workflows/build.yml"><img src="https://img.shields.io/github/actions/workflow/status/emexlab/emexDE/build.yml?style=for-the-badge&amp;logo=github&amp;label=Build%20iOS%20App&amp;labelColor=000&amp;color=fff" alt="Build iOS App"></a>
</h6>
<p align="center">
  <img src="./mockup.png">
</p>

## What is it?
Nyxian is an iOS app that empowers developers with a full toolchain they can use while even being offline for iOS development on iPhone. It supports Swift, C, Objective-C, C++ and Objective-C++. It’s a powerful IDE that made the impossible possible, a fully on-device iOS IDE that doesn’t even need a cloud and can even be used with airplane mode enabled after it downloaded the SDK and resources from our server. It supports officially iOS 17.0 all the way up to the latest iOS version (iOS/iPadOS 27 Beta 4 tested). You can compile and run iOS apps on the go with ease, using the entire iOS 26.5 SDK.

## Installation
To start using Nyxian view the [Installation Guide](https://emexlabs.org/Nyxian/docs/installation/).

## Limitations
The only current limitation is that we cannot intercept a arm64 supervisor call, but that is not so much of a problem, because remember we are on iOS, processes have nearly no priveleges, so by bypassing our shims and asking the iOS kernel directly wouldn't grant anything useful to the attacker, there may be tho a way to intercept a arm64 supervisor call, we think constantly in all directions. If there may be a register apple did not account for or a condition in which a arm64 supervisor call causes a debug exception. So we are already very focused on finding a possible soulution as that would also take weight from the guest process and make it's initialization speed faster, for the speed we have a other solution tho, a extension process poll where extensions wait on mach msg traps till they get the request, meaning they are entirely setup and ready to serve shrinking the initilization speed to effectively zero.

## Todo
- IDE
  - Compiling code
    - [x] C support
    - [x] Objective-C support
    - [x] C++ support
    - [x] Objective-C++ support
    - [x] Swift support
  - Typechecking
    - [x] C support
    - [x] Objective-C support
    - [x] C++ support (limited without indexing)
    - [x] Objective-C++ support (limited without indexing)
    - [ ] Swift support
  - [x] Linking objects to MachO
  - [ ] Indexing
- Offline Code Execution
  - [x] Code execution (via NSExtension)
  - Micro Kernel (ksurface)
    - [x] radix trees
    - [x] object API
    - [x] process object
    - [x] privelege model
    - [x] custom entitlement blob (translated from AppleCS to NXT2 aswell!)
    - kext link editor (kxld)
      - [x] validate code signature of kext
      - [x] validate it's nyxian trust blob
      - [x] load kext executable into nyxian address space
      - [x] find it's kmod
      - [x] apply fixups for kext
      - [x] fix ObjC
      - [ ] fix thread local storage
      - [x] handle it's exports
      - [x] reseal constant data section
      - [x] run it's initializers
      - [x] act upon `kmod_info_t`
    - Syscall handling
      - [x] Mach IPC syscall server
      - [x] Task port handoff (usually they are guarded we bypass that by moving a receive right after the send right has been set as exception port to the host and then executing a `__builtin_trap` which then causes the host to get a `ÌKOT_TASK` which is a control task port which can be reference retained and boom we got our redistributable unguarded task port)
      - [x] Memory copy in/out of guests (yep out of the iOS processes and into them without assistance, this is not a typo lol)
    - Subprocess Patches
      - [x] `posix_spawn`/`posix_spawnp` fix
      - [x] `vfork` fix
      - [x] `sysctl` fix
      - [x] tty support on iPhone and the necessary `ioctl` fix (tho not entirely yet, it only works when NXWindowSessionTerminal creates it, but it is already progress)
      - [x] libproc fix
      - [x] `task_for_pid`/`task_name_for_pid` fix (you heard right, that is not a typo)
      - [x] patches to credential syscalls like `setuid` or `setgid`
  - [x] Signing executables
  - [x] NSBundle think it is loaded **as a binary**
  - [x] Actually make iOS apps and binaries use the version as DYLD version they have been made for
  - [ ] Find NSExtension spawn limit
  - [x] File permissions in guest file system (using sandbox file extensions)
