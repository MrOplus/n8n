#!/usr/bin/env bash

# Applies the license bypass and OpenShift compatibility patches to an n8n checkout.
#
# Usage:
#   ./bypass.sh           # Interactive mode
#   ./bypass.sh --auto    # Non-interactive mode for CI/CD
#
# Every patch is verified after it is applied. sed/perl exit 0 whether or not a
# pattern matched, so without these checks an upstream refactor silently produces
# a half-patched build that still reports success. Any drifted patch now fails
# the script, which fails the workflow, which stops a bad image from shipping.

# Ensure we're running with bash
if [ -z "$BASH_VERSION" ]; then
    echo "This script requires bash. Please run it with: bash $0"
    exit 1
fi

set -eo pipefail

# Check for non-interactive mode
AUTO_MODE=false
if [[ "${1:-}" == "--auto" || "${CI:-}" == "true" || -n "${GITHUB_ACTIONS:-}" ]]; then
    AUTO_MODE=true
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Collects the description of every patch that did not land, so one run reports
# all of the drift instead of stopping at the first problem.
FAILED=()

# verify <description> <file> <perl-regex>
verify() {
    local desc="$1" file="$2" pattern="$3"
    if PATTERN="$pattern" perl -0777 -ne 'exit($_ =~ /$ENV{PATTERN}/sm ? 0 : 1)' "$file"; then
        echo -e "${GREEN}  ✓ ${desc}${NC}"
    else
        echo -e "${RED}  ✗ ${desc}${NC}"
        FAILED+=("$desc")
    fi
}

# verify_absent <description> <file> <perl-regex>
verify_absent() {
    local desc="$1" file="$2" pattern="$3"
    if PATTERN="$pattern" perl -0777 -ne 'exit($_ =~ /$ENV{PATTERN}/sm ? 1 : 0)' "$file"; then
        echo -e "${GREEN}  ✓ ${desc}${NC}"
    else
        echo -e "${RED}  ✗ ${desc}${NC}"
        FAILED+=("$desc")
    fi
}

require_file() {
    if [[ ! -f "$1" ]]; then
        echo -e "${RED}Error: expected file not found: $1${NC}"
        echo -e "${RED}Upstream n8n has moved or renamed it; the patch set needs updating.${NC}"
        exit 1
    fi
}

echo -e "${GREEN}Starting license bypass application for development...${NC}"

# Check if we're in a git repository
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo -e "${RED}Error: Not in a git repository${NC}"
    exit 1
fi

# Get the current branch
CURRENT_BRANCH=$(git branch --show-current || true)
echo -e "${YELLOW}Current ref: ${CURRENT_BRANCH:-<detached>}${NC}"

LICENSE_FILE="packages/cli/src/license.ts"
LICENSE_STATE_FILE="packages/@n8n/backend-common/src/license-state.ts"
BANNER_FILE="packages/frontend/editor-ui/src/components/banners/NonProductionLicenseBanner.vue"
NEW_BANNER_FILE="packages/frontend/editor-ui/src/features/shared/banners/components/banners/NonProductionLicenseBanner.vue"
PROJECT_TABS_FILE="packages/frontend/editor-ui/src/features/collaboration/projects/components/ProjectTabs.vue"
DOCKER_FILE="docker/images/n8n/Dockerfile"

require_file "$LICENSE_FILE"
require_file "$LICENSE_STATE_FILE"
require_file "$PROJECT_TABS_FILE"
require_file "$DOCKER_FILE"

# Check if license bypass is already applied
if grep -q "return true;" "$LICENSE_FILE" && grep -q "Enterprise Edition" "$LICENSE_FILE"; then
    echo -e "${YELLOW}License bypass already applied!${NC}"
    echo -e "${GREEN}Development mode is ready.${NC}"
    exit 0
fi

echo -e "${YELLOW}Applying license bypass for development...${NC}"

# Backup current files
echo -e "${YELLOW}Creating backups...${NC}"
cp "$LICENSE_FILE" "${LICENSE_FILE}.backup"
cp "$LICENSE_STATE_FILE" "${LICENSE_STATE_FILE}.backup"

# ---------------------------------------------------------------------------
# packages/cli/src/license.ts (deprecated wrappers, still used in places)
# ---------------------------------------------------------------------------
echo -e "${YELLOW}Applying license bypass to $LICENSE_FILE...${NC}"

