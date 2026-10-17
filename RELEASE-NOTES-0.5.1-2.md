# Source Dock 0.5.1-2

Fixes the invalid Qt event cast in mouse enter/leave handling associated with the reported F1 crash. `Leave` is handled as a plain `QEvent`; `Enter` and `MouseMove` use their shared `QSinglePointEvent` base. Ctrl-left panning handles actual mouse moves only.

Both platform packages are rebuilt for version `0.5.1-2`, including the 16:9 settings window and automatic macOS plugin quarantine removal. Installer messages, plugin version strings and package filenames use the new revision. The macOS bundle build number is `2`.

## Settings window

The settings window now opens at 1152 × 648 logical pixels (16:9), scaled down to fit smaller screens. Its last width is remembered in the plugin's OBS configuration directory, and reopening preserves the 16:9 ratio. Drag the window border or bottom-right corner to resize it.

## Downloads

- `source-dock-0.5.1-2-windows-x64.zip`: plugin, locale resources and one self-contained `install.bat`.
- `source-dock-0.5.1-2-macos-universal.zip`: Intel/Apple Silicon plugin bundle and `install.sh`.

These are the only uploaded release assets. Source files are available in the repository.

## Installation

Close OBS and extract the entire ZIP before running the installer.

On Windows, double-click `install.bat`. An existing Source Dock installation in OBS's legacy directory is updated in place; a fresh installation uses ProgramData. Fresh OBS 32 installations use the `bin/64bit` layout, while detected OBS 33 or later installations use the direct DLL layout. Administrator permission is requested only if required.

The Windows installation logic is contained in that BAT file and uses Windows PowerShell. It keeps the five-second countdown and any-key exit, with no separate CMD or PS1 installer. Both native plugin binaries were freshly rebuilt for this installer update.

On macOS, run `/bin/bash install.sh` from the extracted folder in Terminal. It installs the bundle to `~/Library/Application Support/obs-studio/plugins`. The plugin supports macOS 12 or later and is ad-hoc signed, without Developer ID signing or notarization.

The macOS installer automatically removes `com.apple.quarantine` recursively from its staged plugin copy, verifies the signature, then replaces the installed plugin. Failure to remove quarantine cancels installation before the existing plugin is replaced. Other extended attributes are preserved. If macOS blocks the installer script itself, run it from Terminal with `/bin/bash` followed by the script's path.

Both installers display a five-second exit countdown after completion or an error. Press any key during the countdown to exit immediately.

## Build output

Both compiled ZIPs are stored in `dist` inside the source tree (`dist` at the repository root). Before each plugin compilation, CMake clears the directory, including during incremental builds. Native GitHub Actions jobs verify that old output is removed, then package, test and upload the ZIP from `dist`. The directory is generated and excluded from Git. Only the two current platform ZIPs are kept in the local distribution and release.

## Validation

Windows x64 and macOS Universal native builds passed. Both native platforms passed fresh and repeat installation tests, copied-file verification, and the five-second countdown test. Windows also passed legacy installation updates. The macOS package passed architecture, executable-permission and bundle-signature checks. The keypress exit path was verified in a macOS terminal. Interactive Windows UAC and OBS F1 behavior were not exercised by these build tests.

The macOS installer passed native tests with quarantine applied to the bundle root, a nested directory, Info.plist and the executable. All installed quarantine attributes were removed, other test metadata was preserved, and the source bundle and an unrelated file retained their attributes. Clean and repeated installations, signature and binary identity checks, the five-second countdown and early keypress exit also passed.

The plugin's earlier 11-group Qt/libobs regression suite passed in WSL with AddressSanitizer and UndefinedBehaviorSanitizer. F1 has not been retested in an interactive OBS session on Windows or macOS.

Earlier native Cocoa dock stress testing passed against the same dock implementation in OBS 32.0.4 with Qt 6.8.3 on a hosted Apple Silicon Mac running macOS 15.7.9 (Apple Software Renderer). A browser source using a static data-URI page and a color source each completed 200 programmatic float/dock cycles and 1,000 built-in dock menu-action and tab-selection checks. Native view ownership, hit-testing and input capture checks passed. The plain-dock baseline confirmed that showing a tabbed dock does not necessarily select its tab. These dock stress scenarios were not repeated for this installer rebuild.

The user's failure after physically dragging a browser-source dock into OBS was not reproduced. This release does not claim a fix for that separate macOS issue. The test does not cover physical drag gestures, operating-system menu clicks, the user's actual browser URL, physical GPU rendering or Intel execution. The test-only driver is excluded from both release binaries.

The user confirms that the failure occurs only while Source Dock is enabled; built-in docks can be dragged normally when it is disabled. This prioritizes the plugin's docking compatibility path for investigation and does not establish OBS or Qt as the root cause.

The plugin log and Windows textual version are `0.5.1-2`; numeric OS version fields use `0.5.1`. Dependencies retain the upstream OBS 31.1.0 SDK and Qt configuration. The reported OBS version was 32.0.4.

See [FIX-0.5.1-2.md](https://github.com/iesv/OBS-SourceDock/blob/main/FIX-0.5.1-2.md) for details. Based on [Exeldro's Source Dock](https://github.com/exeldro/obs-source-dock), with original authorship and the GPL-2.0 license retained.
