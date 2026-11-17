# GitHub publishing — complete Windows PowerShell walkthrough

**Outcome:** a clean public or private GitHub repository containing source code, Terraform, documentation and four architecture diagrams, with automated tests visible under **Actions**. Nothing in these instructions requires giving GitHub your AWS access keys.

## Step 1 — locate the correct folder

Download the complete project ZIP, then **Extract All**. Open PowerShell, not the Python console, and navigate to the **repository root** (the folder containing `README.md`, `.gitignore`, `terraform`, `frontend`, `worker`). Example:

```powershell
Set-Location -LiteralPath 'C:\Users\YOUR_WINDOWS_USER\Desktop\AWS Projects\ApertureBridge_AWS_Migration_Project'
Get-ChildItem -Force | Select-Object Name
```

Check that you see `.gitignore`, `.github`, `README.md`, `terraform`, `frontend`, `worker`, `scripts`, `diagrams`. **Do not** run `git init` from the parent `AWS Projects` directory; doing so would accidentally stage other unrelated projects.

## Step 2 — confirm Git works

```powershell
git --version
Get-Command git
```

If command is not recognized, install **Git for Windows** from https://git-scm.com/download/win or an approved `winget` package; select **Git from the command line and also from 3rd-party software** during setup. Close/reopen PowerShell. If Git is installed but not found, ensure `C:\Program Files\Git\cmd` is in PATH. Check again before continuing.

Optional: `gh --version` verifies GitHub CLI if you want browser-based authentication.

## Step 3 — establish your author identity (once per computer)

```powershell
git config --global user.name "YOUR_NAME"
git config --global user.email "YOUR_GITHUB_VERIFIED_EMAIL"
git config --global init.defaultBranch main
```

Prefer your GitHub noreply address if you want your personal email hidden. `git config --list --show-origin` shows where settings came from. Do not include your home address, personal account data or live AWS IDs in the README.

## Step 4 — run local checks before committing

```powershell
python --version
docker compose -f local/docker-compose.yml config
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r frontend/requirements.txt -r worker/requirements.txt -r requirements-dev.txt
python -m compileall -q frontend worker shared scripts tests
pytest -q tests
terraform fmt -recursive terraform
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
```

If `py -3.12` is not installed, use `python -m venv .venv` provided you have a compatible Python version. If script execution is blocked by PowerShell execution policy, do not weaken machine-wide security: run `.\.venv\Scripts\python.exe -m pytest -q tests` without activating, or ask your admin about per-process policy.

**Note:** Terraform's provider init downloads dependencies; an offline machine may pass Python syntax tests but fail provider-dependent validation. GitHub Actions will run `terraform validate` on a machine with network access.

## Step 5 — safeguard the repository

```powershell
# Never commit terraform state, tfvars, secrets, virtual machines or private keys.
git check-ignore terraform/terraform.tfvars terraform/terraform.tfstate .env example.ova
Get-ChildItem -Recurse -Force -File -Include *.tfstate,terraform.tfvars,*.pem,*.ova,.env `
  | Select-Object FullName
```

The sample `terraform.tfvars.example` and `.env.example` are safe **placeholders** and are meant to be committed. The actual `terraform.tfvars`, `.env`, AWS credentials, certificates, TF plans, Python virtual environment, and real source images belong outside Git. If you have already staged a secret, remove it from Git's index with `git rm --cached PATH` **before** committing. If a real secret was pushed, rotate it and clean the Git history—deleting just the latest file does not erase past commits.

## Step 6 — create an empty repository on GitHub

1. Sign in to https://github.com/ in your browser.
2. Use the top-right **+** menu → **New repository** (or visit https://github.com/new).
3. Repository name: `aperturebridge-aws-migration`.
4. Suggested description: `AWS migration reference for an image-hosting platform — Aurora, Elastic Beanstalk, S3, SQS, ECS, ECR and VM Import/Export`.
5. Set **Public** if the material contains only synthetic code and diagrams; choose **Private** if any employer or customer policy requires it.
6. **Do not check** “Add a README”, `.gitignore`, or a license while creating the repo (they already exist locally or can be added later). This avoids unrelated remote commits and simple first-push conflicts.
7. Click **Create repository**. Keep the repository URL open.

## Step 7 — initialize Git in the project root

```powershell
git status
# If 'not a git repository':
git init -b main
# If it is already a repository, do not reinitialize; use the existing one.
git branch --show-current
```

If `git init -b main` says your Git version lacks `-b`, use `git init` followed by `git branch -M main`. `git status` should show project files as untracked, not your Desktop or other repositories.

## Step 8 — stage and audit

```powershell
git add .
git status --short
git diff --cached --stat
git ls-files | Select-String '\.(tfstate|pem|ova)$|terraform\.tfvars$|(^|/)\.env$'
```

The last command should return **no protected files**. Confirm the PNG/SVG diagrams and `README.md` are staged. If you staged an OVA or state file by accident, stop, remove it from staging, review `.gitignore`, and repeat the check. GitHub rejects individual ordinary Git files larger than 100 MiB; VM exports should never be stored there in the first place.

## Step 9 — make the first commit

```powershell
git commit -m "Create ApertureBridge AWS migration reference architecture"
git log -1 --oneline
```

If Git reports `Author identity unknown`, redo Step 3 and re-run the commit. If `nothing to commit`, check `git status`: it may have been committed already.

## Step 10 — connect the remote

Use your actual account name, not the placeholder:

```powershell
git remote -v
# Run only if 'origin' has not been set:
git remote add origin https://github.com/YOUR_USERNAME/aperturebridge-aws-migration.git
# If origin exists but points to the wrong repository:
git remote set-url origin https://github.com/YOUR_USERNAME/aperturebridge-aws-migration.git

