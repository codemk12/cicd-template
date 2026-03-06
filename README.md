# CI/CD Pipeline Template

A production-ready CI/CD template for deploying FastAPI applications to GCP Cloud Run using GitHub Actions, Terraform, and Workload Identity Federation.

## Architecture

```
Developer → feature/* branch → PR to uat → merge → UAT Cloud Run
                                              ↓
                                    PR to main → merge → release-v* branch → PROD Cloud Run
```

## Branch Strategy

| Branch | Purpose | Triggers |
|--------|---------|----------|
| `feature/*` | Development work | Quality checks + tests |
| `uat` | Staging environment | Quality checks + tests + deploy to UAT |
| `main` | Production gate | Quality checks + tests + creates release branch |
| `release-v*-*-YYYYMMDD` | Production snapshot | Quality checks + tests + deploy to PROD |

## Quality Gates

Every push and PR runs these checks before any deployment:

| Check | Tool | What it catches |
|-------|------|-----------------|
| Linting | flake8 | Syntax errors, unused imports, style issues |
| Formatting | black | Inconsistent code formatting |
| Security | bandit | Hardcoded passwords, SQL injection, unsafe functions |
| Dependency audit | pip-audit | Known CVEs in installed packages |
| Type checking | mypy | Type errors, missing returns |
| Emoji check | custom script | Emojis in source files |
| Dockerfile lint | hadolint | Dockerfile anti-patterns |
| Unit tests | pytest | Application logic failures |

## Getting Started (New Project)

### Prerequisites

- [gcloud CLI](https://cloud.google.com/sdk/docs/install)
- [Terraform](https://developer.hashicorp.com/terraform/downloads)
- [Docker](https://docs.docker.com/get-docker/)
- [GitHub CLI](https://cli.github.com/)
- Python 3.11+

### 1. Clone and configure

```bash
git clone https://github.com/codemk12/cicd-template.git my-project
cd my-project
```

Edit the `Makefile` and update these values:

```makefile
PROJECT_ID=your-gcp-project-id
BUCKET=your-tf-state-bucket
GITHUB_REPO=your-org/your-repo
REGION=australia-southeast1
```

### 2. Authenticate

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
gh auth login
```

### 3. Bootstrap infrastructure

This creates all GCP resources (APIs, bucket, WIF, service account, IAM roles) and sets GitHub secrets:

```bash
make setup
```

### 4. Create branches

```bash
git checkout -b uat
git push -u origin uat
```

The `main` branch should already exist from the initial push.

## Developer Workflow

### Step 1: Create a feature branch

```bash
git checkout uat
git pull origin uat
git checkout -b feature/my-new-feature
```

### Step 2: Make your changes

Edit files under `app/`, add tests, etc.

### Step 3: Run checks locally (recommended)

```bash
# Create a virtual environment (first time only)
python3 -m venv venv
source venv/bin/activate
pip install -r app/requirements.txt -r requirements-dev.txt

# Run all checks
flake8 app/ --max-line-length=120
black --check app/                        # use 'black app/' to auto-fix
bandit -r app/ -x app/test_main.py
pip-audit
mypy app/main.py --ignore-missing-imports
python scripts/check_emoji.py .
pytest app/test_main.py -v
```

### Step 4: Push your feature branch

```bash
git add .
git commit -m "Add my new feature"
git push -u origin feature/my-new-feature
```

This triggers the pipeline which runs all quality checks and tests. No deployment happens. Check the results at: `https://github.com/YOUR_ORG/YOUR_REPO/actions`

If any check fails, fix the issue, commit, and push again.

### Step 5: Create a Pull Request to UAT

```bash
gh pr create --base uat --title "Add my new feature" --body "Description of changes"
```

Or create the PR from the GitHub UI. The pipeline runs again on the PR. All checks must pass before the PR can be merged.

### Step 6: Merge to UAT

Once the PR is approved and checks pass, merge it. This triggers:

1. Quality checks + tests run again
2. Docker image is built and pushed to GCR
3. Terraform deploys the new image to **UAT Cloud Run**

Verify at your UAT URL: `https://fastapi-uat-XXXXXX.a.run.app/health`

### Step 7: Promote to Production

When UAT is verified, create a PR from `uat` to `main`:

```bash
gh pr create --base main --head uat --title "Release: my new feature"
```

After merge to `main`, the pipeline:

1. Runs quality checks + tests
2. Automatically creates a `release-v1-X-YYYYMMDD` branch (version auto-increments)
3. The release branch push triggers a **production deployment**

## Release Versioning

Release branches follow the format: `release-v{major}-{patch}-{date}`

```
release-v1-0-20260306    # First release
release-v1-1-20260307    # Auto-incremented patch
release-v1-2-20260310    # Next auto-increment
```

To bump the major version (e.g., v2), manually create the branch:

```bash
git checkout main
git checkout -b release-v2-0-$(date +'%Y%m%d')
git push origin HEAD
```

Subsequent releases from `main` will auto-increment from `v2-0`.

## Project Structure

```
.
├── .github/workflows/
│   └── deploy.yml          # CI/CD pipeline definition
├── app/
│   ├── main.py             # FastAPI application
│   ├── test_main.py        # Unit tests
│   └── requirements.txt    # App dependencies
├── terraform/
│   ├── main.tf             # Cloud Run service (used by CI/CD)
│   ├── variables.tf        # Terraform variables
│   └── bootstrap/
│       └── main.tf         # WIF + Service Account (one-time setup)
├── scripts/
│   └── check_emoji.py      # Emoji detection script
├── Dockerfile
├── Makefile                # setup, deploy, teardown commands
└── requirements-dev.txt    # Dev/test dependencies
```

## Makefile Commands

| Command | Purpose |
|---------|---------|
| `make setup` | Bootstrap all GCP resources + GitHub secrets |
| `make deploy ENV=uat` | Build, push, and deploy to an environment |
| `make teardown` | Destroy all GCP resources |
| `make setup-apis` | Enable required GCP APIs only |
| `make setup-bucket` | Create TF state bucket only |
| `make setup-bootstrap` | Create WIF + SA via Terraform only |
| `make setup-iam` | Grant IAM roles only |
| `make setup-secrets` | Set GitHub secrets only |
| `make teardown-services` | Destroy Cloud Run services only |
| `make teardown-images` | Delete container images only |
| `make teardown-bucket` | Delete TF state bucket only |

## Teardown

To destroy all GCP resources:

```bash
make teardown
```

This removes: Cloud Run services, WIF pool/provider, service account, container images, TF state bucket, and IAM bindings.
