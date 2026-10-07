# VOLT electronics ecommerce

A complete Flask + SQLite demonstration store with 12 sample electronics, responsive product pages, search/category/brand/price/stock filters, sorting, comparison, account wishlists, registration/login, persistent carts, atomic stock-checked checkout, order history, and admin inventory/fulfillment. Prices are integer paise. Checkout is a demo without real payments. Existing gift catalog data is archived while accounts and historical order snapshots are preserved.

Project: https://dev.azure.com/edukrondevops/VoltElectronics
Pipeline: https://dev.azure.com/edukrondevops/VoltElectronics/_build?definitionId=13

## Local startup

```powershell
python -m venv .venv
.\.venv\Scripts\python -m pip install -r requirements-dev.txt
# Set SECRET_KEY to a stable random value in your environment.
.\.venv\Scripts\python app.py
```

Open http://127.0.0.1:8000. SQLite is created at data/shop.db. Set ADMIN_EMAIL and ADMIN_PASSWORD before startup to seed an administrator; existing users are not silently promoted. Keep credentials out of source and recordings.

```powershell
.\.venv\Scripts\python -m pytest tests -v --cov=app --cov=catalog --cov-fail-under=90
node --check static/app.js
terraform -chdir=infra init -backend=false
terraform -chdir=infra validate
terraform -chdir=infra test
.\.venv\Scripts\python scripts/backup.py data/shop.db backups/snapshot.db
.\.venv\Scripts\python scripts/source_bundle.py downloads/volt-electronics-source.zip
```

Nine application tests cover accounts, CSRF, checkout totals, stock, cart changes, order isolation, wishlist/comparison, authorization and admin fulfillment. Three mocked Terraform tests check hub/spoke networks, public app hosting and private SonarQube. Mock tests validate plans without creating Azure resources.

## CI/CD and architecture

See [pipeline walkthrough](docs/pipeline.md) for all 13 stages, report downloads, SonarQube modes, Trivy gates and deployment variables. See [hub-and-spoke architecture](docs/architecture.md) for modules, network ranges, disk persistence and operational limits.

The pipeline builds a versioned ZIP, constructs a nonroot Docker image, scans the exact saved image, and deploys that image to an Ubuntu VM on a public IP. SQLite uses a separate protected managed disk. A private SonarQube VM in the hub uses PostgreSQL and persistent Docker volumes. A second operations spoke reserves network space for future private agents.

## Azure identity and remote state

The requested Azure identity is giftzee.online@gmail.com. Authenticate it before Terraform execution; another cached CLI identity must not be used. Initialize the Entra-authenticated Blob backend:

```powershell
az login --use-device-code
# Verify the returned account and subscription before continuing.
.\scripts\bootstrap.ps1 -SubscriptionId YOUR_GIFTZEE_SUBSCRIPTION_ID -StorageName UNIQUE_LOWERCASE_NAME -Location centralindia
```

After the federated pipeline identity exists, run scripts/create-ci-backend.ps1 to create the East US backend and migrate application state. Set pipeline stateStorageAccount to voltstateusc2383fdd. The Central India account remains for bootstrap and recovery. Backend keys include volt-electronics/app.tfstate, volt-electronics/bootstrap.tfstate and volt-electronics/ci-backend.tfstate. Storage disables public blobs and shared keys, enables versioning/soft deletion, and uses identity permissions and blob leases. Preserve bootstrap state until migration succeeds. Do not publish Terraform state or saved plans.

Create a federated Azure service connection, configure the variables documented in docs/pipeline.md, then queue main with deployAzure=true. Infrastructure can incur charges for two VMs, managed disks, NAT gateway, public IPs and storage. Regional quota and host-encryption availability must be checked on the intended subscription.

## Scope and operation

The public IP initially provides HTTP demo access. HTTPS, real payment/shipping services, account recovery, throttling, automated off-host backups and production monitoring are not configured. Use one VM/worker with SQLite; do not scale horizontally against this database. Deployment takes a consistent SQLite backup before replacing the container. Validate restores and retain encrypted backups outside the VM for disaster recovery.

Full source downloads exclude live databases, credentials, private SSH keys and Terraform state. Screen recordings live under recordings/ and are excluded from Git. Background terminal execution is not itself visible in a desktop recording; the recording captures the desktop/browser/chat activity from the time it starts.
