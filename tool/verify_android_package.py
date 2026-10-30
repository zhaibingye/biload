"""Static checks of the delivered arm64 APK, including all ELF LOAD segments."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('apk', type=Path)
parser.add_argument('--build-tools', type=Path, required=True)
parser.add_argument('--unsigned', action='store_true')
parser.add_argument('--certificate')
parser.add_argument('--report', type=Path, required=True)
args = parser.parse_args()
suffix = '.exe' if (args.build_tools / 'aapt.exe').exists() else ''

def run(name, *options):
    tool = args.build_tools / (name + suffix)
    if name == 'apksigner' and suffix:
        tool = args.build_tools / 'apksigner.bat'
    return subprocess.check_output([str(tool), *map(str, options)], text=True,
                                   encoding='utf-8', errors='replace')

badging = run('aapt', 'dump', 'badging', args.apk)
assert "package: name='app.biload.biload'" in badging, 'Wrong production package'
version = re.search(r'^version:\s*(\S+)',
                    (Path(__file__).resolve().parents[1] / 'pubspec.yaml').read_text(encoding='utf-8'),
                    re.MULTILINE).group(1)
version_name, version_code = version.split('+')
assert f"versionName='{version_name}'" in badging, 'Wrong release version'
# Flutter adds 1000 * ABI code (2 for arm64) to split APK build numbers.
android_version_code = 2000 + int(version_code)
assert f"versionCode='{android_version_code}'" in badging, 'Wrong release build number'
assert "sdkVersion:'26'" in badging, 'Minimum Android version changed'
assert "targetSdkVersion:'36'" in badging, 'Unexpected target Android version'
assert "native-code: 'arm64-v8a'" in badging, 'Unexpected APK architecture'
run('zipalign', '-c', '-P', '16', '-v', '4', args.apk)
libraries = []
with zipfile.ZipFile(args.apk) as archive:
    assert 'assets/flutter_assets/LICENSE' in archive.namelist()
    assert 'assets/flutter_assets/THIRD_PARTY_NOTICES.md' in archive.namelist()
    for name in archive.namelist():
        if not name.startswith('lib/') or not name.endswith('.so'):
            continue
        assert name.startswith('lib/arm64-v8a/'), name
        data = archive.read(name)
        assert data[:6] == b'\x7fELF\x02\x01', name
        offset = struct.unpack_from('<Q', data, 32)[0]
        size, count = struct.unpack_from('<HH', data, 54)
        alignments = []
        for index in range(count):
            entry = offset + size * index
            if struct.unpack_from('<I', data, entry)[0] != 1:
                continue
            alignment = struct.unpack_from('<Q', data, entry + 48)[0]
            assert alignment >= 16384, f'{name}: incompatible ELF alignment'
            alignments.append(hex(alignment))
        assert alignments, name
        libraries.append({'name': name, 'loadAlignments': alignments})
assert len(libraries) >= 10, 'Native libraries are missing'
certificate = None
if not args.unsigned:
    signature = run('apksigner', 'verify', '--verbose', '--print-certs', args.apk)
    match = re.search(r'Signer #1 certificate SHA-256 digest: (\w+)', signature)
    assert match, 'No verified signing certificate'
    certificate = match[1].lower()
    if args.certificate:
        assert certificate == args.certificate.lower(), 'Signing certificate changed'
digest = hashlib.sha256()
with args.apk.open('rb') as source:
    for chunk in iter(lambda: source.read(1024 * 1024), b''):
        digest.update(chunk)
report = {
    'version': version,
    'androidVersionCode': android_version_code,
    'file': args.apk.name,
    'sizeBytes': args.apk.stat().st_size,
    'sha256': digest.hexdigest(),
    'signed': not args.unsigned,
    'certificateSha256': certificate,
    'minSdk': 26,
    'targetSdk': 36,
    'abi': 'arm64-v8a',
    'zipAlignment16KB': True,
    'elfLibraries': libraries,
    'deviceTesting': False,
}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2), encoding='utf-8')
print(f'APK static verification passed: {len(libraries)} arm64 libraries')
