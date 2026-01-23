---
applyTo: "ai/**/*.sh"
---

# Shell Script Development Patterns

This file contains implementation patterns specific to shell scripts in the AI configuration layer.

## Script Header and Strictness

**Pattern:** Use shebang and strict error handling.

```bash
#!/bin/sh

export ZSH=$HOME/.dotfiles

# Source helper functions
. $ZSH/ai/helpers/output.sh
. $ZSH/ai/helpers/json-settings.sh

set -e  # Exit on error
```

**Key points:**
- Use `#!/bin/sh` for maximum portability (not `#!/bin/bash`)
- Set `ZSH` variable to dotfiles root (legacy name, kept for compatibility)
- Source helper libraries for common functions
- Use `set -e` to fail fast on errors

## Output Helper Functions

**Pattern:** Use color-coded output functions from `helpers/output.sh`.

```bash
# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Output functions
error() {
    echo "${RED}Error: $1${NC}" >&2
}

warning() {
    echo "${YELLOW}Warning: $1${NC}"
}

success() {
    echo "${GREEN}✓ $1${NC}"
}

info() {
    echo "${BLUE}$1${NC}"
}

# Exit with error message
die() {
    error "$1"
    exit 1
}
```

**Usage:**
```bash
success "Symlinked CLAUDE.md"
warning "jq not found - JSON merging skipped"
error "Invalid configuration"
info "Installing Claude configuration…"
die "Critical error occurred"  # Exit with error
```

**Key points:**
- Use ANSI color codes for consistent output
- `error()` writes to stderr (`>&2`)
- `success()` includes checkmark (✓) for visual confirmation
- `die()` combines error message and exit

## Symlink Creation Pattern

**Pattern:** Remove existing symlinks, then create new ones with absolute paths.

```bash
# Symlink CLAUDE.md
if [ "$INSTALL_CLAUDE_MD" = "true" ]; then
    rm -f ~/.claude/CLAUDE.md
    ln -sf $ZSH/ai/CLAUDE.md ~/.claude/CLAUDE.md
    success "Symlinked CLAUDE.md"
fi

# Symlink agents
if [ "$INSTALL_AGENTS" = "true" ]; then
    mkdir -p ~/.claude/agents
    for agent in $ZSH/ai/agents/*.*; do
        agent_name=$(basename "$agent")
        rm -f ~/.claude/agents/"$agent_name"
        ln -sf "$agent" ~/.claude/agents/"$agent_name"
    done
    success "Symlinked agents"
fi
```

**Key points:**
- Use `rm -f` to remove existing symlinks without error
- Use `ln -sf` for symbolic links (force overwrite)
- Use `mkdir -p` to create directories if they don't exist
- Always use absolute paths (via `$ZSH` variable)
- Use `basename` to extract filename from path

## Uninstall Function Pattern

**Pattern:** Provide uninstall functionality that checks link type before removing.

```bash
uninstall_claude_config() {
    info "Uninstalling Claude configuration…"

    # Remove CLAUDE.md symlink
    if [ "$INSTALL_CLAUDE_MD" = "true" ]; then
        if [ -L ~/.claude/CLAUDE.md ]; then
            rm -f ~/.claude/CLAUDE.md
            success "Removed CLAUDE.md symlink"
        elif [ -f ~/.claude/CLAUDE.md ]; then
            warning "~/.claude/CLAUDE.md is a regular file, not a symlink - skipping"
        fi
    fi

    # Remove agent symlinks
    if [ "$INSTALL_AGENTS" = "true" ]; then
        if [ -d ~/.claude/agents ]; then
            for agent in ~/.claude/agents/*.*; do
                if [ -L "$agent" ]; then
                    rm -f "$agent"
                fi
            done
            success "Removed agent symlinks"
        fi
    fi

    echo ""
    success "Claude configuration uninstalled successfully!"
    info "Note: MCP servers, hooks, and permissions are not removed by uninstall"
}
```

