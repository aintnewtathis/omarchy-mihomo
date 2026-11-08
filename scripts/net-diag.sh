#!/usr/bin/env bash
# Snapshot of the laptop's network state, for debugging why proxy nodes are
# unreachable. Writes ~/.local/state/omarchy-mihomo/dev/diag-<time>.txt.
# No secrets are collected.
# usage: net-diag.sh <label>       e.g. net-diag.sh amnezia-off
set -uo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
label=${1:-snapshot}
state=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-mihomo/dev
out=$state/diag-$(date +%H%M%S)-$label.txt
mkdir -p "$state"

nodes=(13.140.88.103 13.140.92.77 46.8.233.95 94.183.235.134)
others=(31.59.41.29 1.1.1.1 5.255.255.77)

tcp() { timeout 4 bash -c "</dev/tcp/$1/$2" 2>/dev/null && echo OK || echo --; }

{
  echo "### $label  $(date -Is)"
  echo; echo "### processes"; pgrep -a -f -i 'amnezia|wireguard|mihomo' | cut -c1-120
  echo; echo "### interfaces"; ip -br a
  echo; echo "### ipv4 routes (main)"; ip route
  echo; echo "### ip rules"; ip rule
  echo; echo "### routes, other tables"; ip route show table all | grep -v -e 'table local' -e 'table main' -e '^local' -e '^broadcast' -e fe80 | head -20
  echo; echo "### dns"; resolvectl dns 2>&1 | head
  echo; echo "### tcp connect (443 / 2053)"
  for ip in "${nodes[@]}" "${others[@]}"; do
    printf '%-16s 443:%s 2053:%s  via %s\n' "$ip" "$(tcp "$ip" 443)" "$(tcp "$ip" 2053)" "$(ip route get "$ip" | grep -o 'dev [^ ]*')"
  done
  echo; echo "### direct http (no proxy)"
  curl -s -m6 --noproxy '*' -o /dev/null -w 'yandex.ru  code=%{http_code} ip=%{remote_ip}\n' https://yandex.ru
  curl -s -m6 --noproxy '*' -w '  <- my public ip (ipinfo)\n' https://ipinfo.io/ip
  echo; echo "### through mihomo 127.0.0.1:7890 (if running)"
  curl -s -m10 -x http://127.0.0.1:7890 -w '  <- exit ip via mihomo, curl exit=%{exitcode}\n' https://ipinfo.io/ip
  echo; echo "### firewall (needs sudo; skipped if not cached)"
  if sudo -n true 2>/dev/null; then
    sudo nft list ruleset 2>&1 | grep -v -e '^\s*$' | head -150
  else
    echo "sudo not cached: run 'sudo -v' first to include nftables rules"
  fi
} > "$out" 2>&1

echo "wrote $out"
