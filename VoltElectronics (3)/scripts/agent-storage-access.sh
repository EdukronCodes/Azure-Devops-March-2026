#!/usr/bin/env bash
# Temporarily permit this job's IPv4; verify data-plane reachability before deployment.
set -euo pipefail
account=${1:?Storage account required}
group=${2:?Resource group required}
action=${3:-add}
container=${4:-releases}
ip=${VOLT_AGENT_IP:-$(curl -4 --fail --silent --show-error https://api.ipify.org)}
[[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo 'Cannot determine agent IPv4'; exit 1; }
export VOLT_AGENT_IP="$ip"
az storage account network-rule "$action" --account-name "$account" --resource-group "$group" --ip-address "$ip" --output none
if [[ "$action" == add ]]; then
  region=$(az storage account show --name "$account" --resource-group "$group" --query location -o tsv)
  echo "Storage account region: $region; waiting for authenticated data-plane access."
  for attempt in $(seq 1 24); do
    if az storage blob list --account-name "$account" --container-name "$container" --auth-mode login --num-results 1 --output none --only-show-errors; then
      echo 'Storage firewall and Blob RBAC access verified.'
      exit_status=0
      break
    fi
    exit_status=1
    sleep 10
  done
  [[ "${exit_status:-1}" == 0 ]] || { echo 'Storage access is blocked. Check same-region restrictions, firewall propagation and Blob RBAC.'; return 1 2>/dev/null || exit 1; }
fi
