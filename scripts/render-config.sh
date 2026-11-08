#!/usr/bin/env bash
# Render config/config.template.yaml into a mihomo config.
# usage: render-config.sh <subscription-url> <secret> <tun:true|false> <out-file>
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $(basename "$0") <subscription-url> <secret> <tun:true|false> <out-file>" >&2
  exit 2
fi

url=$1 secret=$2 tun=$3 out=$4
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

[[ $url =~ ^https?://[^[:space:]\"]+$ ]] || { echo "bad subscription url" >&2; exit 1; }
[[ $secret =~ ^[A-Za-z0-9_-]+$ ]] || { echo "secret must be [A-Za-z0-9_-]" >&2; exit 1; }
[[ $tun == true || $tun == false ]] || { echo "tun must be true or false" >&2; exit 1; }

# Write through a temp file with tight permissions: the result holds the
# subscription url (a credential) and the controller secret.
tmp=$(mktemp "${out}.XXXXXX")
trap 'rm -f "$tmp"' EXIT
chmod 600 "$tmp"
URL=$url SECRET=$secret TUN=$tun awk '
  { gsub(/__SUBSCRIPTION_URL__/, ENVIRON["URL"])
    gsub(/__SECRET__/, ENVIRON["SECRET"])
    gsub(/__TUN_ENABLE__/, ENVIRON["TUN"])
    print }
' "$root/config/config.template.yaml" > "$tmp"
mv "$tmp" "$out"
trap - EXIT
