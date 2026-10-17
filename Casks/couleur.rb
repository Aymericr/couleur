# Generated from the notarized release; do not edit the checksum manually.
cask "couleur" do
  version "1.0.0"
  sha256 "83e662e9dc10855062269d114b8226bbf6ee833e03e6b3ab3fb53763fdd46044"

  url "https://github.com/Aymericr/couleur/releases/download/v#{version}/Couleur-#{version}.dmg"
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
