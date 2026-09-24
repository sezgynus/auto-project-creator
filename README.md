# Auto Project Creator

A PowerShell bootstrap script for creating GitHub repositories that are immediately ready for automated development and automatic SSH commit signing.

The script creates a new public repository, initializes its default branch, installs the required GitHub Actions secrets, configures a signing workflow, and protects the branch so the dedicated Signing Bot can replace unsigned commits with signed equivalents.

## Purpose

The main goal is to make newly created repositories ready for automated development without manually repeating the same GitHub setup for every project.

After a repository is created with this script:

- local commits can use the developer's existing Git/SSH signing configuration;
- commits pushed through automated tools can be detected by GitHub Actions;
- unsigned commits pushed by `sezgynus` are automatically amended and SSH-signed;
- the signed replacement is shown as **Verified** by GitHub;
- force-pushes required for the amend operation are restricted by a repository ruleset;
- only the dedicated GitHub App can bypass the non-fast-forward restriction.

## Requirements

The machine running the script must have:

- PowerShell
- Git
- GitHub CLI (`gh`)
- an authenticated GitHub CLI session
- a local SSH signing key for normal Git commits
- a dedicated SSH signing key for GitHub Actions
- the private key of the dedicated GitHub App

The script currently uses the following local files:

```text
%USERPROFILE%\.ssh\github_actions_signing
C:\Users\swift\Downloads\sezgynus-commit-signing-bot.2026-09-24.private-key.pem
```

The GitHub App ID is configured in the script as:

```text
5059105
```

## How It Works

Run:

```powershell
.\new-project.ps1
```

The script asks for the new repository name and then performs the complete bootstrap process.

### 1. Validates the environment

It checks that Git and GitHub CLI are installed, verifies GitHub CLI authentication, and confirms that the required signing key and GitHub App private key exist.

### 2. Creates a temporary Git repository

A temporary project directory is created with:

- a `main` branch;
- an initial `README.md`;
- the automatic commit-signing workflow.

The initial commit is signed locally with:

```powershell
git commit -S
```

### 3. Creates the GitHub repository

The repository is created under the `sezgynus` account as a public repository and the local temporary repository is connected to it as `origin`.

### 4. Installs repository secrets

Three GitHub Actions secrets are installed automatically:

```text
COMMIT_SIGNING_KEY
SIGNING_APP_ID
SIGNING_APP_PRIVATE_KEY
```

These allow GitHub Actions to sign commits and authenticate as the dedicated Signing Bot GitHub App.

### 5. Pushes the initial project

The locally signed initial commit is pushed to the new repository's `main` branch.

Because the commit is already signed, the signing workflow detects the signature and leaves the commit unchanged.

### 6. Protects the branch

The script creates the repository ruleset:

```text
Protect default branch - Signing Bot Bypass
```

The ruleset applies a `non_fast_forward` restriction to:

```text
refs/heads/main
```

The dedicated Signing Bot GitHub App is configured as the bypass actor.

This allows the bot to replace an unsigned commit with its signed version while ordinary pushes cannot bypass the non-fast-forward protection.

## Automatic Signing Flow

When an unsigned commit is pushed to `main` by `sezgynus`, the generated GitHub Actions workflow performs the following sequence:

```text
Unsigned commit pushed
        |
        v
GitHub Actions starts
        |
        v
Signing Bot installation token generated
        |
        v
HEAD signature checked
        |
        v
Unsigned?
   |        |
  No       Yes
   |        |
 Stop      v
        git commit --amend -S
             |
             v
        Signed commit created
             |
             v
        git push --force-with-lease
             |
             v
        GitHub: Verified
```

The workflow runs only when the push actor is:

```text
sezgynus
```

Already signed commits are not modified.

## UTF-8 Committer Name Handling

The workflow uses:

```text
Sezgin AÇIKGÖZ
```

as the Git committer name.

To avoid Windows PowerShell 5.1 source-file encoding problems, Turkish characters are constructed from Unicode code points inside the bootstrap script instead of relying on the encoding used to read the `.ps1` file.

The generated workflow is then explicitly written as UTF-8 without BOM and verified before the repository is created.

This prevents names such as:

```text
Sezgin AÃ‡IKGÃ–Z
```

from appearing in automatically signed commits.

## Security Model

The repository remains publicly readable, but public visibility does not grant push access.

The signing architecture separates credentials by purpose:

- the developer's personal SSH key signs normal local commits;
- a dedicated SSH signing key signs automated commits;
- a dedicated GitHub App provides the credentials required for the signing workflow to update the protected branch;
- the GitHub App private key and SSH signing private key are stored as GitHub Actions secrets;
- the repository ruleset grants the non-fast-forward bypass specifically to the Signing Bot integration.

Private keys must never be committed to the repository.

## Current Limitations

The signing workflow checks the current `HEAD` commit of a push. If a single push contains several new unsigned commits, only the HEAD commit is amended and signed.

This is suitable for the intended automated-development workflow where automated repository writes normally create one commit at a time.

The current bootstrap configuration creates **public repositories**. Repository ruleset availability for private repositories depends on the GitHub account/plan.

## Files

```text
new-project.ps1
.github/workflows/sign-commits.yml
README.md
```

`new-project.ps1` is the bootstrap utility stored in this repository.

The `.github/workflows/sign-commits.yml` file in every generated project performs automatic signing for future unsigned commits.
