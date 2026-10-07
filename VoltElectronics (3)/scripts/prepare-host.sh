#!/usr/bin/env bash
# Run as root using Azure Run Command. Only the explicitly attached LUN 0 is initialized.
set -euo pipefail
cloud-init status --wait
systemctl stop docker
for attempt in $(seq 1 120); do
  [[ -b /dev/disk/azure/scsi1/lun0 ]] && break
  sleep 5
done
disk=$(readlink -f /dev/disk/azure/scsi1/lun0)
[[ -b "$disk" ]] || { echo 'Attached data disk LUN 0 not found'; exit 1; }
mkdir -p /mnt/volt-data
if ! mountpoint -q /mnt/volt-data; then
  if ! blkid "$disk" >/dev/null; then mkfs.ext4 -F "$disk"; fi
  uuid=$(blkid -s UUID -o value "$disk")
  grep -q "UUID=$uuid " /etc/fstab || echo "UUID=$uuid /mnt/volt-data ext4 defaults,nofail 0 2" >> /etc/fstab
  mount /mnt/volt-data
fi
systemctl start docker
az login --identity --allow-no-subscriptions --output none
