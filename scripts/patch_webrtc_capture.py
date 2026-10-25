"""Backport the upstream Windows capture timeout/buffer ownership fix.
Only the reviewed 1.6.2+hotfix.4 implementation is replaced. Already fixed
sources remain unchanged. This runs after pub get, before Windows compilation.
"""
import json
from pathlib import Path
import re
import shutil
import sys
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname


def patch(root):
    root = Path(root).resolve()
    config = root / '.dart_tool/package_config.json'
    packages = json.loads(config.read_text(encoding='utf-8'))['packages']
    package = next(p for p in packages if p['name'] == 'flutter_webrtc')
    uri = urlparse(urljoin(config.as_uri(), package['rootUri']))
    if uri.scheme != 'file': raise RuntimeError('Expected a local resolved WebRTC package')
    plugin = Path(url2pathname(uri.path))
    source = plugin / 'common/cpp/src/flutter_frame_capturer.cc'
    header = plugin / 'common/cpp/include/flutter_frame_capturer.h'
    old = source.read_text(encoding='utf-8')
    if 'frame_ready_.wait_for' in old and 'std::vector<uint8_t>' in old:
        return False
    version = re.search(r'^version:\s*(\S+)', (plugin / 'pubspec.yaml').read_text(encoding='utf-8'), re.M)
    if version is None or version[1] != '1.6.2+hotfix.4':
        raise RuntimeError('Review Windows snapshot implementation for the new WebRTC version')
    if 'while(!catch_frame_)' not in old or 'new uint8_t[' not in old or 'catch_frame_' not in header.read_text(encoding='utf-8'):
        raise RuntimeError('WebRTC snapshot implementation changed; refusing an unreviewed replacement')
    vendor = Path(__file__).resolve().parents[1] / 'native/webrtc'
    shutil.copyfile(vendor / source.name, source)
    shutil.copyfile(vendor / header.name, header)
    print('Applied upstream bounded snapshot wait and RAII buffer fix.')
    return True

if __name__ == '__main__':
    patch(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1])