**Key points:**
- Check if file is a symlink with `[ -L path ]`
- Check if file is a regular file with `[ -f path ]`
- Check if directory exists with `[ -d path ]`
- Only remove symlinks, warn about regular files
- Provide informative messages about what's not removed

## Command-Line Argument Parsing

**Pattern:** Use `case` statement with flag variables for flexible argument handling.

```bash
# Parse command line options
UNINSTALL=false
INSTALL_CLAUDE_MD=true
INSTALL_AGENTS=true
INSTALL_MCP=true

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --uninstall         Remove symlinks for file-based components"
    echo "  --claude-md-only    Install only CLAUDE.md file"
    echo "  --agents-only       Install only agent files"
    echo "  --no-claude-md      Skip CLAUDE.md installation"
    echo "  -h, --help          Show this help message"
    echo ""
}

# Parse arguments
while [ $# -gt 0 ]; do
    case $1 in
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        --claude-md-only)
            INSTALL_CLAUDE_MD=true
            INSTALL_AGENTS=false
            INSTALL_MCP=false
            shift
            ;;
        --no-claude-md)
            INSTALL_CLAUDE_MD=false
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# If uninstall flag is set, uninstall and exit
if [ "$UNINSTALL" = "true" ]; then
    uninstall_claude_config
    exit 0
fi
```

**Key points:**
- Define flag variables at top with default values
- Use `while [ $# -gt 0 ]` to loop through arguments
- Use `case $1 in` to match patterns
- Support both short (`-h`) and long (`--help`) options
- Always `shift` after processing an argument
- Provide `show_help` function for usage information
- Handle unknown options with error and help display

## JSON Settings Merge Pattern

**Pattern:** Safely merge JSON into settings files with validation.

```bash
# Merge JSON configuration into a settings file
merge_json_settings() {
    local settings_file="$1"
    local json_config="$2" 
    local feature_name="$3"
    
    # Validate parameters
    if [ -z "$settings_file" ] || [ -z "$json_config" ] || [ -z "$feature_name" ]; then
        error "merge_json_settings: Missing required parameters"
        return 1
    fi
    
    # Check if jq is available
    if ! command -v jq > /dev/null 2>&1; then
        warning "jq not found - ${feature_name} configuration skipped"
        info "Install jq and re-run this script to configure ${feature_name}"
        return 1
    fi
    
    # Validate the JSON configuration
    if ! echo "$json_config" | jq empty > /dev/null 2>&1; then
        warning "Invalid ${feature_name} JSON configuration - skipping"
        return 1
    fi
    
    # Ensure settings file exists
    if [ ! -f "$settings_file" ]; then
        echo '{"model": "sonnet"}' > "$settings_file"
        info "Created initial settings.json"
    fi
    
    # Merge configuration into existing settings
    if ! jq --argjson new "$json_config" '
        def deep_merge(a; b):
            a as $a | b as $b |
            if ($a | type) == "object" and ($b | type) == "object" then
                reduce ([$a, $b] | add | keys_unsorted[]) as $key ({};
                    .[$key] = deep_merge($a[$key]; $b[$key])
                )
            elif ($a | type) == "array" and ($b | type) == "array" then
                ($a + $b) | unique
            elif $b == null then
                $a
            else
                $b
            end;
        deep_merge(.; $new)
    ' "$settings_file" > "${settings_file}.tmp" 2>/dev/null; then
        rm -f "${settings_file}.tmp"
        warning "Failed to merge ${feature_name} configuration"
        return 1
    fi
    
    # Validate the merged result
    if ! jq empty "${settings_file}.tmp" > /dev/null 2>&1; then
        rm -f "${settings_file}.tmp"
        warning "Generated invalid JSON - ${feature_name} configuration skipped"
        return 1
    fi
    
    # Atomically replace the settings file
    mv "${settings_file}.tmp" "$settings_file"
    return 0
}
```

**Key points:**
- Use `local` for function-scoped variables
- Validate all parameters before processing
- Check for `jq` availability with `command -v jq`
- Validate JSON with `jq empty`
- Create temporary file with `.tmp` extension
- Use deep merge function that handles arrays properly
- Atomically replace file with `mv` (safer than direct write)
- Clean up temporary files on error
- Return 0 for success, 1 for failure

