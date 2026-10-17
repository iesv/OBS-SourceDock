# Source Dock 0.5.1-2

Source Dock adds source preview and interaction docks to OBS Studio. This version fixes the invalid Qt enter/leave event cast associated with the reported F1 crash.

## Download and install

The [release](https://github.com/iesv/OBS-SourceDock/releases/tag/0.5.1-2) contains two packages:

- **Windows x64:** extract `source-dock-0.5.1-2-windows-x64.zip` and double-click `install.bat`. Accept the administrator prompt if Windows requests permission.
- **macOS Intel and Apple Silicon:** extract `source-dock-0.5.1-2-macos-universal.zip` and run `/bin/bash install.sh` from its extracted folder in Terminal. The bundle supports macOS 12 or later and is ad-hoc signed, without Developer ID signing or notarization.

Close OBS before installation. Each installer exits after a five-second countdown; press any key to exit sooner. The Windows installer updates an existing default OBS installation or installs to the standard ProgramData plugin directory. The macOS installer installs for the current user.

On macOS, the installer automatically removes `com.apple.quarantine` from the staged plugin bundle and its contents before replacing the previous installation. It then verifies the bundle signature. If quarantine removal fails, installation stops before replacing the installed plugin. To use a full path, type `/bin/bash ` in Terminal, drag `install.sh` into the Terminal window, and press Return.

See the [fix and installation guide](FIX-0.5.1-2.md) and [release notes](RELEASE-NOTES-0.5.1-2.md) for details.

## Settings window

The settings window opens at 1152 × 648 logical pixels (16:9), scaled down on smaller screens. Drag its border or bottom-right corner to resize it. The last width is saved in the plugin's OBS configuration directory; reopening uses that width at 16:9, fitted to the current screen.

## Source and build

GitHub contains one initial source snapshot commit. The local source directory is distributed without `.git` metadata. Both release ZIPs are stored in `dist` inside the source tree:

```text
OBS-SourceDock/
├── CMakeLists.txt
├── ...
└── dist/
    ├── source-dock-0.5.1-2-windows-x64.zip
    └── source-dock-0.5.1-2-macos-universal.zip
```

Every plugin build clears `dist` before compiling, including incremental builds. Old ZIPs and extracted packages in that directory are removed first. Packaging writes its ZIP directly to `dist`; it does not clear the directory again, so collecting the two platform packages retains both. `dist` is generated locally and excluded from Git. Intermediate build files, old source archives, patches and standalone checksum files are excluded from the local source distribution.

Use the **Source Dock 0.5.1-2** workflow in GitHub Actions to build and test Windows x64 and macOS Universal packages. It runs manually and produces one ZIP per platform.

Use `scope: packages-only` to compile and verify both platform packages without repeating the separate native macOS dock stress scenarios.

For installer-only changes, `scope: installer-only` updates the macOS ZIP using the existing signed Universal payload and runs native installation, recursive quarantine-removal, signature and countdown tests without recompiling the plugin.

Use `scope: windows-installer-only` to update and test the single self-contained `install.bat` with the existing Windows DLL and resources. The BAT uses the PowerShell runtime included with Windows and needs no separate installer script.

## Native macOS dock stress test

The workflow also supports `scope: stress-only` and `source: browser`, `color` or `both`. It launches OBS 32.0.4 on native Cocoa in a fresh CI user account and uses the actual Source Dock preview component. Each source scenario performs 200 programmatic float/dock cycles and checks the five built-in OBS dock menu actions, native view ownership, visibility and input capture. A plain QWidget dock supplies a baseline: Qt's show action can leave a dock behind an inactive tab, so explicit tab selection is checked separately. Physical drag gestures and operating-system menu clicks are outside this automated test's scope. Reports, screenshots and timeout samples are collected temporarily for diagnosis.

The `SOURCE_DOCK_MAC_STRESS_DRIVER` CMake option is test-only and disabled in release builds. The launcher refuses to overwrite an existing OBS user configuration.

The completed run on October 17, 2026 used macOS 15.7.9, Apple Silicon ARM64, OBS 32.0.4 and Qt 6.8.3 in a hosted Mac virtual machine with Apple Software Renderer. The browser source (a static data-URI page) and color source each passed 200 float/dock cycles and 1,000 built-in dock checks. Both also passed native view ownership, hit-testing and input-capture checks. A plain dock reproduced the inactive-tab behavior; selecting the tab made the built-in panel visible.

The reported failure after physically dragging a browser-source dock into OBS was not reproduced by this test. No fix for that separate macOS issue is claimed. Physical mouse dragging, operating-system menu clicks, the user's actual browser URL, physical GPU rendering and Intel execution remain outside the completed test's scope.

The user confirms that built-in dock dragging works with Source Dock disabled and fails only when it is enabled. Further docking changes are paused at the user's request; these results do not establish OBS or Qt as the cause.

## Credits and license

Based on [Exeldro's Source Dock](https://github.com/exeldro/obs-source-dock). The original authorship and GPL-2.0 license are retained. [Support the original author](https://www.paypal.me/exeldro).
