#!/usr/bin/env bash
# Apply this repo's Pi-hole config. Safe to re-run. Runs as root on the Pi
# (`make deploy` calls it).
set -euo pipefail
cd "$(dirname "$0")/.."
source .env

TAG="managed by repo"

echo "==> Applying settings.conf"
while IFS= read -r line || [[ -n "${line}" ]]; do
  [[ "${line}" =~ ^[[:space:]]*(#|$) ]] && continue
  key="${line%%=*}"
  key="${key//[[:space:]]/}"
  value="${line#*=}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  echo "    ${key} = ${value}"
  pihole-FTL --config "${key}" "${value}" >/dev/null
done < settings.conf

echo "==> Setting web password"
pihole setpassword "${PIHOLE_PASSWORD}" >/dev/null

echo "==> Restarting Pi-hole"
systemctl restart pihole-FTL

echo "==> Syncing adlists.txt"
# Lists tagged "$TAG" are owned by adlists.txt; anything else (added in the
# web UI) is left alone.
{
  echo "BEGIN;"
  echo "CREATE TEMP TABLE repo (address TEXT PRIMARY KEY);"
  grep -Ev '^[[:space:]]*(#|$)' adlists.txt | sed -e 's/[[:space:]]//g' -e "s/'/''/g" \
    | while read -r url; do echo "INSERT OR IGNORE INTO repo VALUES ('${url}');"; done
  echo "DELETE FROM adlist WHERE comment = '${TAG}' AND address NOT IN (SELECT address FROM repo);"
  echo "INSERT INTO adlist (address, enabled, comment, type) SELECT address, 1, '${TAG}', 0 FROM repo WHERE true"
  echo "  ON CONFLICT (address, type) DO UPDATE SET enabled = 1, comment = '${TAG}';"
  echo "COMMIT;"
} | pihole-FTL sqlite3 /etc/pihole/gravity.db

echo "==> Installing daily gravity timer"
install -m 644 systemd/pihole-gravity.service systemd/pihole-gravity.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now pihole-gravity.timer

echo "==> Updating gravity"
pihole -g
