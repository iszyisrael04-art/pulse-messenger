"""Build Windows and preserve the underlying installer failure for CI diagnosis."""
from pathlib import Path
import shutil
import subprocess
import sys
import os


def run_logged(command, destination, cwd):
    with destination.open('w', encoding='utf-8') as log:
        result = subprocess.run(command, cwd=cwd, stdout=log, stderr=subprocess.STDOUT, check=False)
    text = destination.read_text(encoding='utf-8', errors='replace')
    # Keep the file intact; escape unsupported symbols only for the console.
    encoding = getattr(sys.stdout, 'encoding', None) or 'utf-8'
    printable = text.encode(encoding, errors='backslashreplace').decode(encoding)
    print(printable, flush=True)
    return result.returncode


def build(root):
    flutter = shutil.which('flutter')
    if flutter is None:
        print('Flutter was not found on PATH.', flush=True)
        return 127
    # Crown snapshots must not use the old busy-spin/leaking capturer.
    if os.name == 'nt' and (root / '.dart_tool/package_config.json').exists():
        subprocess.run([sys.executable, str(Path(__file__).with_name('patch_webrtc_capture.py')), str(root)], check=True)
    logs = root / 'build-logs'
    logs.mkdir(exist_ok=True)
    code = run_logged([
        flutter, 'build', 'windows', '--release',
        '--dart-define-from-file=config.example.json', '--verbose',
        *(['--dart-define=PULSE_STAFF=true'] if os.environ.get('PULSE_STAFF_APP') == '1' else []),
    ], logs / 'windows-build.log', root)
    # Preserve the original failure even if a diagnostic install happens to pass.
    # This reruns generated local bundle installation only; it does not publish.
    if code != 0:
        cmake = shutil.which('cmake')
        output = root / 'build/windows/x64'
        if cmake is not None and (output / 'cmake_install.cmake').exists():
            print('Capturing the generated CMake install output.', flush=True)
            run_logged([
                cmake, '--install', str(output), '--config', 'Release', '--verbose',
            ], logs / 'windows-install.log', root)
    return code


if __name__ == '__main__':
    raise SystemExit(build(Path(__file__).resolve().parents[1]))
