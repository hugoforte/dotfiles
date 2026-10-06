#!/bin/sh

# Suite for bin/agent-guard.mjs: which shell commands the Claude Code PreToolUse hook refuses,
# which it asks about, and which it lets through untouched.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

guard="$REPO_ROOT/bin/agent-guard.mjs"

# decision <tool> <command>: prints deny, ask, or allow, as the hook would answer for that call.
decision() {
    GUARD_TOOL="$1" GUARD_COMMAND="$2" node -e "
        process.stdout.write(JSON.stringify({ tool_name: process.env.GUARD_TOOL, tool_input: { command: process.env.GUARD_COMMAND } }));
    " | node "$guard" | node -e "
        let s = '';
        process.stdin.on('data', (c) => (s += c)).on('end', () => {
            console.log(s.trim() ? JSON.parse(s).hookSpecificOutput.permissionDecision : 'allow');
        });
    "
}

nl='
'

assert_eq "a heredoc fed to python is refused" "deny" \
    "$(decision Bash "python - <<'PY'${nl}print('hi')${nl}PY")"
assert_eq "a heredoc fed to node is refused" "deny" \
    "$(decision Bash "node - <<'EOF'${nl}console.log(1)${nl}EOF")"
assert_eq "a heredoc fed to perl is refused" "deny" \
    "$(decision Bash "perl <<'EOF'${nl}print 1${nl}EOF")"
assert_eq "a heredoc redirected into a file is refused" "deny" \
    "$(decision Bash "cat > notes.md <<'EOF'${nl}doesn't${nl}EOF")"
assert_eq "a heredoc whose redirect follows the marker is refused" "deny" \
    "$(decision Bash "cat <<'EOF' > notes.md${nl}text${nl}EOF")"
assert_eq "a heredoc through tee is refused" "deny" \
    "$(decision Bash "tee notes.md <<'EOF'${nl}text${nl}EOF")"
assert_eq "perl -pi is refused" "deny" \
    "$(decision Bash "perl -pi -e 's/a/b/' bin/rig.mjs")"
assert_eq "sed -i is refused" "deny" \
    "$(decision Bash "sed -i 's/a/b/' README.md")"

assert_eq "a heredoc commit message is allowed" "allow" \
    "$(decision Bash "git commit -m \"\$(cat <<'EOF'${nl}Add a thing${nl}EOF${nl})\"")"
assert_eq "a heredoc PR body is allowed, whatever its lines hold" "allow" \
    "$(decision Bash "gh pr create --body \"\$(cat <<'EOF'${nl}> a quote${nl}EOF${nl})\"")"
assert_eq "sed without -i is allowed" "allow" \
    "$(decision Bash "sed -n 1,20p README.md")"
assert_eq "an ordinary redirect is allowed" "allow" \
    "$(decision Bash "git log --oneline > log.txt")"

assert_eq "a file heredoc after a commit-message heredoc is refused" "deny" \
    "$(decision Bash "git commit -m \"\$(cat <<'EOF'${nl}msg${nl}EOF${nl})\"${nl}cat > notes.md <<'EOF'${nl}x${nl}EOF")"
assert_eq "a heredoc redirected with an explicit descriptor is refused" "deny" \
    "$(decision Bash "cat <<EOF 1>notes.md${nl}x${nl}EOF")"
assert_eq "perl -i after another flag is refused" "deny" \
    "$(decision Bash "perl -p -i -e 's/a/b/' f")"
assert_eq "sed -i after another flag is refused" "deny" \
    "$(decision Bash "sed -E -i 's/a/b/' f")"
assert_eq "sed -i after the expression is refused" "deny" \
    "$(decision Bash "sed -e 's/a/b/' -i f")"
assert_eq "sed -i later in a pipeline is refused" "deny" \
    "$(decision Bash "cd src && sed -i 's/a/b/' f")"

assert_eq "a PR body that mentions sed -i is allowed" "allow" \
    "$(decision Bash "gh pr create --title t --body \"\$(cat <<'EOF'${nl}Refuses perl -i and sed -i edits${nl}EOF${nl})\"")"
assert_eq "a PR body that mentions gh pr merge is allowed" "allow" \
    "$(decision Bash "gh pr create --title t --body \"\$(cat <<'EOF'${nl}Asks before gh pr merge${nl}EOF${nl})\"")"
assert_eq "grepping for sed -i is allowed" "allow" \
    "$(decision Bash "grep -rn \"sed -i\" .")"
assert_eq "a title naming an interpreter is allowed" "allow" \
    "$(decision Bash "gh pr create --title \"Fix bash completion\" --body \"\$(cat <<'EOF'${nl}x${nl}EOF${nl})\"")"
assert_eq "a commit naming a .py file is allowed" "allow" \
    "$(decision Bash "git commit app.py -m \"\$(cat <<'EOF'${nl}x${nl}EOF${nl})\"")"
assert_eq "an arrow in a title is not a redirect" "allow" \
    "$(decision Bash "gh pr create --title \"Map A -> B\" --body \"\$(cat <<'EOF'${nl}x${nl}EOF${nl})\"")"
assert_eq "a here-string is not a heredoc" "allow" \
    "$(decision Bash "wc -l <<< \"\$x\" > count.txt")"
assert_eq "a heredoc sent to /dev/null is allowed" "allow" \
    "$(decision Bash "cat <<'EOF' >/dev/null${nl}x${nl}EOF")"

assert_eq "gh pr merge asks first" "ask" \
    "$(decision Bash "gh pr merge 12 --squash")"
assert_eq "gh stack merge asks first" "ask" \
    "$(decision Bash "gh stack merge 12 --merge")"
assert_eq "a merge through gh api asks first" "ask" \
    "$(decision Bash "gh api -X PUT repos/o/r/pulls/12/merge")"
assert_eq "a merge through gh api with a variable PR number asks first" "ask" \
    "$(decision Bash "gh api -X PUT \"repos/o/r/pulls/\$pr/merge\"")"
assert_eq "a GraphQL merge asks first" "ask" \
    "$(decision Bash "gh api graphql -f query='mutation { mergePullRequest(input: {}) { clientMutationId } }'")"
assert_eq "asking gh api whether a PR merged is allowed" "allow" \
    "$(decision Bash "gh api repos/o/r/pulls/12/merge")"
assert_eq "gh pr merge from PowerShell asks first" "ask" \
    "$(decision PowerShell "gh pr merge 12 --squash")"
assert_eq "PowerShell commands are only checked for merges" "allow" \
    "$(decision PowerShell "sed -i x")"
assert_eq "gh pr view is allowed" "allow" \
    "$(decision Bash "gh pr view 12")"

assert_eq "a call with no command is allowed" "allow" \
    "$(echo '{"tool_name":"Read","tool_input":{"file_path":"a"}}' | node "$guard" | wc -c | tr -d ' ' | sed 's/^0$/allow/')"

assert_summary "agent-guard"
