#!/usr/bin/env bash
# Analyze the exact release source on the private hub server and export durable evidence.
set -euo pipefail
account=$1
release=$2
build=$3
commit=$4
umask 077
work="/mnt/volt-data/sonar/scans/$build"
mkdir -p "$work/reports/sonarqube"
cd "$work"
az login --identity --allow-no-subscriptions --output none
for file in source.zip coverage.xml analysis-inputs.sha256; do
  az storage blob download --account-name "$account" --container-name releases --name "$release/$file" --file "$file" --auth-mode login --overwrite --output none
done
sha256sum -c analysis-inputs.sha256
unzip -q -o source.zip
mv coverage.xml reports/coverage.xml
chown -R 10001:10001 "$work"
chmod 750 "$work"
export SONAR_HOST_URL=http://127.0.0.1:9000 SONAR_USER_HOME=/tmp/sonar-cache
password=$(cat /mnt/volt-data/sonar/admin.password)
SONAR_TOKEN=$(curl --fail -sS -u "admin:$password" -X POST "$SONAR_HOST_URL/api/user_tokens/generate" --data-urlencode "name=volt-release-$build" | jq -er .token)
export SONAR_TOKEN
trap 'curl --fail -sS -u "admin:$password" -X POST "$SONAR_HOST_URL/api/user_tokens/revoke" --data-urlencode "name=volt-release-$build" >/dev/null || true' EXIT
status=0
docker run --rm --network host --user 10001:10001 -e SONAR_TOKEN -e SONAR_HOST_URL -e SONAR_USER_HOME -v "$work:/usr/src" sonarsource/sonar-scanner-cli:latest -Dsonar.working.directory=/usr/src/.scannerwork -Dsonar.scm.disabled=true "-Dsonar.scm.revision=$commit" "-Dsonar.projectVersion=$build" || status=$?
for report in quality-gate issues measures; do
  case "$report" in
    quality-gate) endpoint='/api/qualitygates/project_status?projectKey=volt-electronics';;
    issues) endpoint='/api/issues/search?componentKeys=volt-electronics&ps=500';;
    measures) endpoint='/api/measures/component?component=volt-electronics&metricKeys=coverage,ncloc,duplicated_lines_density';;
  esac
  curl --fail -sS -H "Authorization: Bearer $SONAR_TOKEN" "$SONAR_HOST_URL$endpoint" > "reports/sonarqube/$report.json"
  az storage blob upload --account-name "$account" --container-name releases --name "$release/hub-sonarqube/$report.json" --file "reports/sonarqube/$report.json" --auth-mode login --overwrite false --output none
done
# Remove the analysis token after exporting reports; credentials never enter logs.
curl --fail -sS -u "admin:$password" -X POST "$SONAR_HOST_URL/api/user_tokens/revoke" --data-urlencode "name=volt-release-$build"
jq -r '"Private hub SonarQube quality gate: " + .projectStatus.status' reports/sonarqube/quality-gate.json
[[ "$status" == 0 ]] || exit "$status"
printf '\nVOLT_HUB_ANALYSIS_SUCCESS\n'