## Dependency Checking Pattern

**Pattern:** Check for optional dependencies and provide helpful messages.

```bash
# Check if jq is available
if ! command -v jq > /dev/null 2>&1; then
    warning "jq not found - JSON merging skipped"
    info "Install jq and re-run this script to enable this feature"
    return 1
fi
```

**Key points:**
- Use `command -v` to check if command exists
- Redirect output to `/dev/null` to suppress messages
- Check exit code with `2>&1` to catch stderr
- Provide clear warning about what's skipped
- Provide installation guidance
- Use `return 1` to signal failure (not `exit`, which would terminate script)

## Loop Over Files Pattern

**Pattern:** Use glob patterns and `basename` to process files.

```bash
# Symlink all agent files
for agent in $ZSH/ai/agents/*.*; do
    agent_name=$(basename "$agent")
    rm -f ~/.claude/agents/"$agent_name"
    ln -sf "$agent" ~/.claude/agents/"$agent_name"
done
```

**Key points:**
- Use glob patterns (`*.*`) to match files
- Use `basename` to extract filename
- Quote variables to handle filenames with spaces
- Process each file individually in loop

## Multi-Line String Data Pattern

**Pattern:** Use here-strings for multi-line configuration data.

```bash
# Define MCP servers as a list of entries
# Format: "name|description|command"
MCP_SERVERS="
posthog-db|PostHog database connection|/path/to/postgres-mcp --access-mode=restricted
puppeteer|Puppeteer web automation|npx -y @modelcontextprotocol/server-puppeteer
memory|Persistent memory across sessions|npx -y @modelcontextprotocol/server-memory
git|Structured git operations|npx -y @modelcontextprotocol/server-git
"

# Process each line
echo "$MCP_SERVERS" | while IFS='|' read -r name description command; do
    [ -z "$name" ] && continue  # Skip empty lines
    # ... process server entry ...
done
```

**Key points:**
- Use multi-line strings for structured data
- Use pipe (`|`) as delimiter for easy parsing
- Use `IFS='|' read -r` to split fields
- Skip empty lines with `[ -z "$name" ] && continue`
- Include comments to document data format

## Conditional Installation Blocks

**Pattern:** Use flag variables to control which components to install.

```bash
if [ "$INSTALL_CLAUDE_MD" = "true" ]; then
    rm -f ~/.claude/CLAUDE.md
    ln -sf $ZSH/ai/CLAUDE.md ~/.claude/CLAUDE.md
    success "Symlinked CLAUDE.md"
fi

if [ "$INSTALL_AGENTS" = "true" ]; then
    mkdir -p ~/.claude/agents
    for agent in $ZSH/ai/agents/*.*; do
        agent_name=$(basename "$agent")
        rm -f ~/.claude/agents/"$agent_name"
        ln -sf "$agent" ~/.claude/agents/"$agent_name"
    done
    success "Symlinked agents"
fi
```

**Key points:**
- Use string comparison with `=` (not `==`)
- Use `"true"` and `"false"` string values for flags
- Wrap condition in `[ ]` with spaces
- Group related operations in each block
- Provide success message after each block

## Function Return Values

**Pattern:** Use return codes to signal success/failure.

```bash
merge_json_settings() {
    # ... validation ...
    
    if [ -z "$settings_file" ]; then
        error "Missing required parameter"
        return 1  # Failure
    fi
    
    # ... processing ...
    
    if ! jq empty "$settings_file"; then
        warning "Invalid JSON"
        return 1  # Failure
    fi
    
    return 0  # Success
}

# Usage
if merge_json_settings "$file" "$json" "MCP"; then
    success "Configuration merged"
else
    warning "Merge failed, continuing..."
fi
```

**Key points:**
- Return 0 for success
- Return 1 (or other non-zero) for failure
- Check return value with `if function_name; then`
- Use return values for flow control
