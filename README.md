# Age of Empires II (1999) - iOS / iPadOS Native Port Project

Turnkey Xcode project architecture targeting iOS/iPadOS to boot classic **Age of Empires II (1999)** and **The Conquerors Expansion (2000)** (`EMPIRES2.EXE` / `age2_x1.exe`).

---

## 🏛️ Architecture Overview

The project bridges three battle-tested open-source iOS architectures:

```
┌─────────────────────────────────────────────────────────────────┐
│                    iOS / iPadOS User Space                      │
│                                                                 │
│  ┌───────────────────────┐         ┌─────────────────────────┐  │
│  │  TouchInputOverlay    │         │   VirtualControlsOverlay│  │
│  │ (fallout1-ce gestural │         │  (TC, Idle, ESC, F3,    │  │
│  │  touch-to-mouse core) │         │   Direct/Trackpad, Logs)│  │
│  └───────────┬───────────┘         └────────────┬────────────┘  │
│              │                                  │               │
│              ▼                                  ▼               │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │             MetalViewportView (utmapp/UTM style)          │  │
│  │    Triple-buffered CAMetalLayer / MTKView with 120Hz      │  │
│  │    CADisplayLink ProMotion & aspect-fit scaling           │  │
│  └───────────────────────────┬───────────────────────────────┘  │
│                              │                                  │
│  ┌───────────────────────────┴───────────────────────────────┐  │
│  │          EmulationBridge (C++ / Obj-C Bridge)             │  │
│  └───────────────────────────┬───────────────────────────────┘  │
└──────────────────────────────┼──────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────┐
│                   Embedded Runner Core (No JIT)                 │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  DOSBox-Pure / TinyEMU Win32 Interpreter Core           │   │
│   │  - Mounts iOS sandbox Documents/ as FAT Drive C:        │   │
│   │  - Boots Windows 98 SE guest kernel in interpreter mode │   │
│   │  - Executes EMPIRES2.EXE (DirectDraw 7 / Win32 x86)     │   │
│   └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────┐
│              Diagnostics, Logging & Crash Reporting             │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  CrashReporter & Centralized Diagnostic Logger          │   │
│   │  - POSIX Signal Handlers (SIGSEGV, SIGBUS, SIGILL...)   │   │
│   │  - Signal-safe alternate stack + backtrace capture      │   │
│   │  - Writes to Documents/Logs/aoe2_runtime.log            │   │
│   │  - Real-time in-app Log Viewer HUD modal                │   │
│   └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📂 Project Directory Structure

```
.
├── project.yml                          # XcodeGen spec for generating .xcodeproj
├── Source/
│   ├── App/
│   │   ├── AppDelegate.swift            # CrashReporter init, lifecycle & background pause
│   │   ├── Info.plist                   # UIFileSharingEnabled, 120Hz ProMotion config
│   │   └── AoE2-Bridging-Header.h       # C/C++ runner & CrashReporter bridging
│   ├── Input/
│   │   └── TouchInputOverlay.swift      # Complete fallout1-ce touch-to-mouse translation
│   ├── Rendering/
│   │   ├── MetalViewportView.swift      # UTM-style Metal viewport with 120Hz display link
│   │   └── Shaders.metal                # Crisp nearest / bilinear / CRT Metal shaders
│   ├── Core/
│   │   ├── CrashReporter.h              # Signal & exception crash reporter header
│   │   ├── CrashReporter.mm             # Signal handler, backtrace & async-safe file write
│   │   ├── Logger.swift                 # Centralized multi-category logging engine
│   │   ├── EmulationBridge.h            # C / Obj-C API declarations
│   │   ├── EmulationBridge.mm           # Bridge implementation with logging & breadcrumbs
│   │   ├── RunnerCore.h                 # Runner loop & frame management
│   │   ├── RunnerCore.cpp               # C++ execution thread, FPS tracking & DirectDraw
│   │   └── GameFileManager.swift        # iTunes/Files sandbox detector & importer
│   └── UI/
│       ├── GameViewController.swift     # Main container & crash alert coordinator
│       ├── VirtualControlsOverlay.swift # Translucent AoE2 HUD hotkeys & Logs button
│       ├── LogViewerViewController.swift# In-app diagnostic viewer & crash log inspector
│       └── DocumentPickerView.swift     # Fallback import UI when files missing
└── README.md
```

---

## 📜 Diagnostic Logging & Crash Reports

The project features a full **enterprise-grade diagnostic logging and crash reporting system** built for non-JIT retro emulation debugging:

### 1. Where Logs Are Stored
Because `UIFileSharingEnabled` is configured in `Info.plist`, you can view and extract logs directly using **Apple Finder (macOS)** or **iTunes / Apple Devices (Windows)**:
- **Runtime Log**: `Documents/Logs/aoe2_runtime.log` (appends all events with timestamps, log levels, and subsystem categories).
- **Crash Reports**: `Documents/Logs/crash_YYYYMMDD_HHMMSS.log` (generated automatically when a native POSIX signal or unhandled exception occurs).

### 2. POSIX Signals & Exceptions Captured
- `SIGSEGV` (Segmentation fault / illegal memory dereference in x86 translation)
- `SIGBUS` (Unaligned memory access or bus error)
- `SIGILL` (Illegal CPU instruction)
- `SIGABRT` (Abort / assertion failure)
- `SIGFPE` (Floating-point / arithmetic exception)
- `SIGTRAP` (Trace/breakpoint trap)
- `NSUncaughtExceptionHandler` (Objective-C/Swift unhandled runtime exceptions)

### 3. Crash Report Anatomy
When a crash happens, `CrashReporter` utilizes a dedicated 128KB **alternate signal stack** (`sigaltstack`) and writes without allocating dynamic memory (`malloc`), guaranteeing report generation even during memory exhaustion:
```
=================================================================
           AGE OF EMPIRES II (iOS) - CRASH REPORT                