# Replace the license renewal warning. Matched up to the terminating semicolon
# rather than to end-of-line: upstream wraps this declaration across two lines.
perl -0777 -pi -e 's/const LICENSE_RENEWAL_DISABLED_WARNING\s*=[^;]*;/const LICENSE_RENEWAL_DISABLED_WARNING = \x27Enterprise Edition\x27;/s' "$LICENSE_FILE"

# isLicensed() is the single chokepoint every wrapper below funnels through.
perl -0777 -pi -e 's/(isLicensed\(feature: BooleanLicenseFeature\) \{)[^}]*\}/$1\n\t\treturn true;\n\t}/s' "$LICENSE_FILE"

# Collapse every `isXxxLicensed()` wrapper to a constant true.
sed -i 's/return this\.isLicensed(LICENSE_FEATURES\.[^)]*);/return true;/g' "$LICENSE_FILE"

# isAPIDisabled is inverted: the line above just turned it into `return true`,
# which would disable the public API. Force it back to false.
perl -0777 -pi -e 's/(\n\tisAPIDisabled\(\) \{)[^}]*\}/$1\n\t\treturn false;\n\t}/s' "$LICENSE_FILE"

# Quotas -> unlimited
sed -i 's/return this\.getValue(LICENSE_QUOTAS\.USERS_LIMIT) ?? UNLIMITED_LICENSE_QUOTA;/return UNLIMITED_LICENSE_QUOTA;/' "$LICENSE_FILE"
sed -i 's/return this\.getValue(LICENSE_QUOTAS\.TRIGGER_LIMIT) ?? UNLIMITED_LICENSE_QUOTA;/return UNLIMITED_LICENSE_QUOTA;/' "$LICENSE_FILE"
sed -i 's/return this\.getValue(LICENSE_QUOTAS\.VARIABLES_LIMIT) ?? UNLIMITED_LICENSE_QUOTA;/return UNLIMITED_LICENSE_QUOTA;/' "$LICENSE_FILE"
sed -i 's/return this\.getValue(LICENSE_QUOTAS\.TEAM_PROJECT_LIMIT) ?? 0;/return 999;/' "$LICENSE_FILE"

# getWorkflowHistoryPruneLimit() is a multi-line `return (...)` upstream, so the
# whole method body is replaced rather than a single line.
perl -0777 -pi -e 's/(getWorkflowHistoryPruneLimit\(\) \{).*?(\n\t\})/$1\n\t\treturn UNLIMITED_LICENSE_QUOTA;$2/s' "$LICENSE_FILE"

# Replace plan name
sed -i 's/return this\.getValue(\x27planName\x27) ?? \x27Community\x27;/return this.getValue(\x27planName\x27) ?? \x27Cracked\x27;/' "$LICENSE_FILE"

echo -e "${GREEN}✓ Applied license bypass to $LICENSE_FILE${NC}"
verify "license.ts: renewal warning rebranded" "$LICENSE_FILE" 'LICENSE_RENEWAL_DISABLED_WARNING = \x27Enterprise Edition\x27;'
verify "license.ts: isLicensed() returns true" "$LICENSE_FILE" 'isLicensed\(feature: BooleanLicenseFeature\) \{\s*return true;'
verify_absent "license.ts: no LICENSE_FEATURES checks remain" "$LICENSE_FILE" 'return this\.isLicensed\(LICENSE_FEATURES\.'
verify "license.ts: isAPIDisabled() returns false" "$LICENSE_FILE" 'isAPIDisabled\(\) \{\s*return false;'
verify "license.ts: users quota unlimited" "$LICENSE_FILE" 'getUsersLimit\(\) \{\s*return UNLIMITED_LICENSE_QUOTA;'
verify "license.ts: workflow history prune unlimited" "$LICENSE_FILE" 'getWorkflowHistoryPruneLimit\(\) \{\s*return UNLIMITED_LICENSE_QUOTA;'
verify "license.ts: team project limit raised" "$LICENSE_FILE" 'return 999;'
verify "license.ts: plan name replaced" "$LICENSE_FILE" '\x27Cracked\x27'

# ---------------------------------------------------------------------------
# packages/@n8n/backend-common/src/license-state.ts (the live code path)
# ---------------------------------------------------------------------------
echo -e "${YELLOW}Applying license bypass to $LICENSE_STATE_FILE...${NC}"

# Replace the whole isLicensed() body. `.*?` stops at the first `\n\t}`, which is
# the method's own closing brace -- nested blocks close at deeper indentation.
perl -0777 -pi -e 's/(isLicensed\(feature: BooleanLicenseFeature \| BooleanLicenseFeature\[\]\) \{).*?(\n\t\})/$1\n\t\treturn true;$2/s' "$LICENSE_STATE_FILE"

