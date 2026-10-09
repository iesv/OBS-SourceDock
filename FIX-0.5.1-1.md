# Source Dock 0.5.1-1

This revision fixes an invalid Qt event cast in `SourceDock::BuildEventFilter()` and `HandleMouseMoveEvent()`. It is based on upstream commit `b78fe9ea7649ece2984bc89432f71ca5f06322d4` and retains the upstream GPL-2.0 license.

## Cause and fix

The reported OBS 32.0.4 Windows crash has the call chain `OBSEventFilter::eventFilter -> SourceDock::HandleMouseMoveEvent -> Qt6Gui`.

Previously, `MouseMove`, `Enter`, and `Leave` were all cast to `QMouseEvent`. Qt delivers `Enter` as `QEnterEvent` and `Leave` as a plain `QEvent`. Reading `buttons()` from the latter accesses data that the object does not contain. F1 can indirectly lead to a boundary event when the interface changes; the crash report does not record the exact event type.

The handler now accepts `QEvent`, validates its type, and reads pointer data only from `MouseMove` and `Enter` through their shared `QSinglePointEvent` base. Leave uses an initialized OBS payload without reading pointer data. Ctrl-left-button panning is restricted to actual mouse moves. Existing source and scene interaction dispatch is retained.

References: [Qt event types](https://doc.qt.io/qt-6/qevent.html), [QEnterEvent](https://doc.qt.io/qt-6/qenterevent.html), [QSinglePointEvent](https://doc.qt.io/qt-6/qsinglepointevent.html).

## Validation

- Full Linux plugin build succeeded in WSL Debian 13 with GCC 14.2, Qt 6.8.2 and libobs 30.2.3.
- The regression executable compiles the actual plugin implementation and uses real Qt events and a registered libobs interaction source. It does not substitute a model of the handler.
- All 11 regression groups passed with AddressSanitizer and UndefinedBehaviorSanitizer: plain Leave, typed Enter, coordinates and modifiers, outside-source movement, Ctrl-left panning and limits, boundary events after panning, F1 dispatch followed by Leave, unsupported/null events, no-source behavior, and 1,000 Leave/Enter cycles.
- The unpatched upstream code fails for both a plain Leave and a typed Enter at `source-dock.cpp:937`, with UBSan reporting an invalid downcast to `QMouseEvent`. Both diagnostic runs exit with code 1.
- Leak detection is disabled for this headless Qt/libobs harness. No graphics renderer or OBS frontend session is started. No Windows or macOS interactive OBS F1 reproduction has been performed.

Windows x64 and macOS Universal builds were produced by `.github/workflows/fix-build.yaml` at commit `9a40cbec5668b7acdcd4f29e94cd80c2241dc23d`. The Windows job verifies the DLL's textual product version. The resulting DLL also loaded successfully on Windows with OBS 32.0.4 dependencies and returned the module name `SourceDock`. The macOS job verifies both arm64 and x86_64 slices and the bundle's ad-hoc signature. The dependency baseline remains the upstream OBS 31.1.0 SDK and Qt dependency set; the reported OBS version is 32.0.4.

## Version and packages

The release, OBS startup log and Windows textual resource version are `0.5.1-1`. CMake's numeric project version, Windows fixed numeric resources and macOS marketing version remain `0.5.1`, because those fields require numeric values. The macOS bundle build number is `1`.

- `source-dock-0.5.1-1-windows-x64.zip`: `source-dock/bin/64bit/source-dock.dll`, debug symbols and locale resources.
- `source-dock-0.5.1-1-macos-universal.zip`: `source-dock.plugin`, supporting Intel and Apple Silicon, macOS 12 or later. It is ad-hoc signed, without Developer ID signing or notarization.

## Installation

For an existing OBS Studio 32 installation on Windows using the default Program Files location:

1. Close OBS and back up the existing plugin DLL.
2. Extract `source-dock/bin/64bit/source-dock.dll` from the Windows archive and use it to replace `C:\Program Files\obs-studio\obs-plugins\64bit\source-dock.dll`.
3. Keep the existing locale files in `C:\Program Files\obs-studio\data\obs-plugins\source-dock`, or copy the archive's `source-dock/data` contents into that directory.
4. Reopen OBS. The plugin startup log should report `0.5.1-1`.

For a fresh OBS Studio 32 installation, the [OBS plugins guide](https://obsproject.com/kb/plugins-guide) recommends `C:\ProgramData\obs-studio\plugins`. Extract the archive's complete `source-dock` folder there, producing these paths:

```text
C:\ProgramData\obs-studio\plugins\source-dock\bin\64bit\source-dock.dll
C:\ProgramData\obs-studio\plugins\source-dock\data\locale\en-US.ini
```

Keep one installed copy of Source Dock. If OBS is installed to a custom location, use that installation's plugin and data directories for an existing-installation update. These Windows instructions target OBS Studio 32; later OBS versions may use a different plugin layout.

On macOS, close OBS and replace `source-dock.plugin` in `~/Library/Application Support/obs-studio/plugins` with the archive's bundle.

For interactive acceptance testing, reopen OBS with Source Dock enabled and check F1 while the pointer is inside and outside the dock, open and close dialogs, then check enter/leave, browser-source interaction, scrolling, and Ctrl-left dragging.

## Reproduce the Linux checks

Install a C++ compiler, CMake, Ninja, Qt 6 development/private headers and libobs development files. From the repository root:

```sh
cmake -S . -B build_linux -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build_linux --parallel 4
cmake -S tests/event-regression -B build_regression -G Ninja \
  -DSOURCE_DOCK_DIR="$PWD" -DCMAKE_BUILD_TYPE=Debug
cmake --build build_regression --parallel 4
ctest --test-dir build_regression --output-on-failure
```

Configure against an unpatched checkout with `-DLEGACY_HANDLER=ON` to reproduce the invalid cast. The diagnostic argument `--enter-only` isolates the Enter case. Use `QT_QPA_PLATFORM=offscreen`, `ASAN_OPTIONS=detect_leaks=0`, and `UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1` when running that executable directly.