=================================================================

Timestamp: 2026-10-20 19:42:15 UTC
Signal: 11 - SIGSEGV (Segmentation Fault / Bad Memory Access)
Faulting Address: 0x0

--- RECENT EXECUTION BREADCRUMBS ---
  [19:42:12 [FileSystem] Verified critical asset: data/empires2.dat]
  [19:42:13 [Emulation] Starting EmulationBridge with GameDir='/var/mobile/.../Age of Empires II']
  [19:42:13 [RunnerCore] Starting guest execution thread]
  [19:42:14 [Touch] LeftClick at (512, 384)]
  [19:42:15 [Input] MouseBtn: Left DOWN at (512, 384)]

--- STACK BACKTRACE ---
0   AoE2                                0x0000000100234a10 PosixSignalHandler + 144
1   libsystem_platform.dylib            0x00000001db163c20 _sigtramp + 56
2   AoE2                                0x0000000100231844 AoE2Runner::RunnerCore::ExecutionThreadLoop() + 268
...
==================== END OF CRASH REPORT =======================
```

### 4. Interactive In-App Log Viewer
- Tap the **"📜 Logs"** button on the top HUD bar at any time.
- Switch between **"All Logs"**, **"⚠️ Errors"**, and **"💀 Crash Reports"**.
- View complete stack traces on device.
- Tap **Share (Action icon)** to immediately AirDrop, email, or copy the log.
- Upon booting, if a crash occurred during the previous session, an alert prompts you to open and review the crash log.

---

## 🛠️ Step-by-Step Build & Setup Guide

### Phase 1: Generate the Xcode Project

```bash
# Install xcodegen if not already installed (macOS)
brew install xcodegen

# In the project root:
xcodegen generate
```
This generates `AoE2-iOS.xcodeproj` configured with Metal, MetalKit, QuartzCore, UIKit, and AudioToolbox frameworks.

---

### Phase 2: Linking the Embedded Runner Core (No JIT)

Age of Empires II (1999) is an x86 32-bit Win32 application. Because standard iOS sideloading (AltStore, SideStore, Sideloadly) does not permit dynamic code generation (JIT) without a debugger attachment, we use a **statically compiled non-JIT interpreter**:

#### Option A: DOSBox-Pure Core (Recommended)
`schellingb/dosbox-pure` is an advanced fork of DOSBox that natively boots Windows 98/95 disk images and automatically launches Windows games from a mounted directory:

1. Clone `dosbox-pure` into a submodule:
   ```bash
   git submodule add https://github.com/schellingb/dosbox-pure.git External/dosbox-pure
   ```
2. In `External/dosbox-pure`, compile for iOS ARM64:
   ```bash
   make platform=ios-arm64
   ```
3. In `Source/Core/RunnerCore.cpp`, wire the DOSBox-Pure frame callback:
   ```cpp
   // DOSBox-Pure delivers the 32-bit DirectDraw buffer:
   void retro_run() {
       uint32_t* guestPixels = dosbox_get_framebuffer();
       m_videoCallback(m_guestWidth, m_guestHeight, m_guestPitch, guestPixels);
   }
   ```
4. Place a lightweight Windows 98 SE base image (`win98se.img`, ~120MB) into the app bundle or allow the user to drop it into `Documents/`.

---

### Phase 3: Packaging and Signing into a `.ipa`

#### Method 1: Via Xcode GUI
1. Open `AoE2-iOS.xcodeproj` in Xcode on macOS.
2. Under **Signing & Capabilities**, select your Apple ID team (Free or Paid).
3. Select **Any iOS Device (arm64)** as the target.
4. Choose **Product > Archive**.
5. Once the Organizer opens:
   - Click **Distribute App** -> **Custom** -> **Ad Hoc** or **Development**.
   - Export to folder to obtain `AoE2.ipa`.

#### Method 2: Command-Line Packaging (`xcodebuild`)
```bash
# 1. Build Archive
xcodebuild archive \
  -project AoE2-iOS.xcodeproj \
  -scheme AoE2 \
  -configuration Release \
  -archivePath ./build/AoE2.xcarchive \
  -destination "generic/platform=iOS" \
  CODE_SIGN_STYLE="Automatic"

