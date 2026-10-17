"""Launch an isolated OBS 32.0.4 and the test-only Source Dock build on macOS."""

import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import time
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('--plugin', type=Path, required=True)
parser.add_argument('--work', type=Path, required=True)
parser.add_argument('--source', choices=['color', 'browser'], default='browser')
args = parser.parse_args()
assert platform.system() == 'Darwin', 'Run this test on macOS, not through an offscreen substitute'
assert args.plugin.is_dir()
work = args.work.resolve()
work.mkdir(parents=True, exist_ok=True)
config = Path.home() / 'Library/Application Support/obs-studio'
if config.exists():
    raise SystemExit('Refusing to overwrite an existing OBS user configuration; use a fresh CI runner')

arch = 'Apple' if platform.machine() == 'arm64' else 'Intel'
dmg = work / 'obs.dmg'
url = f'https://github.com/obsproject/obs-studio/releases/download/32.0.4/OBS-Studio-32.0.4-macOS-{arch}.dmg'
urllib.request.urlretrieve(url, dmg)
mount = work / 'mount'
mount.mkdir(exist_ok=True)
subprocess.run(['hdiutil', 'attach', '-nobrowse', '-readonly', '-mountpoint', str(mount), str(dmg)], check=True)
try:
    app = work / 'OBS.app'
    subprocess.run(['ditto', str(mount / 'OBS.app'), str(app)], check=True)
finally:
    subprocess.run(['hdiutil', 'detach', str(mount)], check=True)

config.mkdir(parents=True)
# This is the same notice-only state written by OBS's Continue button. It does
# not grant camera, microphone, capture or accessibility permissions in macOS.
(config / 'global.ini').write_text('[General]\nLastVersion=536870916\nLicenseAccepted=true\nMacOSPermissionsDialogLastShown=1\n', encoding='utf-8')
(config / 'user.ini').write_text(
    '[General]\nFirstRun=true\nWarnedAboutClosingDocks=true\n'
    '[Basic]\nProfile=Stress\nProfileDir=Stress\nSceneCollection=Stress\nSceneCollectionFile=Stress\n'
    '[OBSWebSocket]\nServerEnabled=false\n', encoding='utf-8')
profile = config / 'basic/profiles/Stress'
profile.mkdir(parents=True)
(profile / 'basic.ini').write_text(
    '[General]\nName=Stress\n[Video]\nBaseCX=1280\nBaseCY=720\nOutputCX=1280\nOutputCY=720\n'
    'FPSType=0\nFPSCommon=30\n[Audio]\nSampleRate=48000\nChannelSetup=Stereo\n', encoding='utf-8')
scenes = config / 'basic/scenes'
scenes.mkdir(parents=True)
collection = {'name': 'Stress', 'current_scene': 'Scene', 'current_program_scene': 'Scene',
    'scene_order': [{'name': 'Scene'}], 'sources': [{'name': 'Scene', 'id': 'scene', 'versioned_id': 'scene', 'settings': {'items': []}}],
    'current_transition': 'Fade', 'transition_duration': 300}
for name in ('DesktopAudioDevice1', 'DesktopAudioDevice2', 'AuxAudioDevice1', 'AuxAudioDevice2', 'AuxAudioDevice3', 'AuxAudioDevice4'):
    collection[name] = None
(scenes / 'Stress.json').write_text(json.dumps(collection), encoding='utf-8')
plugins = config / 'plugins'
plugins.mkdir()
subprocess.run(['ditto', str(args.plugin.resolve()), str(plugins / 'source-dock.plugin')], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(plugins / 'source-dock.plugin')], check=True)

report = work / 'report.json'
env = os.environ.copy()
env['SOURCE_DOCK_STRESS_REPORT'] = str(report)
env['SOURCE_DOCK_STRESS_SOURCE'] = args.source
env['QT_QPA_PLATFORM'] = 'cocoa'
with (work / 'obs-console.log').open('wb') as console:
    process = subprocess.Popen([str(app / 'Contents/MacOS/obs'), '--multi', '--disable-updater',
        '--disable-missing-files-check', '--profile', 'Stress', '--collection', 'Stress'],
        cwd=app / 'Contents/MacOS', env=env, stdout=console, stderr=subprocess.STDOUT)
    # Native CI timers can be coalesced; allow the full 200 cycles to finish.
    # The driver's separate ten-minute limit still detects a stalled run.
    deadline = time.monotonic() + 660
    while not report.exists() and process.poll() is None and time.monotonic() < deadline:
        time.sleep(1)
    if not report.exists():
        subprocess.run(['sample', str(process.pid), '3', '-file', str(work / 'timeout-sample.txt')], check=False)
        report.write_text(json.dumps({'success': False, 'reason': 'OBS exited or timed out before producing a stress report',
            'process_returncode': process.poll(), 'architecture': platform.machine()}, indent=2), encoding='utf-8')
    try:
        process.wait(timeout=20)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
if (config / 'logs').exists():
    shutil.copytree(config / 'logs', work / 'obs-logs', dirs_exist_ok=True)
result = json.loads(report.read_text(encoding='utf-8'))
print(json.dumps(result, indent=2))
if not result.get('success'):
    raise SystemExit(1)
