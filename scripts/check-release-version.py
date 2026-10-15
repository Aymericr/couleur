#!/usr/bin/env python3
"""Reject duplicate/downgrade build numbers before spending time notarizing."""
import plistlib
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

info = plistlib.loads(Path('Resources/Info.plist').read_bytes())
request = urllib.request.Request(info['SUFeedURL'], headers={'User-Agent': 'Couleur release validation'})
try:
    with urllib.request.urlopen(request, timeout=20) as response:
        feed = ET.fromstring(response.read())
except urllib.error.HTTPError as error:
    if error.code != 404:
        raise SystemExit(f'Cannot validate the previous release (HTTP {error.code}). Retry later.')
    print('No previous public update feed; preparing the first release.')
else:
    versions = [item.text for item in feed.iter('{http://www.andymatuschak.org/xml-namespaces/sparkle}version')]
    if not versions or any(not value or not value.isdecimal() for value in versions):
        raise SystemExit('Previous feed has unsupported build numbers. Inspect before releasing.')
    if int(info['CFBundleVersion']) <= max(map(int, versions)):
        raise SystemExit('Increment CFBundleVersion beyond the latest public build before releasing.')
    print('Build number is greater than the current public release.')
