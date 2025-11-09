#!/usr/bin/env bash

# Script to apply license bypass modifications for development
# This script applies the license bypass changes from commit 869baecb059671281df20ede76413c20f78bfbfc
#
# Usage:
#   ./apply-license-bypass.sh           # Interactive mode
#   ./apply-license-bypass.sh --auto    # Non-interactive mode for CI/CD

# Ensure we're running with bash
if [ -z "$BASH_VERSION" ]; then
    echo "This script requires bash. Please run it with: bash $0"
    exit 1
fi

set -e

# Check for non-interactive mode
AUTO_MODE=false
if [[ "$1" == "--auto" || "$CI" == "true" || -n "$GITHUB_ACTIONS" ]]; then
    AUTO_MODE=true
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting license bypass application for development...${NC}"

# Check if we're in a git repository
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo -e "${RED}Error: Not in a git repository${NC}"
    exit 1
fi

# Get the current branch
CURRENT_BRANCH=$(git branch --show-current)
echo -e "${YELLOW}Current branch: ${CURRENT_BRANCH}${NC}"

# Check if license bypass is already applied
LICENSE_FILE="packages/cli/src/license.ts"
LICENSE_STATE_FILE="packages/@n8n/backend-common/src/license-state.ts"
BANNER_FILE="packages/frontend/editor-ui/src/components/banners/NonProductionLicenseBanner.vue"
DOCKER_FILE="docker/images/n8n/Dockerfile"

if [[ ! -f "$LICENSE_FILE" ]]; then
    echo -e "${RED}Error: License file not found: $LICENSE_FILE${NC}"
    exit 1
fi

if [[ ! -f "$LICENSE_STATE_FILE" ]]; then
    echo -e "${RED}Error: License state file not found: $LICENSE_STATE_FILE${NC}"
    exit 1
fi

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

# Apply license bypass to license.ts
echo -e "${YELLOW}Applying license bypass to $LICENSE_FILE...${NC}"

# Replace the license renewal warning
sed -i 's/const LICENSE_RENEWAL_DISABLED_WARNING =.*/const LICENSE_RENEWAL_DISABLED_WARNING = '\''Enterprise Edition'\'';/' "$LICENSE_FILE"

# Replace all isLicensed method returns with true
sed -i '/isLicensed(feature: BooleanLicenseFeature) {/,/}/ { 
    s/return this\.manager?.hasFeatureEnabled(feature) ?? false;/return true;/
}' "$LICENSE_FILE"

# Replace all license check methods to return true
sed -i 's/return this\.isLicensed(LICENSE_FEATURES\.[^)]*);/return true;/g' "$LICENSE_FILE"

# Replace isAPIDisabled to return false (ensure API access is enabled)
sed -i '/isAPIDisabled() {/,/}/ {
    s/return this\.isLicensed(LICENSE_FEATURES\.API_DISABLED);/return false;/
    s/return true;/return false;/
}' "$LICENSE_FILE"

# Replace quota methods to return unlimited values
sed -i 's/return this\.getValue(LICENSE_QUOTAS\.USERS_LIMIT) ?? UNLIMITED_LICENSE_QUOTA;/return UNLIMITED_LICENSE_QUOTA;/' "$LICENSE_FILE"
sed -i 's/return this\.getValue(LICENSE_QUOTAS\.TRIGGER_LIMIT) ?? UNLIMITED_LICENSE_QUOTA;/return UNLIMITED_LICENSE_QUOTA;/' "$LICENSE_FILE"
sed -i 's/return this\.getValue(LICENSE_QUOTAS\.VARIABLES_LIMIT) ?? UNLIMITED_LICENSE_QUOTA;/return UNLIMITED_LICENSE_QUOTA;/' "$LICENSE_FILE"
sed -i 's/return this\.getValue(LICENSE_QUOTAS\.AI_CREDITS) ?? 0;/return 0;/' "$LICENSE_FILE"
sed -i 's/return this\.getValue(LICENSE_QUOTAS\.WORKFLOW_HISTORY_PRUNE_LIMIT) ?? UNLIMITED_LICENSE_QUOTA;/return UNLIMITED_LICENSE_QUOTA;/' "$LICENSE_FILE"
sed -i 's/return this\.getValue(LICENSE_QUOTAS\.TEAM_PROJECT_LIMIT) ?? 0;/return 999;/' "$LICENSE_FILE"

# Replace plan name
sed -i 's/return this\.getValue('\''planName'\'') ?? '\''Community'\'';/return this.getValue('\''planName'\'') ?? '\''Cracked'\'';/' "$LICENSE_FILE"

echo -e "${GREEN}✓ Applied license bypass to $LICENSE_FILE${NC}"

# Apply license bypass to license-state.ts
echo -e "${YELLOW}Applying license bypass to $LICENSE_STATE_FILE...${NC}"

