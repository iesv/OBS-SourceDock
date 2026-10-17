"""Exercise the actual installer countdown, including a terminal keypress."""
import argparse
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('platform', choices=['windows', 'macos'])
parser.add_argument('installer', type=Path)
args = parser.parse_args()

with tempfile.TemporaryDirectory(prefix='source-dock-countdown-') as directory:
    if args.platform == 'windows':
        # A BAT without its payload must fail before writing an installation,
        # then run the real launcher's completion countdown and return code 1.
        installer = Path(directory) / 'install.bat'
        shutil.copyfile(args.installer, installer)
        command = '"' + os.environ['COMSPEC'] + '" /d /s /c ""' + str(installer) + '""'
    else:
        command = ['/bin/bash', '-c', 'source "$1"; pause_before_exit', 'countdown', str(args.installer.resolve())]
    started = time.monotonic()
    result = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True, timeout=15)
    duration = time.monotonic() - started
    assert result.returncode == (1 if args.platform == 'windows' else 0), result.stderr
    assert 4.8 <= duration < 14, duration
    assert b'Closing in 5 seconds' in result.stdout and b'Closing in 1 seconds' in result.stdout
    print(f'PASS: automatic five-second countdown ({duration:.2f}s).')

    if os.name != 'nt':
        import errno
        import pty
        import select
        master, slave = pty.openpty()
        started = time.monotonic()
        process = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
        os.close(slave)
        output = b''
        sent = False
        try:
            while time.monotonic() - started < 5:
                readable, _, _ = select.select([master], [], [], 0.1)
                if readable:
                    try:
                        data = os.read(master, 4096)
                    except OSError as error:
                        if error.errno == errno.EIO: break
                        raise
                    if not data: break
                    output += data
                    if b'Press any key' in output and not sent:
                        os.write(master, b'q')
                        sent = True
                if process.poll() is not None: break
            process.wait(timeout=1)
            assert sent and process.returncode == 0 and time.monotonic() - started < 4, output
            print('PASS: terminal keypress exits before the countdown finishes.')
        finally:
            if process.poll() is None: process.kill()
            os.close(master)
