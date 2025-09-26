# n8n Enterprise Docker Build Workflow

This repository contains a GitHub Actions workflow that automatically builds and pushes multi-architecture n8n Docker images to GitHub Container Registry (GHCR).

## Workflow Overview

The workflow (`build.yml`) performs the following steps:

1. **Clone n8n Repository**: Clones the official n8n repository from `https://github.com/n8n-io/n8n`
2. **Setup Environment**: Installs Node.js 22 and pnpm package manager
3. **Install Dependencies**: Runs `pnpm install --frozen-lockfile`
4. **Build Project**: Executes `pnpm run build`
5. **Multi-Platform Docker Build**: Builds Docker images for both AMD64 and ARM64 architectures using Docker Buildx
6. **Create Multi-Arch Manifests**: Combines platform-specific images into multi-architecture manifests
7. **Push to GHCR**: Tags and pushes the images to `ghcr.io/mroplus/n8n:enterprise`

## Triggers

The workflow runs on:
- Push to `master` branch
- Pull requests to `master` branch
- Manual trigger via GitHub Actions UI (`workflow_dispatch`)

## Docker Image Tags

The workflow creates multiple tags for the Docker image:
- `ghcr.io/mroplus/n8n:enterprise` - Main enterprise tag (multi-arch)
- `ghcr.io/mroplus/n8n:latest` - Latest build (multi-arch, only on master branch)
- `ghcr.io/mroplus/n8n:<commit-sha>` - Specific commit version from this repository (multi-arch)
- `ghcr.io/mroplus/n8n:n8n-<n8n-commit-hash>` - Specific n8n source repository commit version (multi-arch)

Platform-specific tags are also available:
- `ghcr.io/mroplus/n8n:enterprise-amd64` - AMD64 specific image
- `ghcr.io/mroplus/n8n:enterprise-arm64` - ARM64 specific image

## Multi-Architecture Support

The Docker images are built for multiple architectures:
- **linux/amd64** - x86_64 processors (Intel/AMD)
- **linux/arm64** - ARM64 processors (Apple Silicon, ARM servers)

The workflow uses Docker Buildx to create native builds for each platform, ensuring optimal performance on both architectures.

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
# Pull the multi-architecture image (will automatically select the correct architecture)
docker pull ghcr.io/mroplus/n8n:enterprise
docker run -d --name n8n -p 5678:5678 ghcr.io/mroplus/n8n:enterprise

# Or pull a specific architecture if needed
docker pull ghcr.io/mroplus/n8n:enterprise-amd64  # For x86_64 systems
docker pull ghcr.io/mroplus/n8n:enterprise-arm64  # For ARM64 systems
```

## Troubleshooting

- Check the Actions tab in your GitHub repository for build logs
- Ensure your repository has Actions enabled
- Verify that the GitHub Container Registry is accessible from your account
- Make sure the repository visibility allows package publishing

## Monitoring

The workflow includes cleanup steps to prevent disk space issues and provides detailed logging for each build step.