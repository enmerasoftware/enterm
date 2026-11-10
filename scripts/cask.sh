#!/bin/zsh
# Writes the Homebrew cask for a published DMG. Usage: scripts/cask.sh build/dist-<commit>/Enterm-<version>.dmg
# Copy the result into the tap repository (enmerasoftware/homebrew-tap, Casks/enterm.rb) and push it there.
# Then: brew install --cask enmerasoftware/tap/enterm
set -e
root=${0:A:h:h}
dmg=${1:A}
[[ -f "$dmg" ]] || { echo "DMG bulunamadı: $1" >&2; exit 1; }
version=${${dmg:t:r}#Enterm-}
sha=$(shasum -a 256 "$dmg" | awk '{ print $1 }')
sed -e "s/@VERSION@/$version/" -e "s/@SHA256@/$sha/" "$root/packaging/homebrew/enterm.rb.in" > "$root/packaging/homebrew/enterm.rb"
echo "$root/packaging/homebrew/enterm.rb"
