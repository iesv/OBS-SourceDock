#!/bin/bash

pause_before_exit() {
    local seconds key
    for seconds in 5 4 3 2 1; do
        printf '\rClosing in %s seconds. Press any key to exit... ' "$seconds"
        if [[ -t 0 ]]; then
            if IFS= read -r -s -n 1 -t 1 key; then break; fi
        else
            sleep 1
        fi
    done
    printf '\n'
}

install_source_dock() {
    local package_dir="$1" plugins_dir="$2" source_plugin target_plugin
    source_plugin="$package_dir/source-dock.plugin"
    target_plugin="$plugins_dir/source-dock.plugin"
    if pgrep -x OBS >/dev/null 2>&1 || pgrep -x obs >/dev/null 2>&1; then
        printf 'Close OBS Studio before installing Source Dock.\n' >&2
        return 1
    fi
    if [[ ! -f "$source_plugin/Contents/MacOS/source-dock" ]]; then
        printf 'Plugin files are missing. Extract the complete ZIP first.\n' >&2
        return 1
    fi
    codesign --verify --deep --strict "$source_plugin"
    mkdir -p "$plugins_dir"
    installation_stage=$(mktemp -d "$plugins_dir/.source-dock-install.XXXXXX")
    ditto "$source_plugin" "$installation_stage/source-dock.plugin"
    if ! /usr/bin/xattr -dr com.apple.quarantine "$installation_stage/source-dock.plugin"; then
        printf 'Could not remove the plugin quarantine attribute. Installation was cancelled.\n' >&2
        return 1
    fi
    codesign --verify --deep --strict "$installation_stage/source-dock.plugin"
    if [[ -e "$target_plugin" ]]; then
        mv "$target_plugin" "$installation_stage/previous.plugin"
    fi
    mv "$installation_stage/source-dock.plugin" "$target_plugin"
    installation_succeeded=1
    printf 'Source Dock 0.5.1-2 installed successfully.\nPlugin: %s\nPlugin quarantine attribute removed.\nYou can now open OBS Studio.\n' "$target_plugin"
}

# Sourcing the script exposes the countdown for terminal verification only.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then return 0; fi

set -euo pipefail
package_dir=$(cd -- "$(dirname -- "$0")" && pwd)
plugins_dir="$HOME/Library/Application Support/obs-studio/plugins"
no_pause=0
installation_stage=''
installation_succeeded=0

finish_installation() {
    local status=$?
    trap - EXIT
    if [[ -n "$installation_stage" && "$installation_stage" == "$plugins_dir"/.source-dock-install.* ]]; then
        if [[ "$installation_succeeded" -eq 0 && -d "$installation_stage/previous.plugin" ]]; then
            if ! mv "$installation_stage/previous.plugin" "$plugins_dir/source-dock.plugin"; then
                printf 'Restore failed; the previous plugin is saved in: %s/previous.plugin\n' "$installation_stage" >&2
                status=1
                installation_stage=''
            fi
        fi
        if [[ -n "$installation_stage" ]]; then rm -rf -- "$installation_stage" || status=1; fi
    fi
    if [[ "$status" -ne 0 ]]; then printf '\nInstallation failed (exit code %s).\n' "$status" >&2; fi
    if [[ "$no_pause" -eq 0 ]]; then pause_before_exit; fi
    exit "$status"
}
trap finish_installation EXIT

while [[ $# -gt 0 ]]; do
    case "$1" in
        --plugin-dir)
            if [[ $# -lt 2 || -z "$2" ]]; then printf 'Missing plugin directory.\n' >&2; exit 1; fi
            plugins_dir="$2"
            shift 2
            ;;
        --no-pause) no_pause=1; shift ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; exit 1 ;;
    esac
done
if [[ "$(uname -s)" != Darwin ]]; then printf 'This installer requires macOS.\n' >&2; exit 1; fi
install_source_dock "$package_dir" "$plugins_dir"
