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

#ifndef NXBRIDGE_H
#define NXBRIDGE_H

/* Objective-C UI Headers */
#import <UI/XCodeButton.h>

/* Apple Private API Headers */
#import <LindChain/Private/UIKitPrivate.h>

/* IDE Headers */
#import <LindChain/IDEFoundation/NXUser.h>
#import <LindChain/IDEFoundation/NXCodeTemplate.h>
#import <LindChain/IDEFoundation/NXPlist.h>
#import <LindChain/IDEFoundation/NXProject.h>
#import <LindChain/IDEFoundation/NXDocumentManager.h>
#import <LindChain/IDEFoundation/NXUtils.h>
#import <LindChain/IDEFoundation/NXBootstrap.h>
#import <LindChain/IDEBuilder/LDEFilesFinder.h>
#import <LindChain/IDEBuilder/NXPhaseEngine.h>
#import <LindChain/IDEBuilder/NXPhaseRunner.h>
#import <LindChain/IDELanguageServer/NXLanguageServer.h>
#import <LindChain/IDEConsole/NXConsoleView.h>

/* LindChain Core Headers */
#import <LindChain/TrollStoreSupport/NXTrollStoreSupport.h>
#import <LindChain/Downloader/fdownload.h>
#import <LindChain/Utils/Zip.h>
#import <LindChain/Utils/LDEDebouncer.h>
#import <LindChain/Utils/Utils.h>

/* Micro Kernel Headers */
#import <LindChain/WindowServer/NXWindowServer.h>
#import <LindChain/WindowServer/Session/NXWindowSessionApplication.h>
#import <LindChain/WindowServer/Session/NXWindowSessionTerminal.h>
#import <LindChain/ProcEnvironment/PELaunchServiceManager.h>
#import <LindChain/ProcEnvironment/PEProcessManager.h>
#import <LindChain/ProcEnvironment/PEExtension.h>
#import <LindChain/ProcEnvironment/PEUserspaceManager.h>
#import <LindChain/ProcEnvironment/Surface/surface.h>
#import <LindChain/ProcEnvironment/LiveContainer/LCUtils.h>
#import <LindChain/ProcEnvironment/LiveContainer/LCMachOUtils.h>
#import <LindChain/ProcEnvironment/LiveContainer/ZSign/zsigner.h>
#import <LindChain/ProcEnvironment/Surface/trust/trust.h>
#import <LindChain/ProcEnvironment/Surface/fs/fs.h>
#import <LindChain/ProcEnvironment/KextLoader/PEKext.h>
#import <LindChain/ProcEnvironment/Utils/vnode.h>
#import <LindChain/ProcEnvironment/Utils/klog.h>
#import <LindChain/ProcEnvironment/Utils/misc.h>

/* Daemon Interfaces Headers */
#import <LindChain/Services/applicationmgmtd/LDEApplicationWorkspace.h>

void refreshFile(const char* path);

#endif /* NXBRIDGE_H */