# 2. Export IPA
xcodebuild -exportArchive \
  -archivePath ./build/AoE2.xcarchive \
  -exportPath ./build/ipa \
  -exportOptionsPlist ExportOptions.plist
```

---

### Phase 4: Sideloading to iPhone / iPad

You can install the `.ipa` onto any non-jailbroken device running iOS 15.0 - 18.x+:

- **Feather (On-Device Sideloading)**: 
  - 100% compatible with Feather on-device signing (`zsign` / `libimobiledevice`).
  - `AoE2.entitlements` contains standard `<key>get-task-allow</key><true/>`.
  - Zero JIT requirement: The embedded non-JIT interpreter boots directly with standard developer, personal, or distribution certificates.
  - Simply import `AoE2.ipa` into Feather, sign with your certificate profile, and tap Install.
- **SideStore / AltStore**: Select `AoE2.ipa` in the My Apps tab and install.
- **Sideloadly**: Drag `AoE2.ipa` into Sideloadly on macOS/Windows, connect device via USB, enter Apple ID, and click Start.
- **TrollStore** (iOS 15.0 - 17.0): Direct permanent installation without revokes or 7-day limits.

---

### Phase 5: Importing the Game Files

Because `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` are enabled in `Info.plist`:

1. Connect your iPhone/iPad to Mac (Finder) or PC (iTunes / Apple Devices app).
2. Go to **Files** -> Select **AoE2**.
3. Drag your original PC installation folder of **Age of Empires II** into the app's Documents folder:
   ```
   Age of Empires II/
   ├── EMPIRES2.EXE
   ├── data/
   │   └── empires2.dat
   ├── language.dll
   ├── sound/
   └── win98se.img (if using Win98 guest runner)
   ```
4. Launch the app on iOS. The app automatically detects `EMPIRES2.EXE` and boots straight into the game.

---

## 🎮 In-Game Controls & Small-Screen UI Adaptation

### 1. Fallout-1-CE Gestural Touch-to-Mouse Engine

| Touch Gesture | PC Mouse / Keyboard Action | AoE2 In-Game Result |
| :--- | :--- | :--- |
| **Single Tap** | Left Click (Down + Up) | Select unit/building, confirm target |
| **Two-Finger Tap** | Right Click (Down + Up) | Command unit to Move / Attack / Gather |
| **Tap & Hold + Drag** | Left Click Held Down + Drag | Draws green rectangular unit selection marquee box |
| **Two-Finger Drag** | Middle Click / Arrow Pan | Smoothly scrolls and pans camera across the map |
| **Screen Edge Touch** | Border Mouse Hover | Classic AoE2 edge scrolling |
| **HUD: 🏛️ TC** | Press 'H' Key | Immediately jumps camera to Town Center |
| **HUD: 🚶 Idle** | Press '.' Key | Cycles through idle villagers |
| **HUD: ⏸️ F3** | Press 'F3' Key | Pauses/unpauses the game |
| **HUD: 📺 Filter** | Metal Shader Toggle | Cycles Nearest Neighbor (Crisp) ➔ Bilinear ➔ CRT Scanline |
| **HUD: 🎯 Mode** | Input Mode Toggle | Switches between Direct Mode and Trackpad Mode |
| **HUD: 📜 Logs** | Open Log Viewer | Real-time console, error filtering, and crash log viewer |

### 2. Tactical Flanks (19.5:9 iPhone Pillarbox Margins)
On wide iPhone screens (iPhone 11 through 16 Pro Max), the 4:3 aspect-fit game creates unused pillarbox margins on the left and right. The project leverages these margins to host native SwiftUI buttons without obstructing the gameplay area:
- **Left Flank (Map Cycling)**:
  - `TC` ('H'): Jump to Town Center
  - `Idle Vil` ('.'): Cycle idle villagers
  - `Military` (','): Cycle military units
  - `Focus` (`Space`): Center view on current selection
- **Right Flank (Command Toggles)**:
  - `Econ` ('B'): Economic build menu
  - `Mil Bld` ('V'): Military build menu
  - `Repair` ('R'): Repair command
  - `Garrison` ('T'): Garrison command
  - `Delete` (`DEL`): Delete selected unit/building
  - `Loupe`: Toggle Command Bar Zoom Loupe on/off

### 3. Command Bar Zoom Loupe
- When interacting with unit production icons in the bottom HUD on small iPhone screens, a **2.2x magnified Metal sub-texture** floats 88pt above the finger touch position.
- Uses nearest-neighbor pixel sampling to preserve crisp retro pixel art.
- Features a gold bezel with targeting crosshair, ensuring accurate tapping on small 32x32 retro icons.
- Automatically dismisses upon finger lift.
