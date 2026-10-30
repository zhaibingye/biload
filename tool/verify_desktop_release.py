"""Run the actual packaged executable against isolated original media fixtures."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('--executable', required=True)
parser.add_argument('--report-dir', default='artifacts/runtime')
args = parser.parse_args()
executable = Path(args.executable).resolve(strict=True)
reports = Path(args.report_dir).resolve()
reports.mkdir(parents=True, exist_ok=True)
port_file = reports / 'fixture-port.txt'
port_file.unlink(missing_ok=True)
server_log = (reports / 'fixture-server.log').open('w', encoding='utf-8')
server = subprocess.Popen([
    sys.executable, str(Path(__file__).with_name('runtime_fixture_server.py')),
    '--port', '0', '--port-file', str(port_file),
], stdout=server_log, stderr=subprocess.STDOUT, text=True)
app = None
try:
    deadline = time.monotonic() + 30
    while not port_file.exists():
        if server.poll() is not None or time.monotonic() > deadline:
            server_log.flush()
            print((reports / 'fixture-server.log').read_text(encoding='utf-8'))
            raise RuntimeError(f'Fixture server did not start (exit {server.poll()})')
        time.sleep(0.1)
    port = int(port_file.read_text(encoding='utf-8'))
    environment = os.environ | {
        'BILOAD_VERIFY_RELEASE': '1',
        'BILOAD_VERIFY_ID': f'ci-{uuid.uuid4().hex}',
        'BILOAD_VERIFY_BASE_URL': f'http://127.0.0.1:{port}/',
    }
    app = subprocess.Popen([str(executable)], env=environment,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, encoding='utf-8', errors='replace')
    try:
        output, _ = app.communicate(timeout=480)
    except subprocess.TimeoutExpired:
        app.kill()
        output, _ = app.communicate()
        (reports / 'runtime.log').write_text(output, encoding='utf-8')
        raise RuntimeError('Packaged application exceeded the runtime deadline')
    (reports / 'runtime.log').write_text(output, encoding='utf-8')
    print(output[-16000:])
    paths = [line.split('BILOAD_RELEASE_REPORT=', 1)[1].strip()
             for line in output.splitlines() if 'BILOAD_RELEASE_REPORT=' in line]
    if not paths:
        raise RuntimeError(f'No application report (exit {app.returncode})')
    source = Path(paths[-1])
    if not source.is_file():
        raise RuntimeError('Application stopped before writing its report')
    shutil.copy2(source, reports / 'report.json')
    screenshot = source.with_name('parsed-ui.png')
    if screenshot.is_file():
        shutil.copy2(screenshot, reports / 'parsed-ui.png')
    report = json.loads(source.read_text(encoding='utf-8'))
    print(json.dumps(report, indent=2, ensure_ascii=False))
    if app.returncode != 0 or report.get('passed') is not True:
        raise RuntimeError('Packaged runtime verification failed')
    required = {'sqlite', 'os-credential-vault', 'ui-and-default-selection', 'rendered-ui',
                'AVC-AAC', 'HEVC-AAC', 'AV1-AAC',
                'multi-audio-AAC-FLAC-EAC3', 'audio-only-30280',
                'audio-only-30251', 'audio-only-30250', 'pause-resume',
                'http-range-resume', 'no-flutter-errors',
                'webview-post-and-httpOnly-cookie'}
    if not required.issubset(report.get('checks', [])):
        raise RuntimeError('Application report is missing required checks')
finally:
    if app is not None and app.poll() is None:
        app.kill()
        app.wait()
    server.terminate()
    server.wait(timeout=10)
    server_log.close()
