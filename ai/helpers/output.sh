#!/bin/sh

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Output functions (printf: `echo` in POSIX sh does not interpret escape codes)
#
# Prefixes match powershell/output.ps1 so both languages report the same way. ASCII on purpose:
# sync.ps1 captures this output into sync.log, and neither that file nor the Windows console is
# reliably UTF-8 - a check mark arrives there mangled.
error() {
    printf "${RED}[XX] %s${NC}\n" "$1" >&2
}

warning() {
    printf "${YELLOW}[!!] %s${NC}\n" "$1"
}

success() {
    printf "${GREEN}[OK] %s${NC}\n" "$1"
}

info() {
    printf "${BLUE}%s${NC}\n" "$1"
}

# Exit with error message
die() {
    error "$1"
    exit 1
}
