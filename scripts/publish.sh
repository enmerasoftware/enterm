#!/bin/zsh
# Puts a distributed build on GitHub: a release with the DMG and the appcast Sparkle reads.
# Usage: scripts/publish.sh build/dist-<commit>/Enterm-<version>.dmg ["release notes"]
# The appcast is signed with the Sparkle key in this Mac's Keychain (account "enterm").
set -e
root=${0:A:h:h}
repo=enmerasoftware/enterm
dmg=${1:A}
notes=${2:-""}
[[ -f "$dmg" ]] || { echo "DMG bulunamadı: $1" >&2; exit 1; }
version=${${dmg:t:r}#Enterm-}
tag="v$version"
# The release is tagged on the commit the DMG was built from: build/dist-<commit>.
folder=${dmg:h:t}
commit=$(git -C "$root" rev-parse "${folder#dist-}")
tools="$root/.build/artifacts/sparkle/Sparkle/bin"

work=$(mktemp -d)
cp "$dmg" "$work/"
[[ -n "$notes" ]] && print -r -- "$notes" > "$work/${dmg:t:r}.md"
# Every release ships its own appcast with only itself in it; latest/download always points to the newest.
"$tools/generate_appcast" --account enterm \
  --download-url-prefix "https://github.com/$repo/releases/download/$tag/" \
  --embed-release-notes \
  -o "$work/appcast.xml" "$work"

if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
  echo "$tag zaten yayında; sürüm numarasını Resources/Info.plist içinde artırın." >&2
  exit 1
fi
gh release create "$tag" "$work/${dmg:t}" "$work/appcast.xml" --repo "$repo" --target "$commit" \
  --title "Enterm $version" --notes "${notes:-Enterm $version}"
rm -rf "$work"
echo "https://github.com/$repo/releases/tag/$tag"
