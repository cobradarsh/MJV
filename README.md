# OpenCam

OpenCam is an independent, MIT-licensed virtual-camera tweak for RootHide. It provides a manager app and a `mediaserverd` hook that replaces outgoing camera video with a looping video or a black screen.

**Target:** iPhone 14 Pro, iOS 16.5, RootHide. Other devices and iOS versions are not verified. The source has been compile-checked, but the tweak has **not been tested on a physical device**.

## Features

- Select a video from Photos and export it as MP4.
- Preview the saved video before enabling it.
- Stream and loop the video instead of caching an entire movie in memory.
- Apply the video's display rotation and scale it with aspect-fill.
- Use a black screen instead; switch back to the saved video without importing it again.
- Enable or disable replacement globally from the app.
- Pass the real camera frames through unchanged while disabled.
- Start disabled after installation or upgrade.
- No account, payment system, network access, or third-party analytics.

Only camera video buffers are changed. Microphone audio, sample timestamps, and the original Photos item are not changed. Compatibility can vary between apps because this uses a private iOS camera-graph interface.

## Important safety notes

- **Do not install, upgrade, or remove the package during a call or recording.** Its package scripts restart `mediaserverd`, briefly interrupting camera and audio services.
- Disable OpenCam before an important call unless you have already tested the exact app and workflow.
- Remove or disable other virtual-camera tweaks first. Two tweaks modifying the same camera buffers can conflict.
- The app starts disabled. If a selected source is missing or cannot be decoded, enabled output falls back to black rather than exposing an unintended real frame.
- Uninstalling disables replacement and reloads `mediaserverd`. The imported video may remain for a future reinstall.

## Build a RootHide `.deb`

This source release intentionally does not include a prebuilt binary. The available Windows LLD linker can compile arm64e objects but does not produce a proper final arm64e dylib for this target. Use Apple's linker through Xcode or the included macOS workflow; do not rename an arm64 binary or merely edit its Mach-O architecture field.

### Option A: GitHub Actions, no Mac required

1. Create a new GitHub repository and upload the **contents of the `OpenCam` project folder** to its root. `.github/workflows/build.yml` must be at the repository's top level.
2. Open **Actions → Build RootHide package → Run workflow**.
3. The workflow installs RootHide Theos and `ldid`, builds with Apple's linker on macOS, and checks that the app and tweak are actually arm64e.
4. Download the **OpenCam-RootHide-arm64e** artifact from the completed run. It contains the installable `.deb`.

The workflow is included and configured, but it has not been executed from this workspace.

### Option B: macOS with Xcode

Install a current Xcode (including its iOS SDK), Homebrew, `ldid`, and RootHide Theos:

```sh
brew install ldid
git clone --recursive https://github.com/roothide/theos.git "$HOME/theos-roothide"
export THEOS="$HOME/theos-roothide"
cd /path/to/OpenCam
```

Build using the iOS SDK supplied with Xcode:

```sh
make clean
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide ARCHS=arm64e TARGET=iphone:clang:latest:16.0
```

Alternatively, put `iPhoneOS16.5.sdk` in `$THEOS/sdks` and run:

```sh
./build.sh
```

The package is written to:

```text
packages/com.opencam.virtualcamera_1.0.0_iphoneos-arm64e.deb
```

A genuine arm64e build is required for the injected dylib. Do not use a rootless/rootful package or a header-patched LLD output as a substitute.

### Option C: Build on the jailbroken device

Install RootHide's Theos toolchain, its build dependencies, `ldid`, and an iPhoneOS 16.5 SDK using RootHide's normal setup. In NewTerm, set `THEOS` to that RootHide Theos installation, change into the project directory, and run `./build.sh`. Build output appears under `packages/`.

## Install and use

1. End active calls and stop camera recording.
2. Open the generated `.deb` with Sileo or Zebra and install it. The installation script registers OpenCam and restarts `mediaserverd`.
3. Open **OpenCam** from the Home Screen.
4. Tap **Choose video from Photos**, select a video, and wait for the MP4 export to finish. Allow enough free storage for the temporary import and export.
5. Optionally tap **Preview video**.
6. Turn on **Enable virtual camera** and confirm. Open or reopen the camera view in the app you want to use.
7. Tap **Use black screen** for black output. When a saved video exists, the same button becomes **Use selected video** so you can switch back.
8. Turn off **Enable virtual camera** to restore real camera frames. No respring is needed for the enable switch.

The imported video stays on the device. Selecting or exporting it does not delete the original from Photos.

## Project layout

- `Tweak.m`: hooks only `BWNodeOutput.emitSampleBuffer:` for video output.
- `FrameSource.m`: serial video decoding, native frame pacing, looping, cached-frame rendering, black output, and Darwin configuration notifications.
- `ViewController.m`: Photos selection, temporary import, MP4 export, atomic publication, preview, and mode controls.
- `Shared.h`: RootHide-aware video/configuration paths and the root-filesystem enable marker.
- `layout/DEBIAN/`: installation and removal scripts.
- `.github/workflows/build.yml`: reproducible macOS RootHide package build with architecture checks.

## Verification and limitations

All five Objective-C source files were compiled for arm64 and arm64e against the iPhoneOS 16.5 SDK. The app and tweak passed arm64 symbol-resolution link checks; the shell scripts and property lists passed syntax/parsing checks. These checks do not establish runtime compatibility.

A final installable package was not produced on the Windows development machine because its linker lacks the required arm64e output support. No camera, import, preview, loop, black-screen, installation, or call behavior has been tested on the target iPhone. Test first with a short, non-sensitive video and an unimportant camera session.

OpenCam is a new implementation and is not affiliated with the original tweak's developer.
