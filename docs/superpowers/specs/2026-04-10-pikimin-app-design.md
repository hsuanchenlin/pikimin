# Pikimin — macOS Android Emulator Wrapper for Pikmin Bloom

## Overview

A native SwiftUI macOS app (Apple Silicon only) that provides a one-click Android emulator experience for Pikmin Bloom walking simulation. Users install a small DMG, the app downloads SDK components on first launch, and provides a GUI to start the emulator and run a configurable walk simulation with live progress.

## Target

- macOS 14+ (Sonoma), Apple Silicon (arm64) only
- Distributed as a DMG with ad-hoc code signing
- Personal tool shared with friends, not App Store

## Architecture

Single SwiftUI app with four internal modules:

```
Pikimin.app
├── SwiftUI Views
│   ├── SetupView       — first-run download progress
│   ├── MainView        — emulator controls + walk dashboard
│   └── LogView         — scrollable output log
├── SDKManager          — downloads & extracts SDK components
├── EmulatorManager     — start/stop emulator, create AVD
└── WalkSimulator       — adb sensor + GPS commands, progress
```

All state managed via `@Observable` view models. Modules communicate through published properties.

## Data Directory

`~/Library/Application Support/Pikimin/`

```
sdk/
├── emulator/           (~1.1 GB)
├── platform-tools/     (~38 MB)
└── system-images/
    └── android-35/
        └── google_apis_playstore/
            └── arm64-v8a/   (~5.9 GB)
avd/                    (AVD files, ~2 GB after first boot)
```

## First-Run Setup Flow

When the sdk directory is missing or incomplete:

1. **Welcome screen** — informs user about ~7 GB download requirement.
2. **Download phase** — downloads from Google's official SDK URLs:
   - `platform-tools` for macOS arm64 (~38 MB zip)
   - `emulator` for macOS arm64 (~300 MB zip)
   - `system-images;android-35;google_apis_playstore;arm64-v8a` (~3 GB zip)
3. **Extract phase** — unzips each component into the sdk directory.
4. **AVD creation** — creates a Pixel 7 Play AVD with:
   - `hw.keyboard=yes`
   - `PlayStore.enabled=yes` (google_apis_playstore image)
   - arm64-v8a ABI
   - 6 GB data partition
5. **Transition** — shows main view.

Progress bar shows per-component and overall progress. Resumable — the app checks which components exist before downloading.

SDK licenses are pre-accepted via bundled config.

## Main View

### Emulator Controls (top section)

- **Start/Stop button** — toggles emulator process
  - States: "Start Emulator" → "Starting..." → "Stop Emulator"
- **Status indicator** — Stopped / Booting / Running

The emulator runs as a child `Process`. Launch command:
```
sdk/emulator/emulator -avd Pikimin_AVD -no-snapshot-load -gpu host -dns-server 8.8.8.8
```

Boot detection: polls `adb shell getprop sys.boot_completed` until it returns `1`.

### Walk Dashboard (bottom section)

- **Step count input** — number field, default 50,000
- **Start Walk / Stop Walk button** — disabled until emulator is Running
- **Live stats** (during walk):
  - Steps completed / total
  - Progress bar
  - Phase: "Wandering" or "Returning"
  - Current GPS coordinates
  - Percentage
- **Log area** — scrollable text showing recent output

### State Machine

```
Emulator: Stopped → Booting → Running → Stopped
Walk:     Idle → Walking → Idle
```

Walk requires Emulator=Running. Stopping the emulator force-stops the walk first.

## Walk Simulation

Ported from walk.sh to Swift. Runs as a Swift async task.

### Step Cycle (~500ms per step, ~2 steps/sec)

Each step issues these adb commands with 50-100ms sleep gaps:

1. **GPS update**: `adb emu geo fix <lon> <lat>`
2. **Swing**: acceleration `0.3:0.4:5.0`, gyroscope `0.2:0.3:0.0`, sleep 50ms
3. **Heel strike**: acceleration `-1.5:2.0:22.0`, sleep 50ms
4. **Peak impact**: acceleration `-2.0:2.5:25.0`, sleep 50ms
5. **Settling**: acceleration `-0.3:0.5:12.0`, sleep 50ms
6. **Midstance**: acceleration `0.0:0.0:9.8`, gyroscope `0.0:0.0:0.0`, sleep 100ms
7. **Toe off**: acceleration `0.5:-0.6:15.0`, sleep 50ms
8. **Rest**: acceleration `0.0:0.0:9.8`, sleep 100ms

Natural ~50ms adb latency provides additional spacing.

### Movement Algorithm

- Random direction (8 compass directions) with wobble
- Direction changes every 30-150 steps (random)
- First half: random wandering
- Second half: bias toward starting position (return home)
- GPS step size: ~0.000014 degrees (~1.5m)

### Progress Reporting

Updates an `@Observable` model after each step. SwiftUI view observes automatically.

### Cancellation

Swift structured concurrency — `Task.cancel()` on stop, checked via `Task.isCancelled` in loop.

## ADB Helper

A thin wrapper around `Process` that:
- Resolves adb path from `~/Library/Application Support/Pikimin/sdk/platform-tools/adb`
- Runs commands synchronously or async
- Returns stdout/stderr as strings
- Used by both EmulatorManager and WalkSimulator

## Packaging & Distribution

- **Build**: Xcode project, `xcodebuild` for CLI builds
- **App size**: ~5-10 MB (no SDK bundled)
- **DMG**: Created with `hdiutil`, standard drag-to-Applications layout
- **Code signing**: Ad-hoc — friends right-click → Open to bypass Gatekeeper
- **Min target**: macOS 14 Sonoma

## Out of Scope (v1)

- x86_64 / Intel Mac support
- Google Play Store sign-in automation
- Pikmin Bloom installation automation
- GPS location picker in the app UI
- App Store distribution
- Auto-updates