# Keep the public API enabled
perl -0777 -pi -e 's/(\n\tisAPIDisabled\(\) \{)[^}]*\}/$1\n\t\treturn false;\n\t}/s' "$LICENSE_STATE_FILE"

# Quotas -> unlimited / generous values
sed -i 's/return this\.getValue(\x27quota:users\x27) ?? UNLIMITED_LICENSE_QUOTA;/return UNLIMITED_LICENSE_QUOTA;/' "$LICENSE_STATE_FILE"
sed -i 's/return this\.getValue(\x27quota:activeWorkflows\x27) ?? UNLIMITED_LICENSE_QUOTA;/return UNLIMITED_LICENSE_QUOTA;/' "$LICENSE_STATE_FILE"
sed -i 's/return this\.getValue(\x27quota:maxVariables\x27) ?? UNLIMITED_LICENSE_QUOTA;/return UNLIMITED_LICENSE_QUOTA;/' "$LICENSE_STATE_FILE"
sed -i 's/return this\.getValue(\x27quota:aiCredits\x27) ?? 0;/return 9999;/' "$LICENSE_STATE_FILE"
sed -i 's/return this\.getValue(\x27quota:workflowHistoryPrune\x27) ?? UNLIMITED_LICENSE_QUOTA;/return UNLIMITED_LICENSE_QUOTA;/' "$LICENSE_STATE_FILE"
sed -i 's/return this\.getValue(\x27quota:insights:maxHistoryDays\x27) ?? 7;/return 365;/' "$LICENSE_STATE_FILE"
sed -i 's/return this\.getValue(\x27quota:insights:retention:maxAgeDays\x27) ?? 180;/return 365;/' "$LICENSE_STATE_FILE"
sed -i 's/return this\.getValue(\x27quota:insights:retention:pruneIntervalDays\x27) ?? 24;/return 365;/' "$LICENSE_STATE_FILE"
sed -i 's/return this\.getValue(\x27quota:maxTeamProjects\x27) ?? 0;/return 99999;/' "$LICENSE_STATE_FILE"
sed -i 's/return this\.getValue(\x27quota:evaluations:maxWorkflows\x27) ?? 0;/return 99999;/' "$LICENSE_STATE_FILE"

echo -e "${GREEN}✓ Applied license bypass to $LICENSE_STATE_FILE${NC}"
verify "license-state.ts: isLicensed() returns true" "$LICENSE_STATE_FILE" 'isLicensed\(feature: BooleanLicenseFeature \| BooleanLicenseFeature\[\]\) \{\s*return true;\s*\}'
verify "license-state.ts: isAPIDisabled() returns false" "$LICENSE_STATE_FILE" 'isAPIDisabled\(\) \{\s*return false;'
verify_absent "license-state.ts: no users quota lookup remains" "$LICENSE_STATE_FILE" 'getValue\(\x27quota:users\x27\)'
verify_absent "license-state.ts: no variables quota lookup remains" "$LICENSE_STATE_FILE" 'getValue\(\x27quota:maxVariables\x27\)'
verify_absent "license-state.ts: no team project quota lookup remains" "$LICENSE_STATE_FILE" 'getValue\(\x27quota:maxTeamProjects\x27\)'
verify_absent "license-state.ts: no evaluations quota lookup remains" "$LICENSE_STATE_FILE" 'getValue\(\x27quota:evaluations:maxWorkflows\x27\)'
verify_absent "license-state.ts: no insights retention lookups remain" "$LICENSE_STATE_FILE" 'getValue\(\x27quota:insights:'

# ---------------------------------------------------------------------------
# Frontend: always show the Variables tab
# ---------------------------------------------------------------------------
echo -e "${YELLOW}Fixing Variables tab visibility in ProjectTabs.vue...${NC}"

# Anchored on the tab push rather than on the condition text, so upstream
# rewording the condition (which it has already done twice) does not break this.
perl -0777 -pi -e 's/if \([^\n]*\) \{(\n\t*tabs\.push\(createTab\(\x27mainSidebar\.variables\x27)/if (true) {$1/s' "$PROJECT_TABS_FILE"

verify "ProjectTabs.vue: Variables tab always visible" "$PROJECT_TABS_FILE" 'if \(true\) \{\s*tabs\.push\(createTab\(\x27mainSidebar\.variables\x27'

