#!/usr/bin/env bash
# Parameters: storage account, release prefix, build ID. Fetch immutable scanned image using managed identity.
set -euo pipefail
account=$1
release=$2
build=$3
cloud-init status --wait
for attempt in $(seq 1 120); do [[ -b /dev/disk/azure/scsi1/lun0 ]] && break; sleep 5; done
systemctl stop docker
disk=$(readlink -f /dev/disk/azure/scsi1/lun0)
[[ -b "$disk" ]] || { echo 'LUN 0 is not attached'; exit 1; }
mkdir -p /mnt/volt-data
if ! mountpoint -q /mnt/volt-data; then
  if ! blkid "$disk" >/dev/null; then mkfs.ext4 -F "$disk"; fi
  uuid=$(blkid -s UUID -o value "$disk")
  grep -q "UUID=$uuid " /etc/fstab || echo "UUID=$uuid /mnt/volt-data ext4 defaults,nofail 0 2" >> /etc/fstab
  mount /mnt/volt-data
fi
systemctl start docker
az login --identity --allow-no-subscriptions --output none
work="/mnt/volt-data/releases/$build"
mkdir -p "$work" /mnt/volt-data/app/backups
chown -R 10001:10001 /mnt/volt-data/app
cd "$work"
for file in image.tar image.tar.sha256; do
  for attempt in $(seq 1 30); do
    az storage blob download --account-name "$account" --container-name releases --name "$release/$file" --file "$file" --auth-mode login --overwrite --output none --only-show-errors && break
    [[ "$attempt" == 30 ]] && exit 1
    sleep 10
  done
done
sha256sum -c image.tar.sha256
docker load -i image.tar
if [[ ! -f /mnt/volt-data/app.env ]]; then
  umask 077
  printf 'SECRET_KEY=%s\nDATABASE_PATH=/data/shop.db\nPRODUCTION=0\nADMIN_EMAIL=giftzee.online@gmail.com\nADMIN_PASSWORD=%s\n' "$(openssl rand -hex 32)" "$(openssl rand -hex 32)" > /mnt/volt-data/app.env
fi
# HTTP is a demonstration endpoint. Set PRODUCTION=1 after configuring HTTPS.
if docker inspect volt-app >/dev/null 2>&1; then
  docker exec volt-app python -c "import sqlite3; a=sqlite3.connect('/data/shop.db'); b=sqlite3.connect('/data/backups/pre-$build.db'); a.backup(b); b.close(); a.close()"
  docker stop volt-app
  docker rm volt-app
fi
docker run -d --name volt-app --restart unless-stopped --read-only --tmpfs /tmp --env-file /mnt/volt-data/app.env -v /mnt/volt-data/app:/data -p 127.0.0.1:8000:8000 "volt:$build"
cat > /etc/nginx/sites-available/volt <<'NGINX'
server {
  listen 80 default_server;
  server_name _;
  client_max_body_size 64k;
  location / {
    proxy_pass http://127.0.0.1:8000;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }
}
NGINX
rm -f /etc/nginx/sites-enabled/default
ln -sfn /etc/nginx/sites-available/volt /etc/nginx/sites-enabled/volt
nginx -t
systemctl enable --now nginx
systemctl reload nginx
curl --fail --retry 12 --retry-delay 5 --retry-all-errors http://127.0.0.1/health
printf '\nVOLT_DEPLOY_SUCCESS\n'
