#!/usr/bin/env bash
# Set mihomo up as the system service the bar panel drives:
#   /etc/mihomo/config.yaml   rendered from config/config.template.yaml (root, 600)
#   mihomo.service            enabled, restarted with the new config
#   ~/.config/omarchy-mihomo/controller.json   url + secret for the panel
#
# usage: ./install.sh [subscription-url]
# Re-running keeps the saved subscription url and secret unless a new url
# is given, so it is also how you apply template changes.
set -euo pipefail

fail() { echo "install.sh: $*" >&2; exit 1; }

if [[ $EUID -ne 0 ]]; then
  exec sudo -- "$0" "$@"
fi

user=${SUDO_USER:-}
[[ -n $user && $user != root ]] || fail "run it as your user (it asks for sudo itself), not as root"
home=$(getent passwd "$user" | cut -d: -f6)
group=$(id -gn "$user")
root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
etc=/etc/mihomo
service=mihomo.service

command -v mihomo >/dev/null || fail "mihomo is not installed: yay -S mihomo-bin"
systemctl cat "$service" >/dev/null 2>&1 || fail "$service not found (the mihomo-bin package ships it)"

install -d -m 755 "$etc"

# Subscription url: argument, else the saved one, else ask.
url=${1:-}
if [[ -z $url && -s $etc/subscription-url ]]; then
  url=$(head -n1 "$etc/subscription-url")
  echo "Using the saved subscription url."
fi
if [[ -z $url ]]; then
  read -rp "Subscription url (Clash/mihomo format): " url
fi
[[ $url =~ ^https?://[^[:space:]\"]+$ ]] || fail "that does not look like a subscription url"
(umask 077; printf '%s\n' "$url" > "$etc/subscription-url")

# Controller secret: keep the existing one so the panel stays paired.
if [[ ! -s $etc/controller-secret ]]; then
  (umask 077; head -c 24 /dev/urandom | base64 | tr -d '/+=' > "$etc/controller-secret")
fi
secret=$(cat "$etc/controller-secret")

# Keep a config we did not write, once.
if [[ -f $etc/config.yaml ]] && ! grep -q managed-by-omarchy-mihomo "$etc/config.yaml"; then
  cp -p "$etc/config.yaml" "$etc/config.yaml.orig"
  echo "Saved the previous config as $etc/config.yaml.orig"
fi

# TUN starts off at boot; the panel turns it on and remembers your choice.
"$root/scripts/render-config.sh" "$url" "$secret" false "$etc/config.yaml.new"
if ! mihomo -d "$etc" -f "$etc/config.yaml.new" -t >/dev/null 2>&1; then
  mihomo -d "$etc" -f "$etc/config.yaml.new" -t || true
  rm -f "$etc/config.yaml.new"
  fail "the rendered config did not pass mihomo -t"
fi
mv "$etc/config.yaml.new" "$etc/config.yaml"

systemctl enable "$service" >/dev/null
systemctl restart "$service"

# Pair the panel. It also keeps its on/off choice in its state dir.
ctl_dir=$home/.config/omarchy-mihomo
install -d -m 700 -o "$user" -g "$group" "$ctl_dir"
sudo -u "$user" mkdir -p "$home/.local/state/omarchy-mihomo"
tmp=$(mktemp "$ctl_dir/.controller.XXXXXX")
printf '{"url": "http://127.0.0.1:9090", "secret": "%s", "service": "%s"}\n' "$secret" "$service" > "$tmp"
chown "$user:$group" "$tmp"
chmod 600 "$tmp"
mv "$tmp" "$ctl_dir/controller.json"

# Wait for the controller to answer.
for _ in $(seq 1 30); do
  if curl -fs -m 1 -H "Authorization: Bearer $secret" http://127.0.0.1:9090/version >/dev/null 2>&1; then
    echo "mihomo is running: $(curl -fs -H "Authorization: Bearer $secret" http://127.0.0.1:9090/version)"
    echo
    echo "Turn the VPN on from the bar (shield icon), or: omarchy-shell aintnewtathis.mihomo on"
    echo "Only one VPN at a time: disconnect any other VPN (Amnezia, WireGuard...) first."
    exit 0
  fi
  sleep 0.5
done
journalctl -u "$service" -n 20 --no-pager -o cat >&2 || true
fail "mihomo did not answer on 127.0.0.1:9090"