git branch -M main
git remote -v
```

Check the URL before pushing: it must be your own repository or an organization repository to which you have write access. A GitHub username is not necessarily the same as your Windows username.

## Step 11 — authenticate correctly and push

**Recommended:** sign in through Git Credential Manager's browser prompt. If using GitHub CLI:

```powershell
gh auth login
# Choose GitHub.com > HTTPS > authenticate with browser.
gh auth status
git push -u origin main
```

Alternatively, use `git push -u origin main` directly; on a standard Git for Windows installation, Git Credential Manager should offer browser login. GitHub account passwords cannot be used as Git-over-HTTPS passwords. Don't paste a personal access token into README, shell history, issue comments or screenshots. If you deliberately use a fine-grained PAT, grant only the necessary repository Contents permissions, store it in a credential manager and rotate when appropriate.

Expected final output resembles `branch 'main' set up to track 'origin/main'`. Check `git status -sb`: ideally `## main...origin/main` with a clean working tree.

## Step 12 — verify the actual GitHub page

Open `https://github.com/YOUR_USERNAME/aperturebridge-aws-migration` and confirm:

- README renders the target architecture image and hyperlinks.
- Terraform files, frontend, worker, PowerShell scripts, test cases and diagrams are visible.
- No `terraform.tfstate`, secrets, AWS keys, private PEM/OVA or customer images appear.
- Under **Actions**, the `validate-migration-reference` workflow runs and becomes green. If a job fails, open its logs; do not claim the project has passed CI until it is green.
- Optionally set a repository description, topics `aws`, `migration`, `terraform`, `ecs`, `aurora`, `elastic-beanstalk`, and the website/project URL. Add a diagram preview to a professional portfolio, with the lab/demo status clearly labeled.

## Subsequent edits

```powershell
git status
git add .
git diff --cached --stat
git commit -m "Improve migration runbook and tests"
git push
```

## Fast troubleshooting

| Message | Likely reason | Fix |
|---|---|---|
| `git is not recognized` | Git not on PATH | Install Git for Windows, add `C:\Program Files\Git\cmd`, restart shell |
| `fatal: not a git repository` | Wrong folder | `Set-Location -LiteralPath '...\ApertureBridge_AWS_Migration_Project'` |
| `remote origin already exists` | Remote already configured | `git remote -v`, use `git remote set-url origin ...` |
| `Repository not found` | Wrong URL, private repo or permission | Verify `git remote -v`, browser access and correct authenticated account |
| `Authentication failed` / 403 | Stale credentials or no write access | Run `gh auth login`, Git Credential Manager; check organization SSO and permissions |
| `src refspec main does not match any` | No commit on local main | Commit files, `git branch -M main`, then push |
| `rejected (fetch first)` | GitHub repo was initialized with a README/commit | Prefer a fresh *empty* remote. Otherwise fetch and integrate remote history intentionally; never force push blindly |
| `file exceeds 100 MB` | OVA/DB image or generated file staged | Remove from staging and history; add to `.gitignore`; use S3 for VM assets |
| `fatal: unable to access` | Corporate proxy/DNS/firewall | Test GitHub browser access, VPN/proxy configuration, organization network policy |
| `Actions workflow failed` | Dependency, Terraform schema or test failure | Inspect exact job log, fix locally, commit and push again |

**You do not need to deploy to AWS to publish the project to GitHub.** GitHub is storing your implementation and verification workflow, not live cloud infrastructure.
