#!/usr/bin/env bash
set -euo pipefail
mode=${1:-source}
mkdir -p reports/trivy
image="aquasec/trivy:${TRIVY_VERSION:-0.75.0}"
docker pull "$image"
docker image inspect "$image" --format '{{json .RepoDigests}}' > reports/trivy/tool-image.json
extra_mount=()
if [[ "$mode" == image ]]; then extra_mount=(-v "${PIPELINE_WORKSPACE:?}:/artifacts:ro"); fi
trivy() { docker run --rm -v "$PWD:/work" -w /work "${extra_mount[@]}" -v "$HOME/.cache/trivy:/root/.cache/trivy" "$image" "$@"; }
if [[ "$mode" == source ]]; then
  echo 'Scanning pinned dependencies, Terraform, Dockerfile and repository secrets.'
  trivy fs --scanners vuln,misconfig,secret --skip-dirs .git,.tools,.venv,downloads,reports,recordings --severity HIGH,CRITICAL --format json --output reports/trivy/source.json --exit-code 0 .
  trivy fs --scanners vuln,misconfig,secret --skip-dirs .git,.tools,.venv,downloads,reports,recordings --severity HIGH,CRITICAL --format sarif --output reports/trivy/source.sarif --exit-code 1 .
else
  : "${CONTAINER_ARCHIVE:?Set CONTAINER_ARCHIVE}"
  echo 'Scanning the exact application container that will be deployed.'
  trivy image --input "$CONTAINER_ARCHIVE" --severity HIGH,CRITICAL --format json --output reports/trivy/image.json --exit-code 0
  status=0
  trivy image --input "$CONTAINER_ARCHIVE" --severity HIGH,CRITICAL --format sarif --output reports/trivy/image.sarif --exit-code 1 || status=$?
  trivy image --input "$CONTAINER_ARCHIVE" --format cyclonedx --output reports/trivy/sbom.cdx.json
  exit "$status"
fi
