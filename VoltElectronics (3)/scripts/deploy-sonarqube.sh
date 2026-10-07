#!/usr/bin/env bash
set -euo pipefail
account=$1
release=$2
build=$3
cloud-init status --wait
for attempt in $(seq 1 120); do [[ -b /dev/disk/azure/scsi1/lun0 ]] && break; sleep 5; done
systemctl stop docker
disk=$(readlink -f /dev/disk/azure/scsi1/lun0)
[[ -b "$disk" ]] || exit 1
mkdir -p /mnt/volt-data
if ! mountpoint -q /mnt/volt-data; then
  if ! blkid "$disk" >/dev/null; then mkfs.ext4 -F "$disk"; fi
  uuid=$(blkid -s UUID -o value "$disk")
  grep -q "UUID=$uuid " /etc/fstab || echo "UUID=$uuid /mnt/volt-data ext4 defaults,nofail 0 2" >> /etc/fstab
  mount /mnt/volt-data
fi
systemctl start docker
az login --identity --allow-no-subscriptions --output none
mkdir -p /mnt/volt-data/sonar
cd /mnt/volt-data/sonar
az storage blob download --account-name "$account" --container-name releases --name "$release/sonarqube-compose.yml" --file compose.yml --auth-mode login --overwrite --output none
if [[ ! -f .env ]]; then
  umask 077
  printf 'SONAR_DB_PASSWORD=%s\nSONAR_BIND_IP=0.0.0.0\n' "$(openssl rand -hex 32)" > .env
fi
# Named Docker volumes live beneath the Docker data-root on the managed data disk.
docker compose -f compose.yml up -d
for attempt in $(seq 1 180); do
  status=$(curl -fsS http://127.0.0.1:9000/api/system/status | jq -r .status || true)
  [[ "$status" == UP ]] && break
  [[ "$attempt" == 180 ]] && exit 1
  sleep 3
done
if [[ ! -f admin.password ]]; then
  umask 077
  printf 'V0lt!%s\n' "$(openssl rand -hex 32)" > admin.password.pending
  password=$(cat admin.password.pending)
  curl --fail -sS -u admin:admin -X POST http://127.0.0.1:9000/api/users/change_password --data-urlencode login=admin --data-urlencode previousPassword=admin --data-urlencode "password=$password"
  mv admin.password.pending admin.password
fi
printf '\nVOLT_SONAR_READY\n'
