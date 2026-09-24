$ErrorActionPreference = "Stop"

# ============================================================
# CONFIG
# ============================================================

$GitHubOwner = "sezgynus"

$SigningKeyFile = "$HOME\.ssh\github_actions_signing"

$SigningAppId = "5059105"

$SigningAppPrivateKeyFile =
    "C:\Users\swift\Downloads\sezgynus-commit-signing-bot.2026-09-24.private-key.pem"


# ============================================================
# CHECK REQUIREMENTS
# ============================================================

Write-Host ""
Write-Host "Checking requirements..."

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI (gh) bulunamadi."
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git bulunamadi."
}

gh auth status

if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI authentication bulunamadi."
}

if (-not (Test-Path $SigningKeyFile)) {
    throw "Signing key bulunamadi: $SigningKeyFile"
}

if (-not (Test-Path $SigningAppPrivateKeyFile)) {
    throw "Signing Bot private key bulunamadi: $SigningAppPrivateKeyFile"
}


# ============================================================
# PROJECT NAME
# ============================================================

Write-Host ""

$ProjectName = Read-Host "Yeni proje/repository adi"

$ProjectName = $ProjectName.Trim()

if ([string]::IsNullOrWhiteSpace($ProjectName)) {
    throw "Proje adi bos olamaz."
}

$Repo = "$GitHubOwner/$ProjectName"

Write-Host ""
Write-Host "Repository: $Repo"
Write-Host ""


# ============================================================
# CHECK REPOSITORY
# ============================================================

$repoExists = $false

try {
    $null = gh api "/repos/$Repo" 2>$null

    if ($LASTEXITCODE -eq 0) {
        $repoExists = $true
    }
}
catch {
    $repoExists = $false
}

if ($repoExists) {
    throw "Repository zaten mevcut: $Repo"
}


# ============================================================
# CREATE TEMP PROJECT
# ============================================================

$TempDir = Join-Path $env:TEMP "github-project-bootstrap-$([Guid]::NewGuid())"

New-Item `
    -ItemType Directory `
    -Path $TempDir `
    -Force | Out-Null

Set-Location $TempDir


# ============================================================
# INITIALIZE GIT
# ============================================================

git init -b main

$Readme = @"
# $ProjectName

Project initialized for automated development.
"@

[IO.File]::WriteAllText(
    (Join-Path $TempDir "README.md"),
    $Readme,
    [Text.UTF8Encoding]::new($false)
)


# ============================================================
# CREATE SIGNING WORKFLOW
# ============================================================

New-Item `
    -ItemType Directory `
    -Path ".github\workflows" `
    -Force | Out-Null


# Build "Sezgin ACIKGOZ" with Turkish Unicode characters
# independently from the encoding of this PowerShell script.
#
# U+00C7 = C-cedilla
# U+0130 = Latin capital I with dot
# U+00D6 = O-diaeresis

$CommitterName =
    "Sezgin A" +
    [char]0x00C7 +
    [char]0x0049 +
    [char]0x004B +
    "G" +
    [char]0x00D6 +
    "Z"


$Workflow = @"
name: Sign Commits

on:
  push:
    branches:
      - main
  workflow_dispatch:

permissions:
  contents: read

jobs:
  sign:
    if: github.actor == 'sezgynus'
    runs-on: ubuntu-latest

    steps:
      - name: Generate Signing Bot token
        id: app-token
        uses: actions/create-github-app-token@v2
        with:
          app-id: `${{ secrets.SIGNING_APP_ID }}
          private-key: `${{ secrets.SIGNING_APP_PRIVATE_KEY }}

      - name: Checkout
        uses: actions/checkout@v4
        with:
          token: `${{ steps.app-token.outputs.token }}
          fetch-depth: 2

      - name: Install signing key
        shell: bash
        env:
          SIGNING_KEY: `${{ secrets.COMMIT_SIGNING_KEY }}
        run: |
          mkdir -p ~/.ssh
          chmod 700 ~/.ssh

          printf '%s\n' "`$SIGNING_KEY" > ~/.ssh/github_actions_signing
          chmod 600 ~/.ssh/github_actions_signing

          git config --local user.name "$CommitterName"
          git config --local user.email "sezginacikgoz@mail.com"

          git config --local gpg.format ssh
          git config --local user.signingkey ~/.ssh/github_actions_signing
          git config --local commit.gpgsign true

      - name: Check signature
        id: signature
        shell: bash
        run: |
          if git cat-file commit HEAD | grep -q '^gpgsig '; then
            echo "signed=true" >> "`$GITHUB_OUTPUT"
          else
            echo "signed=false" >> "`$GITHUB_OUTPUT"
          fi

      - name: Sign commit
        if: steps.signature.outputs.signed == 'false'
        shell: bash
        run: |
          git commit --amend --no-edit -S
          git push --force-with-lease origin HEAD:main
