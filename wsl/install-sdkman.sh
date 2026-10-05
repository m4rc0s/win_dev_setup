#!/usr/bin/env bash
# Installs SDKMAN inside a WSL distro, for JDK management on the Linux side.
#
# This is additive, not a replacement: jabba remains the native-Windows JDK
# manager (see ../configuration.dsc.yaml and ../bootstrap.ps1). SDKMAN is for
# whoever builds or runs JVM projects from inside WSL.
#
# Run from inside a WSL shell (not PowerShell):
#   bash wsl/install-sdkman.sh
#
# Idempotent: re-running skips the install if SDKMAN is already present.

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}==> Checking for an existing SDKMAN install...${NC}"

if [ -d "$HOME/.sdkman" ]; then
    echo -e "${GREEN}    Found: $HOME/.sdkman - nothing to do.${NC}"
    exit 0
fi

echo -e "${CYAN}==> Installing SDKMAN...${NC}"
curl -s "https://get.sdkman.io" | bash

echo ""
echo -e "${GREEN}==> SDKMAN installed.${NC}"
echo -e "${YELLOW}    Open a new shell (or run 'source \"\$HOME/.sdkman/bin/sdkman-init.sh\"') to start using it.${NC}"
