#!/bin/sh

# Fixture suite for macos/install-cswap-agent.sh: the LaunchAgent plist it writes runs one
# `cswap auto --once` at load and every minute, trimming its log first; it loads the agent through
# launchctl, a re-run with nothing changed leaves the running agent alone, --check reports drift,
# --uninstall takes it out, and with no cswap it refuses and writes nothing. launchctl and cswap are
# stubs; where plutil exists (macOS), the plist must pass its lint.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

home="$work/home dir"
stubs="$work/stubs"
mkdir -p "$home" "$stubs"
# launchctl logs each call. `print` answers that the job is loaded only once a bootstrap has been
# logged since the last bootout; `bootstrap` fails while $work/bootstrap-fails exists.
cat > "$stubs/launchctl" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$work/launchctl.log"
case "\$1" in
    print) [ "\$(grep -E '^(bootstrap|bootout)' "$work/launchctl.log" | tail -n 1 | cut -d' ' -f1)" = bootstrap ] ;;
    bootstrap) [ ! -e "$work/bootstrap-fails" ] ;;
esac
EOF
printf '#!/bin/sh\n' > "$stubs/cswap"
chmod +x "$stubs/launchctl" "$stubs/cswap"

HOME="$home"; export HOME
# Only the stubs and the system's own tools, so a real cswap on this machine is never found.
PATH="$stubs:/usr/bin:/bin"; export PATH

plist="$home/Library/LaunchAgents/local.dotfiles.cswap-auto.plist"
log="$home/Library/Logs/cswap-auto.log"
agent()   { (cd "$work" && sh "$REPO_ROOT/macos/install-cswap-agent.sh" "$@" 2>&1); }
has()     { if grep -qF -- "$1" "$plist"; then echo y; else echo n; fi; }
# after <key>: the plist line that follows <key>$1</key>, which holds its value
after()   { grep -A 1 -F "<key>$1</key>" "$plist" | tail -n 1 | sed 's/^ *//'; }
exists()  { if [ -e "$1" ]; then echo y; else echo n; fi; }
says()    { case "$out" in *"$1"*) echo y ;; *) echo n ;; esac; }
calls()   { if [ -e "$work/launchctl.log" ]; then grep -E '^(bootstrap|bootout)' "$work/launchctl.log"; fi; }
uid="$(id -u)"

out="$(agent)"; rc=$?
assert_eq "install succeeds" "0" "$rc"
assert_eq "it writes the plist" "y" "$(exists "$plist")"
assert_eq "the agent is labelled local.dotfiles.cswap-auto, naming no one" "<string>local.dotfiles.cswap-auto</string>" "$(after Label)"
assert_eq "it runs the cswap on PATH, by its full path" "y" "$(has "<string>$stubs/cswap</string>")"
assert_eq "one check-and-switch a run" "y" "$(has "auto --once --json")"
assert_eq "at load" "<true/>" "$(after RunAtLoad)"
assert_eq "and every minute" "<integer>60</integer>" "$(after StartInterval)"
assert_eq "it is never kept running between runs" "n" "$(has "<key>KeepAlive</key>")"
assert_eq "it logs to ~/Library/Logs/cswap-auto.log" "y" "$(has "<string>$log</string>")"
assert_eq "it loads the agent" "bootout gui/$uid/local.dotfiles.cswap-auto
bootstrap gui/$uid $plist" "$(calls)"
if command -v plutil > /dev/null 2>&1; then
    assert_eq "plutil accepts the plist" "0" "$(plutil -lint "$plist" > /dev/null 2>&1; echo $?)"
fi

# The command the agent runs, through the shell it names, with the stub cswap writing a line.
run_agent() {
    script="$(grep -A 3 '<string>-c</string>' "$plist" | sed -n 2p | sed -e 's/^ *<string>//' -e 's/<\/string>$//' -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&amp;/\&/g')"
    /bin/sh -c "$script" "$stubs/cswap" "$log"
}
printf '#!/bin/sh\necho "ran $*"\n' > "$stubs/cswap"
run_agent
assert_eq "a run appends cswap's output to the log" "ran auto --once --json" "$(tail -n 1 "$log")"
head -c 1100000 /dev/zero | tr '\0' x > "$log"
run_agent
assert_eq "a run over 1 MB of log first moves it to cswap-auto.log.1" "y" "$(exists "$log.1")"
assert_eq "and starts the log afresh" "ran auto --once --json" "$(cat "$log")"

first="$(cat "$plist")"
rm "$work/launchctl.log"
printf 'bootstrap gui/%s %s\n' "$uid" "$plist" > "$work/launchctl.log"
out="$(agent)"; rc=$?
assert_eq "re-running with nothing changed succeeds" "0" "$rc"
assert_eq "and writes the same plist" "$first" "$(cat "$plist")"
assert_eq "and leaves the loaded agent alone" "bootstrap gui/$uid $plist" "$(calls)"
assert_eq "and says it is installed" "y" "$(says "is installed")"

out="$(agent --check)"; rc=$?
assert_eq "--check passes when the agent is installed and loaded" "0" "$rc"

# uv installs its tools in ~/.local/bin; that one wins over another cswap on PATH, such as a
# project's virtualenv.
mkdir -p "$home/.local/bin"
printf '#!/bin/sh\n' > "$home/.local/bin/cswap"
chmod +x "$home/.local/bin/cswap"
out="$(agent --check)"; rc=$?
assert_eq "--check fails when the plist differs from what install would write" "1" "$rc"
out="$(agent)"; rc=$?
assert_eq "with cswap in ~/.local/bin, install succeeds" "0" "$rc"
assert_eq "and runs that one rather than the one on PATH" "y" "$(has "<string>$home/.local/bin/cswap</string>")"
assert_eq "and reloads the agent, since the plist changed" "bootstrap gui/$uid $plist" "$(calls | tail -n 1)"

rm "$work/launchctl.log"
out="$(agent --uninstall)"; rc=$?
assert_eq "--uninstall succeeds" "0" "$rc"
assert_eq "--uninstall unloads the agent" "bootout gui/$uid/local.dotfiles.cswap-auto" "$(calls)"
assert_eq "--uninstall removes the plist" "n" "$(exists "$plist")"
out="$(agent --check)"; rc=$?
assert_eq "--check fails when the agent is not installed" "1" "$rc"

touch "$work/bootstrap-fails"
out="$(agent)"; rc=$?
assert_eq "when launchctl cannot load the agent, install fails" "1" "$rc"
assert_eq "and says so" "y" "$(says "could not load")"
rm "$work/bootstrap-fails"

out="$(agent --bogus)"; rc=$?
assert_eq "an unknown option fails" "1" "$rc"
assert_eq "and names it" "y" "$(says "Unknown option: --bogus")"

rm -f "$plist" "$work/launchctl.log"
rm "$home/.local/bin/cswap" "$stubs/cswap"
out="$(agent)"; rc=$?
assert_eq "with no cswap anywhere, install fails" "1" "$rc"
assert_eq "and says how to install claude-swap" "y" "$(says "uv tool install claude-swap")"
assert_eq "and writes no plist" "n" "$(exists "$plist")"
assert_eq "and loads nothing" "" "$(calls)"

assert_summary "macos/install-cswap-agent.sh"