"@

[IO.File]::WriteAllText(
    (Join-Path $TempDir ".github\workflows\sign-commits.yml"),
    $Workflow,
    [Text.UTF8Encoding]::new($false)
)


# ============================================================
# VERIFY GENERATED WORKFLOW ENCODING
# ============================================================

$WorkflowFile = Join-Path $TempDir ".github\workflows\sign-commits.yml"

$WorkflowCheck = [IO.File]::ReadAllText(
    $WorkflowFile,
    [Text.Encoding]::UTF8
)

$ExpectedCommitterName =
    "Sezgin A" +
    [char]0x00C7 +
    [char]0x0049 +
    [char]0x004B +
    "G" +
    [char]0x00D6 +
    "Z"

if (-not $WorkflowCheck.Contains(
    "git config --local user.name `"$ExpectedCommitterName`""
)) {
    throw "Workflow UTF-8 verification failed."
}

Write-Host "Workflow UTF-8 verification: OK"


# ============================================================
# INITIAL COMMIT
# ============================================================

git add .

git commit `
    -S `
    -m "chore: initialize project"

if ($LASTEXITCODE -ne 0) {
    throw "Initial commit olusturulamadi."
}


# ============================================================
# CREATE GITHUB REPOSITORY
# ============================================================

Write-Host ""
Write-Host "Creating GitHub repository..."

gh repo create $Repo `
    --public `
    --source . `
    --remote origin

if ($LASTEXITCODE -ne 0) {
    throw "Repository olusturulamadi."
}


# ============================================================
# INSTALL ACTIONS SECRETS
# ============================================================

Write-Host ""
Write-Host "Installing Actions secrets..."

Get-Content $SigningKeyFile -Raw |
    gh secret set COMMIT_SIGNING_KEY `
        --repo $Repo

if ($LASTEXITCODE -ne 0) {
    throw "COMMIT_SIGNING_KEY yuklenemedi."
}


$SigningAppId |
    gh secret set SIGNING_APP_ID `
        --repo $Repo

if ($LASTEXITCODE -ne 0) {
    throw "SIGNING_APP_ID yuklenemedi."
}


Get-Content $SigningAppPrivateKeyFile -Raw |
    gh secret set SIGNING_APP_PRIVATE_KEY `
        --repo $Repo

if ($LASTEXITCODE -ne 0) {
    throw "SIGNING_APP_PRIVATE_KEY yuklenemedi."
}


# ============================================================
# PUSH INITIAL COMMIT
# ============================================================

Write-Host ""
Write-Host "Pushing initial project..."

git push -u origin main

if ($LASTEXITCODE -ne 0) {
    throw "Initial push basarisiz."
}


# ============================================================
# CREATE RULESET
# ============================================================

Write-Host ""
Write-Host "Creating Signing Bot ruleset..."

$RulesetFile = Join-Path $TempDir "ruleset.json"

$Ruleset = @"
{
  "name": "Protect default branch - Signing Bot Bypass",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [
    {
      "actor_id": 5059105,
      "actor_type": "Integration",
      "bypass_mode": "always"
    }
  ],
  "conditions": {
    "ref_name": {
      "include": [
        "refs/heads/main"
      ],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "non_fast_forward"
    }
  ]
}
"@

[IO.File]::WriteAllText(
    $RulesetFile,
    $Ruleset,
    [Text.UTF8Encoding]::new($false)
)

Get-Content $RulesetFile -Raw |
    gh api `
        --method POST `
        -H "Accept: application/vnd.github+json" `
        -H "X-GitHub-Api-Version: 2022-11-28" `
        "/repos/$Repo/rulesets" `
        --input -

if ($LASTEXITCODE -ne 0) {
    throw "Ruleset olusturulamadi."
}


# ============================================================
# CLEANUP
# ============================================================

Set-Location $env:TEMP

Remove-Item `
    $TempDir `
    -Recurse `
    -Force


# ============================================================
# COMPLETE
# ============================================================

Write-Host ""
Write-Host "=============================================="
Write-Host " PROJECT READY"
Write-Host "=============================================="
Write-Host ""
Write-Host "Repository : $Repo"
Write-Host "Branch     : main"
Write-Host "Signing    : Enabled"
Write-Host "Signing Bot: Enabled"
Write-Host "Ruleset    : Enabled"
Write-Host "Committer  : $CommitterName"
Write-Host ""
Write-Host "ChatGPT'ye su repo adini ver:"
Write-Host ""
Write-Host "    $Repo"
Write-Host ""
