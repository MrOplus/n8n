# n8n Enterprise Docker Build Workflow

This repository contains a GitHub Actions workflow that builds n8n from source with the license
bypass patches applied, and pushes the resulting Docker image to GitHub Container Registry (GHCR).

## Workflow Overview

`.github/workflows/build.yml` runs two jobs:

**`check-version`**
1. Resolves the latest stable n8n release tag (`n8n@X.Y.Z`)
2. Computes a *build key* — `<version>-b<short hash of bypass.sh>`
3. Skips the build if that exact key was already pushed to GHCR

**`build-and-push`**
1. Clones n8n at the resolved release tag
2. Installs dependencies with pnpm
3. Applies `bypass.sh`, which verifies every patch and fails the build if any of them no longer apply
4. Builds n8n (`pnpm run build`) and the Docker image (`pnpm run build:docker`)
5. Tags and pushes the image to GHCR

> Only immutable `n8n@X.Y.Z` tags are considered. Upstream also publishes moving `stable` and
> `beta` releases; building from those produced non-reproducible images and permanently wedged
> the skip check, so they are filtered out.

## Triggers

- Weekly schedule — Sundays at 00:00 UTC
- Manual trigger via the Actions UI (`workflow_dispatch`), with two optional inputs:
  - `n8n_tag` — build a specific release instead of the latest stable (e.g. `n8n@2.32.7`)
  - `force_build` — build even if the build key already exists in the registry

## Docker Image Tags

Every successful build pushes:

| Tag | Meaning |
| --- | --- |
| `ghcr.io/mroplus/n8n:enterprise` | Main enterprise tag |
| `ghcr.io/mroplus/n8n:latest` | Latest build |
| `ghcr.io/mroplus/n8n:<n8n-version>` | n8n release version, e.g. `2.32.7` |
| `ghcr.io/mroplus/n8n:<version>-b<hash>` | Build key — version plus the `bypass.sh` revision |
| `ghcr.io/mroplus/n8n:<commit-sha>` | Commit of *this* repository |
| `ghcr.io/mroplus/n8n:n8n-<commit-hash>` | Commit of the n8n source repository |

The build key is what makes a rebuild happen: changing `bypass.sh` changes the key, so patch
changes ship without waiting for a new n8n release.

## What `bypass.sh` Patches

- `packages/@n8n/backend-common/src/license-state.ts` — license checks return `true`, quotas unlimited
- `packages/cli/src/license.ts` — same, for the deprecated wrappers still in use
- `ProjectTabs.vue` — the Variables tab is always shown
- `NonProductionLicenseBanner.vue` — banner hidden
- `docker/images/n8n/Dockerfile` — stable release type, plus arbitrary-UID support (see below)

Each patch is verified after it is applied. `sed`/`perl` exit 0 whether or not a pattern matched,
so without those checks an upstream refactor silently produces a half-patched image that still
reports a green build. If a patch no longer applies, the script lists it and exits non-zero.

## Required Permissions

- `contents: read` — to check out the repository
- `packages: write` — to push Docker images to GHCR

Authentication uses the `GITHUB_TOKEN` provided by GitHub Actions. No additional secrets are needed.

## Pulling the Image

```bash
docker pull ghcr.io/mroplus/n8n:enterprise
docker run -d --name n8n -p 5678:5678 -v n8n_data:/home/node/.n8n ghcr.io/mroplus/n8n:enterprise
```

Or use the provided `compose.yml`:

```bash
docker volume create n8n_data
docker compose up -d
```

## Running on Kubernetes / OpenShift

The image supports arbitrary UIDs: `/home/node` is group-0 writable and `N8N_USER_FOLDER` is pinned
to `/home/node`, so it runs under OpenShift's `restricted-v2` SCC without an `anyuid` exception.

```yaml
env:
  - name: N8N_USER_FOLDER
    value: /home/node
volumeMounts:
  - name: n8n-data
    mountPath: /home/node/.n8n
```

> **`N8N_USER_FOLDER` must not include `.n8n`.** n8n appends `.n8n` itself, so setting it to
> `/home/node/.n8n` makes n8n target `/home/node/.n8n/.n8n` and fail with
> `EACCES: permission denied`.

## Troubleshooting

- Check the Actions tab for build logs
- A run that finishes in seconds means `check-version` skipped the build — the build key already
  exists in GHCR. Re-run with `force_build` to rebuild anyway.
- `Bypass patch drifted` errors mean upstream n8n moved something `bypass.sh` targets; the
  annotation names which patch needs updating.
