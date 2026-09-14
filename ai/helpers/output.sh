#!/bin/sh

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Output functions (printf: `echo` in POSIX sh does not interpret escape codes)
error() {
    printf "${RED}Error: %s${NC}\n" "$1" >&2
}

warning() {
    printf "${YELLOW}Warning: %s${NC}\n" "$1"
}

success() {
    printf "${GREEN}✓ %s${NC}\n" "$1"
}

info() {
    printf "${BLUE}%s${NC}\n" "$1"
}

# Exit with error message
die() {
    error "$1"
    exit 1
}
