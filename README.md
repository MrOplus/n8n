# n8n Enterprise Docker Build Workflow

This repository contains a GitHub Actions workflow that automatically builds and pushes n8n Docker images to GitHub Container Registry (GHCR).

## HTTP Timeout Patch for LLM Support

This repository includes the HTTP timeout patch from [Piggeldi2013/n8n-timeout-patch](https://github.com/Piggeldi2013/n8n-timeout-patch) to support long-running LLM requests without timeouts.

### What the Patch Does

- **Inbound Server Timeouts**: Relaxes Node.js HTTP(S) server timeouts that affect browser -> n8n connections
- **Outbound Fetch Timeouts**: Configures undici (Node fetch) timeouts for n8n -> LLM/API connections

### Timeout Environment Variables

The following environment variables are preconfigured in `compose.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `N8N_HTTP_REQUEST_TIMEOUT` | 0 | Disable per-request timeout |
| `N8N_HTTP_HEADERS_TIMEOUT` | 120000 | 2 minutes; must be > keep-alive |
| `N8N_HTTP_KEEPALIVE_TIMEOUT` | 65000 | 65 seconds |
| `FETCH_HEADERS_TIMEOUT` | 1800000 | 30 min for response headers |
| `FETCH_BODY_TIMEOUT` | 12000000 | 200 min for full body/stream |
| `FETCH_CONNECT_TIMEOUT` | 600000 | 10 min for connection |
| `FETCH_KEEPALIVE_TIMEOUT` | 65000 | 65 seconds |

## Workflow Overview

The workflow (`build-and-push.yml`) performs the following steps:

1. **Clone n8n Repository**: Clones the official n8n repository from `https://github.com/n8n-io/n8n`
2. **Setup Environment**: Installs Node.js 18 and pnpm package manager
3. **Install Dependencies**: Runs `pnpm install --frozen-lockfile`
4. **Build Project**: Executes `pnpm run build`
5. **Build Docker Image**: Runs `pnpm run build:docker`
6. **Push to GHCR**: Tags and pushes the image to `ghcr.io/mroplus/n8n:enterprise`

## Triggers

The workflow runs on:
- Push to `master` branch
- Pull requests to `master` branch
- Manual trigger via GitHub Actions UI (`workflow_dispatch`)

## Docker Image Tags

The workflow creates multiple tags for the Docker image:
- `ghcr.io/mroplus/n8n:enterprise` - Main enterprise tag
- `ghcr.io/mroplus/n8n:latest` - Latest build (only on master branch)
- `ghcr.io/mroplus/n8n:<commit-sha>` - Specific commit version from this repository
- `ghcr.io/mroplus/n8n:n8n-<n8n-commit-hash>` - Specific n8n source repository commit version

## Required Permissions

The workflow requires the following permissions (already configured):
- `contents: read` - To checkout the repository
- `packages: write` - To push Docker images to GHCR

## Authentication

The workflow uses the `GITHUB_TOKEN` automatically provided by GitHub Actions. No additional secrets need to be configured for GHCR access.

## Usage

1. Push changes to the `master` branch or create a pull request
2. The workflow will automatically trigger and build the n8n Docker image
3. On successful completion, the image will be available at `ghcr.io/mroplus/n8n:enterprise`

## Pulling the Image

To use the built Docker image:

```bash
docker pull ghcr.io/mroplus/n8n:enterprise
docker run -d --name n8n -p 5678:5678 ghcr.io/mroplus/n8n:enterprise
```

## Troubleshooting

- Check the Actions tab in your GitHub repository for build logs
- Ensure your repository has Actions enabled
- Verify that the GitHub Container Registry is accessible from your account
- Make sure the repository visibility allows package publishing

## Monitoring

The workflow includes cleanup steps to prevent disk space issues and provides detailed logging for each build step.