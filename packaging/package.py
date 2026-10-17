"""Create the two release ZIPs from native build output or existing packages."""

import argparse
import json
from pathlib import Path
import stat
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('platform', choices=['windows', 'macos'])
parser.add_argument('--payload', type=Path, required=True)
parser.add_argument('--output', type=Path, help='ZIP path inside the source tree dist directory')
args = parser.parse_args()
source_dir = Path(__file__).resolve().parent
project_dir = source_dir.parent.resolve()
dist_dir = project_dir / 'dist'
if dist_dir.resolve() != dist_dir:
    parser.error('dist must be a directory inside the source tree, not a link')
version = json.loads((project_dir / 'buildspec.json').read_text(encoding='utf-8'))['version']
suffix = 'windows-x64' if args.platform == 'windows' else 'macos-universal'
if args.output is None:
    args.output = dist_dir / f'source-dock-{version}-{suffix}.zip'
if args.output.resolve().parent != dist_dir:
    parser.error('ZIP output must be directly inside the source tree dist directory')
if not args.payload.exists():
    parser.error('The native build payload does not exist')
if args.output.resolve() == args.payload.resolve():
    parser.error('Payload and output must be different files')
args.output.parent.mkdir(parents=True, exist_ok=True)

def add_script(archive, path, name, executable=False):
    info = zipfile.ZipInfo(name)
    info.create_system = 3
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = (stat.S_IFREG | (0o755 if executable else 0o644)) << 16
    data = path.read_bytes().replace(b'\r\n', b'\n')
    if name.endswith(('.cmd', '.bat')):
        data = data.replace(b'\n', b'\r\n')
    archive.writestr(info, data)

with zipfile.ZipFile(args.output, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    if args.payload.is_file():
        with zipfile.ZipFile(args.payload) as previous:
            for entry in previous.infolist():
                if entry.filename.endswith('.pdb'):
                    continue
                if entry.filename.startswith(('source-dock/', 'source-dock.plugin/', '__MACOSX/')):
                    archive.writestr(entry, previous.read(entry.filename))
    else:
        for path in sorted(args.payload.rglob('*')):
            if path.is_file() and path.suffix != '.pdb':
                archive.write(path, 'source-dock' + ('.plugin' if args.platform == 'macos' else '') + '/' + path.relative_to(args.payload).as_posix())
    if args.platform == 'windows':
        add_script(archive, source_dir / 'windows/install.bat', 'install.bat')
    else:
        add_script(archive, source_dir / 'macos/install.sh', 'install.sh', executable=True)

with zipfile.ZipFile(args.output) as archive:
    assert archive.testzip() is None
    required = 'source-dock/bin/64bit/source-dock.dll' if args.platform == 'windows' else 'source-dock.plugin/Contents/MacOS/source-dock'
    assert required in archive.namelist(), required
print(args.output)
