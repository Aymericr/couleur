#!/bin/bash
# An isolated, disposable app for visual and interaction checks.
set -euo pipefail
cd "$(dirname "$0")/.."
appearance="${1:-light}"
if [[ "$appearance" != light && "$appearance" != dark ]]; then
  echo "Usage: scripts/preview.sh [light|dark]" >&2
  exit 1
fi
./scripts/build.sh debug
preview_app="build/Couleur Preview.app"
ditto build/Couleur.app "$preview_app"
python3 - "$appearance" <<'PY'
import datetime, json, pathlib, plistlib, sys, uuid
root = pathlib.Path.cwd()
folder = root / 'build/preview-data'
folder.mkdir(parents=True, exist_ok=True)
colors = [('Porcelain', '#FAFAFA'), ('Ink', '#242424'), ('Wisteria', '#9D8DF1'),
          ('Terracotta', '#DB7A58'), ('Sage', '#A8B39E'), ('Rose', '#D4A4AA')]
if not (folder / 'library.json').exists():
    records = []
    for i, (name, code) in enumerate(colors):
        date = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=i)).strftime('%Y-%m-%dT%H:%M:%SZ')
        value = {k: int(code[j:j+2],16)/255 for k,j in [('red',1),('green',3),('blue',5)]}
        records.append(dict(id=str(uuid.uuid4()).upper(), name=name, value=dict(value,alpha=1),
                            createdAt=date, updatedAt=date, favorite=False, notes='', sourceURL='',
                            source=dict(method='Design preview')))
    (folder / 'library.json').write_text(json.dumps(dict(version=1, colors=records, collections=[])))
p = root / 'build/Couleur Preview.app/Contents/Info.plist'
info = plistlib.loads(p.read_bytes())
info.update(CFBundleIdentifier='com.aymeric.couleur.preview', CFBundleName='Couleur Preview',
            CFBundleDisplayName='Couleur Preview', CouleurPreviewDirectory=str(folder),
            CouleurPreviewAppearance=sys.argv[1])
p.write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - --identifier com.aymeric.couleur.preview "$preview_app"
echo "Preview ready: $PWD/$preview_app ($appearance)"
