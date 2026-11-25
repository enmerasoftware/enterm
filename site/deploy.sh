#!/usr/bin/env bash
# Puts enterm.enmeraapps.com (site + Library server) on Enmera's server and runs install.sh there as root.
# Usage: site/deploy.sh      (SSH key: ~/.ssh/enmera_server)
# Server details are not kept in the repository; they are read from ~/.config/enterm/site.env
# (or, on the same server, ~/.config/couchsubs/site.env): SITE_HOST=user@server  SITE_PORT=ssh-port
set -euo pipefail
cd "$(dirname "$0")"
ENV_FILE="${ENTERM_SITE_ENV:-$HOME/.config/enterm/site.env}"
[[ -f "$ENV_FILE" ]] || ENV_FILE="$HOME/.config/couchsubs/site.env"
[[ -f "$ENV_FILE" ]] || { echo "Sunucu ayar dosyası yok: ~/.config/enterm/site.env (SITE_HOST, SITE_PORT)." >&2; exit 1; }
# shellcheck source=/dev/null
source "$ENV_FILE"
: "${SITE_HOST:?SITE_HOST yok}" "${SITE_PORT:?SITE_PORT yok}"
KEY="$HOME/.ssh/enmera_server"
[[ -f public/index.html ]] || { echo "public/index.html yok." >&2; exit 1; }
node --test server.test.mjs >/dev/null || { echo "Sunucu testleri geçmedi; yüklenmedi." >&2; exit 1; }
SSH="ssh -i $KEY -p $SITE_PORT"
$SSH "$SITE_HOST" 'mkdir -p ~/enterm-web-staging'
# -L: rules.mjs and TAGS.md are links into library/ here; the server gets the files.
rsync -rLptz --delete --exclude .DS_Store --exclude .data -e "$SSH" \
  public server.mjs rules.mjs TAGS.md admin.html install.sh "$SITE_HOST:enterm-web-staging/"
$SSH "$SITE_HOST" 'if [ "$(id -u)" = 0 ]; then bash ~/enterm-web-staging/install.sh; else sudo bash ~/enterm-web-staging/install.sh; fi'
curl -fsS https://enterm.enmeraapps.com/health >/dev/null && echo "Yayında: https://enterm.enmeraapps.com"
