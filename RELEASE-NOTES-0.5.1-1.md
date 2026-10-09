# Source Dock 0.5.1-1

This revision fixes an invalid Qt event cast in Source Dock's mouse enter/leave handling. The defect matches the reported F1-triggered call chain: `OBSEventFilter::eventFilter -> SourceDock::HandleMouseMoveEvent -> Qt6Gui`.

Previously, both a plain `QEvent::Leave` and `QEnterEvent` were cast to `QMouseEvent`. The handler now reads data according to the actual event type. Leave events no longer access nonexistent mouse fields, and Ctrl-left dragging handles actual mouse moves only. The crash report does not identify the exact boundary event triggered after F1.

## Downloads

- **Windows x64:** `source-dock-0.5.1-1-windows-x64.zip`.
- **macOS Universal:** `source-dock-0.5.1-1-macos-universal.zip`, supporting Intel and Apple Silicon on macOS 12 or later. The bundle is ad-hoc signed, without Developer ID signing or notarization.
- **Source:** `source-dock-0.5.1-1-source.zip`.
- **Patches:** `source-dock-f1-fix.patch` contains the mouse-event fix; `source-dock-0.5.1-1-full.patch` also includes versioning, CI, tests, and documentation.
- **Checksums:** `SHA256SUMS.txt`.

## Validation

The complete Linux plugin build succeeded. All 11 regression groups passed AddressSanitizer and UndefinedBehaviorSanitizer checks in WSL Debian 13 with Qt 6.8.2 and libobs 30.2.3. The tests compile the actual plugin implementation and use real Qt events and libobs callbacks. The unpatched code fails UBSan checks for both Leave and Enter events.

The Windows and macOS packages passed [native GitHub Actions builds](https://github.com/iesv/OBS-SourceDock/actions/runs/37867644352). Windows checks the DLL version; macOS checks both architectures and the bundle signature. The Windows DLL also passed dependency-loading and module-name checks on a machine with OBS 32.0.4 installed.

**F1 has not been retested in a running OBS interface on Windows or macOS.** Installation and verification of the original trigger are still required.

The plugin startup log and Windows textual version are **0.5.1-1**. Fields requiring a numeric version use `0.5.1`. Dependencies retain the upstream OBS 31.1.0 SDK and Qt configuration; the reported OBS version is 32.0.4.

The binary build commit is `9a40cbec5668b7acdcd4f29e94cd80c2241dc23d`. Documentation updates after that build affect Markdown files only; the source archive and complete patch include those updates.

## Installation for OBS Studio 32

Close OBS and back up the existing plugin before updating.

For an existing Windows installation in the default location, replace `C:\Program Files\obs-studio\obs-plugins\64bit\source-dock.dll` with `source-dock/bin/64bit/source-dock.dll` from the archive. Keep the locale files in `C:\Program Files\obs-studio\data\obs-plugins\source-dock`, or update them from the archive's `source-dock/data` directory. Keep one installed copy of Source Dock.

For a fresh Windows installation, extract the complete `source-dock` folder to `C:\ProgramData\obs-studio\plugins`. This produces `C:\ProgramData\obs-studio\plugins\source-dock\bin\64bit\source-dock.dll` and the corresponding `source-dock\data\locale` directory. See the [OBS plugins guide](https://obsproject.com/kb/plugins-guide) for this OBS Studio 32 layout.

On macOS, replace the existing `source-dock.plugin` bundle in `~/Library/Application Support/obs-studio/plugins` with the bundle from the archive.

See [FIX-0.5.1-1.md](https://github.com/iesv/OBS-SourceDock/blob/fix/f1-0.5.1-1/FIX-0.5.1-1.md) for the full explanation, acceptance checks, and build commands. The original author is [Exeldro](https://github.com/exeldro/obs-source-dock); the upstream GPL-2.0 license is retained.