# Replace isLicensed method to always return true (handles both single feature and array)
# Use a simpler approach: find the method and replace its entire body
awk '
/isLicensed\(feature: BooleanLicenseFeature \| BooleanLicenseFeature\[\]\) \{/ {
    print
    print "\t\treturn true;"
    in_method = 1
    brace_count = 1
    next
}
in_method {
    if (/\{/) brace_count++
    if (/\}/) brace_count--
    if (brace_count == 0) {
        print "\t}"
        in_method = 0
    }
    next
}
{ print }
' "$LICENSE_STATE_FILE" > "$LICENSE_STATE_FILE.tmp" && mv "$LICENSE_STATE_FILE.tmp" "$LICENSE_STATE_FILE"

# Replace isAPIDisabled to return false (ensure API access is enabled)
sed -i '/isAPIDisabled() {/,/}/ {
    s/return this\.isLicensed(.*feat:apiDisabled.*);/return false;/
    s/return true;/return false;/
}' "$LICENSE_STATE_FILE"

# Replace quota methods to return unlimited/high values
sed -i 's/return this\.getValue('\''quota:users'\'') ?? UNLIMITED_LICENSE_QUOTA;/return UNLIMITED_LICENSE_QUOTA;/' "$LICENSE_STATE_FILE"
sed -i 's/return this\.getValue('\''quota:activeWorkflows'\'') ?? UNLIMITED_LICENSE_QUOTA;/return UNLIMITED_LICENSE_QUOTA;/' "$LICENSE_STATE_FILE"
sed -i 's/return this\.getValue('\''quota:maxVariables'\'') ?? UNLIMITED_LICENSE_QUOTA;/return UNLIMITED_LICENSE_QUOTA;/' "$LICENSE_STATE_FILE"
sed -i 's/return this\.getValue('\''quota:aiCredits'\'') ?? 0;/return 9999;/' "$LICENSE_STATE_FILE"
sed -i 's/return this\.getValue('\''quota:workflowHistoryPrune'\'') ?? UNLIMITED_LICENSE_QUOTA;/return UNLIMITED_LICENSE_QUOTA;/' "$LICENSE_STATE_FILE"
sed -i 's/return this\.getValue('\''quota:insights:maxHistoryDays'\'') ?? 7;/return 365;/' "$LICENSE_STATE_FILE"
sed -i 's/return this\.getValue('\''quota:insights:retention:maxAgeDays'\'') ?? 180;/return 365;/' "$LICENSE_STATE_FILE"
sed -i 's/return this\.getValue('\''quota:insights:retention:pruneIntervalDays'\'') ?? 24;/return 365;/' "$LICENSE_STATE_FILE"
sed -i 's/return this\.getValue('\''quota:maxTeamProjects'\'') ?? 0;/return 99999;/' "$LICENSE_STATE_FILE"
sed -i 's/return this\.getValue('\''quota:evaluations:maxWorkflows'\'') ?? 0;/return 99999;/' "$LICENSE_STATE_FILE"

echo -e "${GREEN}✓ Applied license bypass to $LICENSE_STATE_FILE${NC}"

# Disable NonProductionLicenseBanner (new location and structure)
NEW_BANNER_FILE="packages/frontend/editor-ui/src/features/shared/banners/components/banners/NonProductionLicenseBanner.vue"
if [[ -f "$NEW_BANNER_FILE" ]]; then
    echo -e "${YELLOW}Disabling NonProductionLicenseBanner...${NC}"
    sed -i 's/<BaseBanner name="NON_PRODUCTION_LICENSE"/<BaseBanner v-if="false" name="NON_PRODUCTION_LICENSE"/' "$NEW_BANNER_FILE"
    echo -e "${GREEN}✓ Disabled NonProductionLicenseBanner${NC}"
elif [[ -f "$BANNER_FILE" ]]; then
    echo -e "${YELLOW}Disabling NonProductionLicenseBanner (old location)...${NC}"
    sed -i 's/<BaseBanner /<BaseBanner v-if="false" /' "$BANNER_FILE"
    echo -e "${GREEN}✓ Disabled NonProductionLicenseBanner${NC}"
fi

# Update Dockerfile to have stable release type
sed -i 's/^ARG N8N_RELEASE_TYPE=dev$/ARG N8N_RELEASE_TYPE=stable/' "$DOCKER_FILE"

# Final check
echo -e "${YELLOW}Checking git status...${NC}"
git status

echo -e "${GREEN}License bypass application completed!${NC}"
echo -e "${YELLOW}Development mode is now active with license restrictions bypassed.${NC}"
echo -e "${YELLOW}Backup files have been created with .backup extension.${NC}"

# Optional: Commit the changes
if [[ "$AUTO_MODE" == "true" ]]; then
    echo -e "${GREEN}Auto mode: Skipping commit prompt${NC}"
    echo -e "${YELLOW}Changes applied successfully in CI/CD mode${NC}"
else
    read -p "Do you want to commit these changes? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git add .
        git commit -m "Apply license bypass for development

- Bypassed all license checks to return true
- Set unlimited quotas for development
- Removed license decorators from controllers
- Applied development-friendly license modifications
"
        echo -e "${GREEN}Changes committed successfully!${NC}"
    fi
fi

echo -e "${GREEN}Script completed successfully!${NC}"
echo -e "${YELLOW}n8n is now ready for development with all license restrictions bypassed.${NC}"