# ---------------------------------------------------------------------------
# Frontend: hide the non-production license banner
# ---------------------------------------------------------------------------
if [[ -f "$NEW_BANNER_FILE" ]]; then
    echo -e "${YELLOW}Disabling NonProductionLicenseBanner...${NC}"
    sed -i 's/<BaseBanner name="NON_PRODUCTION_LICENSE"/<BaseBanner v-if="false" name="NON_PRODUCTION_LICENSE"/' "$NEW_BANNER_FILE"
    verify "NonProductionLicenseBanner disabled" "$NEW_BANNER_FILE" '<BaseBanner v-if="false" name="NON_PRODUCTION_LICENSE"'
elif [[ -f "$BANNER_FILE" ]]; then
    echo -e "${YELLOW}Disabling NonProductionLicenseBanner (old location)...${NC}"
    sed -i 's/<BaseBanner /<BaseBanner v-if="false" /' "$BANNER_FILE"
    verify "NonProductionLicenseBanner disabled (old location)" "$BANNER_FILE" '<BaseBanner v-if="false" '
else
    echo -e "${RED}  ✗ NonProductionLicenseBanner not found at either known path${NC}"
    FAILED+=("NonProductionLicenseBanner not found")
fi

# ---------------------------------------------------------------------------
# Dockerfile
# ---------------------------------------------------------------------------
echo -e "${YELLOW}Patching $DOCKER_FILE...${NC}"

# Report as a stable release rather than a dev build
sed -i 's/^ARG N8N_RELEASE_TYPE=dev$/ARG N8N_RELEASE_TYPE=stable/' "$DOCKER_FILE"

# OpenShift / arbitrary-UID support (issue #8).
#
# Upstream does `chown -R node:node /home/node` and leaves mode 0755, so only UID
# 1000 can write there. OpenShift's restricted-v2 SCC ignores `USER node` and runs
# the container as a random UID in group 0, which then cannot create ~/.n8n and
# dies with `EACCES: permission denied, mkdir '/home/node/.n8n'`. Granting group 0
# the owner's permissions is the standard fix and is a no-op for `docker run`.
#
# N8N_USER_FOLDER is pinned for the same reason: an arbitrary UID has no
# /etc/passwd entry, so $HOME resolves to `/` and n8n would target `/.n8n`.
# Note that n8n appends `.n8n` itself -- this must be /home/node, not /home/node/.n8n.
if ! grep -q 'chgrp -R 0 /home/node' "$DOCKER_FILE"; then
    perl -0777 -pi -e 's{^USER node$}{ENV N8N_USER_FOLDER=/home/node\nRUN chgrp -R 0 /home/node && chmod -R g=u /home/node\nUSER node}m' "$DOCKER_FILE"
fi

verify "Dockerfile: release type is stable" "$DOCKER_FILE" '^ARG N8N_RELEASE_TYPE=stable$'
verify "Dockerfile: /home/node writable by group 0" "$DOCKER_FILE" 'RUN chgrp -R 0 /home/node && chmod -R g=u /home/node'
verify "Dockerfile: N8N_USER_FOLDER pinned" "$DOCKER_FILE" '^ENV N8N_USER_FOLDER=/home/node$'

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo -e "${YELLOW}Checking git status...${NC}"
git status --short

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo
    echo -e "${RED}=== ${#FAILED[@]} patch(es) did not apply ===${NC}"
    for desc in "${FAILED[@]}"; do
        echo -e "${RED}  - ${desc}${NC}"
        if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
            echo "::error title=Bypass patch drifted::${desc}"
        fi
    done
    echo -e "${RED}Upstream n8n has changed. Refusing to continue with a partial bypass.${NC}"
    exit 1
fi

echo
echo -e "${GREEN}License bypass application completed -- all patches verified.${NC}"
echo -e "${YELLOW}Backup files have been created with .backup extension.${NC}"

# Optional: Commit the changes
if [[ "$AUTO_MODE" == "true" ]]; then
    echo -e "${GREEN}Auto mode: Skipping commit prompt${NC}"
else
    read -p "Do you want to commit these changes? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git add .
        git commit -m "Apply license bypass for development

- Bypassed all license checks to return true
- Set unlimited quotas for development
- Made the image usable under an arbitrary UID (OpenShift)
"
        echo -e "${GREEN}Changes committed successfully!${NC}"
    fi
fi

echo -e "${GREEN}Script completed successfully!${NC}"
echo -e "${YELLOW}Note: You must rebuild n8n (pnpm run build) for changes to take effect.${NC}"
