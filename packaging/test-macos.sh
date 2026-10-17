#!/bin/bash
set -euo pipefail
package_dir="$1"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/source-dock-installer-test.XXXXXX")
cleanup() {
    if [[ "$test_root" == "${TMPDIR:-/tmp}"/source-dock-installer-test.* ]]; then rm -rf -- "$test_root"; fi
}
trap cleanup EXIT
plugin_dir="$test_root/plugins with spaces"
/bin/bash "$package_dir/install.sh" --plugin-dir "$plugin_dir" --no-pause
codesign --verify --deep --strict "$plugin_dir/source-dock.plugin"
cmp "$package_dir/source-dock.plugin/Contents/MacOS/source-dock" "$plugin_dir/source-dock.plugin/Contents/MacOS/source-dock"
/bin/bash "$package_dir/install.sh" --plugin-dir "$plugin_dir" --no-pause
codesign --verify --deep --strict "$plugin_dir/source-dock.plugin"

# Emulate a downloaded bundle with quarantine on directories and nested files.
source_plugin="$package_dir/source-dock.plugin"
quarantine='0081;00000000;SourceDockInstallerTest;'
for path in "$source_plugin" "$source_plugin/Contents" "$source_plugin/Contents/Info.plist" "$source_plugin/Contents/MacOS/source-dock"; do
    /usr/bin/xattr -w com.apple.quarantine "$quarantine" "$path"
done
/usr/bin/xattr -w com.source-dock.installer-test preserve-me "$source_plugin/Contents/MacOS/source-dock"
unrelated="$test_root/unrelated.txt"
printf 'Outside the installed plugin\n' > "$unrelated"
/usr/bin/xattr -w com.apple.quarantine "$quarantine" "$unrelated"

for attempt in 1 2; do
    /bin/bash "$package_dir/install.sh" --plugin-dir "$plugin_dir" --no-pause
    codesign --verify --deep --strict "$plugin_dir/source-dock.plugin"
    cmp "$source_plugin/Contents/MacOS/source-dock" "$plugin_dir/source-dock.plugin/Contents/MacOS/source-dock"
    python3 - "$plugin_dir/source-dock.plugin" "$source_plugin" "$unrelated" <<'PY'
from pathlib import Path
import subprocess
import sys

installed, source, unrelated = map(Path, sys.argv[1:])
for path in [installed, *installed.rglob('*')]:
    attributes = subprocess.check_output(['/usr/bin/xattr', str(path)], text=True).splitlines()
    assert 'com.apple.quarantine' not in attributes, path
def read_attribute(path, name):
    return subprocess.check_output(['/usr/bin/xattr', '-p', name, str(path)]).rstrip(b'\n')
assert read_attribute(installed / 'Contents/MacOS/source-dock', 'com.source-dock.installer-test') == b'preserve-me'
assert read_attribute(source, 'com.apple.quarantine')
assert read_attribute(unrelated, 'com.apple.quarantine')
print('PASS: recursive quarantine removal, other metadata preserved, source and unrelated file unchanged.')
PY
done

# Reject a damaged package before touching a working installation.
damaged_package="$test_root/damaged package"
mkdir -p "$damaged_package"
ditto "$source_plugin" "$damaged_package/source-dock.plugin"
cp "$package_dir/install.sh" "$damaged_package/install.sh"
printf 'damaged executable\n' >> "$damaged_package/source-dock.plugin/Contents/MacOS/source-dock"
if /bin/bash "$damaged_package/install.sh" --plugin-dir "$plugin_dir" --no-pause; then
    printf 'A damaged package was incorrectly accepted.\n' >&2
    exit 1
fi
codesign --verify --deep --strict "$plugin_dir/source-dock.plugin"
cmp "$source_plugin/Contents/MacOS/source-dock" "$plugin_dir/source-dock.plugin/Contents/MacOS/source-dock"

if find "$plugin_dir" -name '.source-dock-install.*' | grep -q .; then
    printf 'Unexpected staging directory remains.\n' >&2
    exit 1
fi
printf 'PASS: macOS clean and quarantined installs, repeat installs, binary identity, signature and paths with spaces.\n'
