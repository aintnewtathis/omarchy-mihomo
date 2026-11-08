#!/usr/bin/env bash
# Run mihomo in the foreground as a plain proxy (no TUN, no root) for testing.
# It does not touch system routing or DNS: only apps pointed at
# 127.0.0.1:7890 go through it.
#
# Subscription url: $SUBSCRIPTION_URL, or the first line of $dev/subscription-url
# (dev = ~/.local/state/omarchy-mihomo/dev, kept outside the plugin folder so
# mihomo writing its cache does not hot-reload the bar widget).
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
dev=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-mihomo/dev
mkdir -p "$dev"

command -v mihomo >/dev/null || { echo "mihomo not found: yay -S mihomo-bin" >&2; exit 1; }
if systemctl is-active --quiet mihomo.service; then
  echo "mihomo.service is running and holds the same ports; stop it first: sudo systemctl stop mihomo" >&2
  exit 1
fi

url=${SUBSCRIPTION_URL:-}
if [[ -z $url && -f $dev/subscription-url ]]; then
  url=$(head -n1 "$dev/subscription-url")
fi
[[ -n $url ]] || { echo "set SUBSCRIPTION_URL or write it to $dev/subscription-url" >&2; exit 1; }

if [[ ! -f $dev/secret ]]; then
  (umask 077; head -c 24 /dev/urandom | base64 | tr -d '/+=' > "$dev/secret")
fi

"$root/scripts/render-config.sh" "$url" "$(cat "$dev/secret")" false "$dev/config.yaml"

# Where the bar plugin finds the controller.
ctl_dir=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-mihomo
mkdir -p "$ctl_dir"
(umask 077; printf '{"url": "http://127.0.0.1:9090", "secret": "%s"}\n' "$(cat "$dev/secret")" > "$ctl_dir/controller.json")
mihomo -d "$dev" -t >/dev/null || { mihomo -d "$dev" -t; exit 1; }
exec mihomo -d "$dev"
