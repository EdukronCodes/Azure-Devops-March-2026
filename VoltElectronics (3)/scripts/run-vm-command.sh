#!/usr/bin/env bash
set -euo pipefail
: "${RESOURCE_GROUP:?}" "${VM_NAME:?}" "${SCRIPT_FILE:?}" "${RELEASE_ACCOUNT:?}" "${RELEASE_PREFIX:?}" "${BUILD_ID:?}" "${SUCCESS_MARKER:?}"
parameters=("$RELEASE_ACCOUNT" "$RELEASE_PREFIX" "$BUILD_ID")
if [[ -n "${EXPECTED_COMMIT:-}" ]]; then parameters+=("$EXPECTED_COMMIT"); fi
az vm run-command invoke --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --command-id RunShellScript --scripts "@$SCRIPT_FILE" --parameters "${parameters[@]}" -o json > command-result.json
jq -r '.value[]?.message' command-result.json
jq -r '.value[]?.message' command-result.json | grep -q "$SUCCESS_MARKER" || { echo 'Remote deployment did not confirm success'; exit 1; }
