#!/usr/bin/env python3
"""Generate a real Homebrew cask and checksums from final, stapled artifacts."""
import hashlib
import pathlib
import plistlib
import re
import sys

folder = pathlib.Path(sys.argv[1])
info = plistlib.loads(pathlib.Path(sys.argv[2]).read_bytes())
version = info['CFBundleShortVersionString']
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    raise SystemExit('Invalid release version')
dmg = folder / f'Couleur-{version}.dmg'
sha = hashlib.sha256(dmg.read_bytes()).hexdigest()
(folder / 'couleur.rb').write_text(f'''# Generated from the notarized release; do not edit the checksum manually.
cask "couleur" do
  version "{version}"
  sha256 "{sha}"

  url "https://github.com/Aymericr/couleur/releases/download/v#{{version}}/Couleur-#{{version}}.dmg"
  name "Couleur"
  desc "Floating color picker and palette library"
  homepage "https://aymeric.dev/couleur"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sonoma
  app "Couleur.app"
end
''')
names = [dmg.name, f'Couleur-{version}.zip', 'appcast.xml', 'couleur.rb']
(folder / 'SHA256SUMS').write_text(''.join(
    f'{hashlib.sha256((folder / name).read_bytes()).hexdigest()}  {name}\n' for name in names
))
