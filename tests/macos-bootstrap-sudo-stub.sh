#!/bin/sh

# The sudo that tests/macos-bootstrap.test.sh puts on PATH. $STUB_STATE is a folder; in it:
#   log        every prompt, as "sudo asked", and every askpass as "sudo askpass <path>"
#   nopasswd   present: sudo -v fails, as when another sudoers rule matching the user wants a password
#   pwreq      present: sudo wants the password "secret", which it then remembers in the file "cache"
#              until sudo -k forgets it, as a tty timestamp record does
# Without pwreq, sudo needs no password.

log="$STUB_STATE/log"
cache="$STUB_STATE/cache"

# authenticated <A|N|Q>: succeeds when sudo would run the command without asking a person. A is
# sudo -A (askpass allowed), Q a sudo -n probe, which never asks and logs nothing.
authenticated() {
    [ ! -e "$STUB_STATE/pwreq" ] && return 0
    [ -e "$cache" ] && return 0
    if [ "$1" = A ] && [ -n "${SUDO_ASKPASS:-}" ]; then
        echo "sudo askpass $SUDO_ASKPASS" >> "$log"
        # The helper's folder and the password file beside it, as `ls -l` shows their modes.
        ls -ld "$(dirname "$SUDO_ASKPASS")" "$(dirname "$SUDO_ASKPASS")/password" 2> /dev/null \
            | cut -c1-10 > "$STUB_STATE/modes"
        [ "$("$SUDO_ASKPASS")" = secret ] && : > "$cache" && return 0
    fi
    [ "$1" = Q ] || echo "sudo asked" >> "$log"
    return 1
}

case "$1" in
    -k) rm -f "$cache"; exit 0 ;;
    -n) authenticated Q; exit $? ;;
    -S)
        # sudo -S -p '' -v: the password on stdin
        read -r pw
        [ "$pw" = secret ] || exit 1
        : > "$cache"
        exit 0 ;;
    -v)
        [ ! -e "$STUB_STATE/nopasswd" ] || exit 1
        # Prompts on the terminal, which stands in for stdin here.
        if [ -e "$STUB_STATE/pwreq" ] && [ ! -e "$cache" ]; then
            read -r pw
            [ "$pw" = secret ] || exit 1
            : > "$cache"
        fi
        exit 0 ;;
    -A)
        shift
        [ "$1" = -v ] && { authenticated A; exit $?; }
        authenticated A || exit 1
        [ "$1" = -E ] && shift
        [ "$1" = -- ] && shift
        exec "$@" ;;
    -E)
        authenticated N || exit 1
        shift
        [ "$1" = -- ] && shift
        exec "$@" ;;
    *)
        authenticated N || exit 1
        exec "$@" ;;
esac
