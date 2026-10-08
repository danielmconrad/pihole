#!/usr/bin/env bash
# First-time setup of a fresh Raspberry Pi OS Lite install. Runs as root on the Pi
# (`make setup` calls it). The static IP takes effect on the next reboot.
#   setup.sh <hostname> <static-ip>
set -euo pipefail
cd "$(dirname "$0")/.."
source .env

NAME="$1"
IP="$2"
APT=(apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
export DEBIAN_FRONTEND=noninteractive

echo "==> Upgrading OS packages"
apt-get update
"${APT[@]}" full-upgrade
"${APT[@]}" install curl dnsutils

echo "==> Hostname ${NAME}, timezone ${TZ}"
raspi-config nonint do_hostname "${NAME}"
timedatectl set-timezone "${TZ}"

echo "==> Static IP ${IP} on eth0"
con="$(nmcli -g GENERAL.CONNECTION device show eth0)"
if [[ -z "${con}" ]]; then
  echo "eth0 has no active NetworkManager connection; is the Pi plugged in?" >&2
  exit 1
fi
# The Pi resolves through public DNS, not itself, so installs and upgrades still
# work when Pi-hole is down.
nmcli connection modify "${con}" \
  ipv4.method manual \
  ipv4.addresses "${IP}/24" \
  ipv4.gateway "${GATEWAY}" \
  ipv4.dns "1.1.1.1 1.0.0.1" \
  ipv4.ignore-auto-dns yes

if ! command -v pihole >/dev/null; then
  echo "==> Installing Pi-hole"
  install -d -m 755 /etc/pihole
  # An existing pihole.toml makes the installer run without its interactive
  # dialogs; FTL fills in defaults and configure.sh applies settings.conf after.
  [[ -f /etc/pihole/pihole.toml ]] || echo "# Seeded by setup.sh" > /etc/pihole/pihole.toml
  grep -Ev '^[[:space:]]*(#|$)' adlists.txt > /etc/pihole/adlists.list
  curl -sSL https://install.pi-hole.net | bash /dev/stdin --unattended
fi

bash scripts/configure.sh
