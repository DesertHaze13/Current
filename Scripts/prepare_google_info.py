#!/usr/bin/env python3
"""Generate native Google callback registration from this target's Firebase plist."""
import plistlib
import sys
import shutil
from pathlib import Path


def make_info(config, bundle_id):
    client_id = config.get('CLIENT_ID', '')
    if not client_id or config.get('BUNDLE_ID') != bundle_id:
        return {}
    scheme = '.'.join(reversed(client_id.split('.')))
    return {'CFBundleURLTypes': [{'CFBundleURLName': 'Google Sign-In', 'CFBundleTypeRole': 'Editor', 'CFBundleURLSchemes': [scheme]}]}


if __name__ == '__main__':
    source, destination, bundle_id = sys.argv[1:]
    local = Path(source)
    if not local.exists():
        example = local.with_name('GoogleService-Info.example.plist')
        if example.exists():
            shutil.copy2(example, local)
    config = plistlib.loads(Path(source).read_bytes()) if Path(source).exists() else {}
    info = make_info(config, bundle_id)
    output = Path(destination)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(plistlib.dumps(info))
    print('Google profile callback configured.' if info else 'Google profile callback awaits target-specific Firebase configuration.')
