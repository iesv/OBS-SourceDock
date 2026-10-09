# Source Dock plugin for OBS Studio

Plugin for OBS Studio to add docks.

# Source Dock 0.5.1-1 fix

This fork fixes an invalid Qt event cast associated with the reported F1 crash in Source Dock. Download the Windows x64 and macOS Universal packages from the [0.5.1-1 release](https://github.com/iesv/OBS-SourceDock/releases/tag/0.5.1-1).

See [the fix and installation guide](FIX-0.5.1-1.md) for the cause, validation results, and OBS Studio 32 installation instructions. The [release notes](RELEASE-NOTES-0.5.1-1.md) summarize this revision.

# Download

https://obsproject.com/forum/resources/source-dock.1317/

# Build
- Build OBS Studio: https://obsproject.com/wiki/Install-Instructions
- Check out this repository to UI/frontend-plugins/source-dock
- Add `add_subdirectory(source-dock)` to UI/frontend-plugins/CMakeLists.txt
- Rebuild OBS Studio

# Donations
https://www.paypal.me/exeldro
