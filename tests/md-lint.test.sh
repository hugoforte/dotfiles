#!/bin/sh

# Suite for bin/md-lint.mjs: which arguments reach markdownlint-cli2, and when a repo's own
# config takes over from the dotfiles default. markdownlint-cli2 itself is not run here.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

module="$REPO_ROOT/bin/md-lint.mjs"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# lint_args <own config: true|false> [args...]: prints the markdownlint-cli2 arguments, one per
# line, with the default config's path replaced by DEFAULT. The arguments go through the
# environment, space-separated: with an argv[1], the module would take itself to be run directly.
lint_args() {
    own="$1"
    shift
    MD_MODULE="$module" MD_OWN="$own" MD_ARGS="$*" node --input-type=module -e "
        import { pathToFileURL } from 'node:url';
        const { markdownlintArguments, defaultConfig } = await import(pathToFileURL(process.env.MD_MODULE).href);
        const args = markdownlintArguments(process.env.MD_ARGS.split(' ').filter(Boolean), process.env.MD_OWN === 'true');
        console.log(args.map((a) => (a === defaultConfig ? 'DEFAULT' : a)).join('\n'));
    "
}

# own_config <dir>: prints true or false.
own_config() {
    MD_MODULE="$module" MD_DIR="$1" node --input-type=module -e "
        import { pathToFileURL } from 'node:url';
        const { hasOwnConfig } = await import(pathToFileURL(process.env.MD_MODULE).href);
        console.log(hasOwnConfig(process.env.MD_DIR));
    "
}

nl='
'

assert_eq "with no arguments, every markdown file is linted with the default config" \
    "--config${nl}DEFAULT${nl}**/*.md" \
    "$(lint_args false)"
assert_eq "a file argument replaces the glob" \
    "--config${nl}DEFAULT${nl}README.md" \
    "$(lint_args false README.md)"
assert_eq "arguments pass through in order" \
    "--config${nl}DEFAULT${nl}--fix${nl}a.md" \
    "$(lint_args false --fix a.md)"
assert_eq "a repo with its own config gets no --config" \
    "README.md" \
    "$(lint_args true README.md)"

assert_eq "the default config is the one the repo ships" \
    "true" \
    "$(MD_MODULE="$module" node --input-type=module -e "
        import { existsSync } from 'node:fs';
        import { pathToFileURL } from 'node:url';
        const { defaultConfig } = await import(pathToFileURL(process.env.MD_MODULE).href);
        console.log(existsSync(defaultConfig));
    ")"

assert_eq "a directory without a config has none of its own" "false" "$(own_config "$work")"
: > "$work/.markdownlint-cli2.jsonc"
assert_eq "a .markdownlint-cli2.jsonc counts as the repo's own config" "true" "$(own_config "$work")"
rm "$work/.markdownlint-cli2.jsonc"
: > "$work/.markdownlint.yaml"
assert_eq "a .markdownlint.yaml counts as the repo's own config" "true" "$(own_config "$work")"

assert_summary "md-lint"
