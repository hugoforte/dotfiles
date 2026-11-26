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

# decision_on <platform> <tool> <command>: the answer verdict gives on a machine of that platform
# named box1, whose one address is 192.0.2.7, so the sudo and self-ssh rules are tested whatever
# machine runs the suite.
# The hook is imported from the repo root by a relative path: as an argument it would be argv[1],
# which makes the module run as the hook and wait for JSON on stdin.
decision_on() {
    (cd "$REPO_ROOT" && GUARD_PLATFORM="$1" GUARD_TOOL="$2" GUARD_COMMAND="$3" node -e "
        const { pathToFileURL } = require('node:url');
        import(pathToFileURL(require('node:path').resolve('bin/agent-guard.mjs')).href).then(({ verdict }) => {
            const machine = { platform: process.env.GUARD_PLATFORM, names: ['box1'], addresses: ['192.0.2.7'] };
            console.log(verdict(process.env.GUARD_TOOL, process.env.GUARD_COMMAND, machine)?.decision ?? 'allow');
        });
    ")
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
assert_eq "perl -i after the -e expression is refused" "deny" \
    "$(decision Bash "perl -e 's/a/b/' -i f")"
assert_eq "perl -i.bak is refused" "deny" \
    "$(decision Bash "perl -i.bak -pe 's/a/b/' f")"
assert_eq "perl running a command whose own flags hold an i is allowed" "allow" \
    "$(decision Bash "perl -e 'alarm 300; exec @ARGV' pwsh -NoProfile -File tests/Run-Pester.ps1")"
assert_eq "an -i given to perl's script is allowed" "allow" \
    "$(decision Bash "perl script.pl -i f")"
assert_eq "sed -i after another flag is refused" "deny" \
    "$(decision Bash "sed -E -i 's/a/b/' f")"
assert_eq "sed -i after the expression is refused" "deny" \
    "$(decision Bash "sed -e 's/a/b/' -i f")"
assert_eq "sed -i later in a pipeline is refused" "deny" \
    "$(decision Bash "cd src && sed -i 's/a/b/' f")"

assert_eq "a heredoc piped into tee is refused" "deny" \
    "$(decision Bash "cat <<'EOF' | tee notes.md${nl}x${nl}EOF")"
assert_eq "a heredoc piped into an interpreter is refused" "deny" \
    "$(decision Bash "cat <<'EOF' | python${nl}print(1)${nl}EOF")"
assert_eq "a refusal wins over a merge in the same command" "deny" \
    "$(decision Bash "gh pr merge 42; cat <<EOF > out.txt${nl}x${nl}EOF")"
assert_eq "sed -i with a quoted command word is refused" "deny" \
    "$(decision Bash "\"sed\" -i 's/a/b/' f")"
assert_eq "a heredoc piped into a filter is allowed" "allow" \
    "$(decision Bash "cat <<'EOF' | grep x${nl}x${nl}EOF")"

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
assert_eq "a quoted heredoc marker does not hide a merge" "ask" \
    "$(decision Bash "echo \"<<EOF\"${nl}gh pr merge 42")"
assert_eq "a quoted command word does not hide a merge" "ask" \
    "$(decision Bash "gh \"pr\" merge 42")"
assert_eq "gh pr merge from PowerShell asks first" "ask" \
    "$(decision PowerShell "gh pr merge 12 --squash")"
assert_eq "PowerShell commands are not checked for writes through the shell" "allow" \
    "$(decision PowerShell "sed -i x")"
assert_eq "gh pr view is allowed" "allow" \
    "$(decision Bash "gh pr view 12")"

# Elevated steps: denied everywhere but through the runner's client, elevate.

assert_eq "Start-Process -Verb RunAs is refused" "deny" \
    "$(decision PowerShell "Start-Process powershell -Verb RunAs")"
assert_eq "start-process -verb runas in lower case is refused" "deny" \
    "$(decision PowerShell "start-process pwsh -verb runas -ArgumentList '-File x.ps1'")"
assert_eq "saps with -Verb:RunAs is refused" "deny" \
    "$(decision PowerShell "saps notepad -Verb:RunAs")"
assert_eq "start with a quoted RunAs is refused" "deny" \
    "$(decision PowerShell "start 'C:\Program Files\x.exe' -Verb 'RunAs'")"
assert_eq "Start-Process -Verb RunAsUser is refused" "deny" \
    "$(decision PowerShell "Start-Process cmd -Verb RunAsUser")"
assert_eq "Start-Process after the call operator is refused" "deny" \
    "$(decision PowerShell "& Start-Process pwsh -Verb RunAs")"
assert_eq "Start-Process -Verb RunAs across a line continuation is refused" "deny" \
    "$(decision PowerShell "Start-Process pwsh \`${nl}    -Verb RunAs")"
assert_eq "Start-Process -Verb RunAs through powershell -Command from Bash is refused" "deny" \
    "$(decision Bash "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"Start-Process pwsh -Verb RunAs\"")"
assert_eq "Start-Process -Verb RunAs as powershell's bare command is refused" "deny" \
    "$(decision Bash "powershell -NoProfile Start-Process pwsh -Verb RunAs")"
encoded="$(node -e "process.stdout.write(Buffer.from('Start-Process pwsh -Verb RunAs', 'utf16le').toString('base64'))")"
assert_eq "Start-Process -Verb RunAs in an encoded command is refused" "deny" \
    "$(decision Bash "pwsh -NoProfile -EncodedCommand $encoded")"
assert_eq "Start-Process -Verb RunAs through cmd /c is refused" "deny" \
    "$(decision Bash "cmd //c powershell -c Start-Process pwsh -Verb RunAs")"
assert_eq "Start-Process -Verb RunAs through bash -c is refused" "deny" \
    "$(decision Bash "bash -lc \"powershell -c 'Start-Process pwsh -Verb RunAs'\"")"
assert_eq "Start-Process -Verb RunAs through Invoke-Expression is refused" "deny" \
    "$(decision PowerShell "Invoke-Expression 'Start-Process pwsh -Verb RunAs'")"
assert_eq "Start-Process without -Verb is allowed" "allow" \
    "$(decision PowerShell "Start-Process notepad -Wait")"
assert_eq "Start-Process -Verbose is allowed" "allow" \
    "$(decision PowerShell "Start-Process notepad -Verbose")"
assert_eq "Start-Process -Verb Open is allowed" "allow" \
    "$(decision PowerShell "Start-Process report.html -Verb Open")"
assert_eq "a commit message naming Start-Process -Verb RunAs is allowed" "allow" \
    "$(decision Bash "git commit -m \"Refuse Start-Process -Verb RunAs\"")"
assert_eq "Write-Output of Start-Process -Verb RunAs is allowed" "allow" \
    "$(decision PowerShell "Write-Output 'Start-Process pwsh -Verb RunAs'")"
assert_eq "bash -c echoing a quoted Start-Process -Verb RunAs is allowed" "allow" \
    "$(decision Bash "bash -c \"echo 'Start-Process pwsh -Verb RunAs'\"")"

assert_eq "runas is refused" "deny" \
    "$(decision PowerShell "runas /user:Administrator cmd")"
assert_eq "runas.exe by its path is refused" "deny" \
    "$(decision PowerShell "& C:\Windows\System32\runas.exe /savecred /user:admin cmd")"
assert_eq "runas from Bash is refused" "deny" \
    "$(decision Bash "runas //user:admin \"cmd /c x\"")"
assert_eq "looking runas up is allowed" "allow" \
    "$(decision PowerShell "where.exe runas")"
assert_eq "a commit message naming runas is allowed" "allow" \
    "$(decision Bash "git commit -m \"runas is refused\"")"

assert_eq "sudo on Windows is refused" "deny" \
    "$(decision_on win32 PowerShell "sudo powershell -File x.ps1")"
assert_eq "sudo from Git Bash on Windows is refused" "deny" \
    "$(decision_on win32 Bash "sudo ls")"
assert_eq "sudo.exe by its path is refused on any platform" "deny" \
    "$(decision_on darwin Bash "C:/Windows/System32/sudo.exe ls")"
assert_eq "gsudo is refused" "deny" \
    "$(decision_on win32 PowerShell "gsudo Set-Content x y")"
assert_eq "sudo on macOS is allowed" "allow" \
    "$(decision_on darwin Bash "sudo softwareupdate -l")"
assert_eq "sudo on Linux is allowed" "allow" \
    "$(decision_on linux Bash "sudo apt update")"
assert_eq "looking sudo up on Windows is allowed" "allow" \
    "$(decision_on win32 Bash "command -v sudo")"
assert_eq "a commit message naming sudo on Windows is allowed" "allow" \
    "$(decision_on win32 Bash "git commit -m \"sudo is refused on Windows\"")"

assert_eq "schtasks /run on Elevated runs is refused" "deny" \
    "$(decision PowerShell "schtasks /run /tn \"Elevated runs\"")"
assert_eq "schtasks //run on Elevated runs from Git Bash is refused" "deny" \
    "$(decision Bash "schtasks //run //tn \"Elevated runs\"")"
assert_eq "schtasks /Run on \\Elevated runs is refused" "deny" \
    "$(decision PowerShell "schtasks /Run /TN '\\Elevated runs'")"
assert_eq "schtasks /change on Elevated runs is refused" "deny" \
    "$(decision PowerShell "schtasks /change /tn \"Elevated runs\" /tr x.exe")"
assert_eq "schtasks /delete on Elevated runs is refused" "deny" \
    "$(decision PowerShell "schtasks /delete /tn \"Elevated runs\" /f")"
assert_eq "Start-ScheduledTask on Elevated runs is refused" "deny" \
    "$(decision PowerShell "Start-ScheduledTask -TaskName 'Elevated runs'")"
assert_eq "Start-ScheduledTask with the name in place is refused" "deny" \
    "$(decision PowerShell "Start-ScheduledTask 'elevated runs'")"
assert_eq "Elevated runs piped into Start-ScheduledTask is refused" "deny" \
    "$(decision PowerShell "Get-ScheduledTask 'Elevated runs' | Start-ScheduledTask")"
assert_eq "Elevated runs through a variable into Start-ScheduledTask is refused" "deny" \
    "$(decision PowerShell "\$t = Get-ScheduledTask -TaskName 'Elevated*'; Start-ScheduledTask -InputObject \$t")"
assert_eq "Set-ScheduledTask on Elevated runs is refused" "deny" \
    "$(decision PowerShell "Set-ScheduledTask -TaskName:'Elevated runs' -Action \$a")"
assert_eq "Register-ScheduledTask -Force over Elevated runs is refused" "deny" \
    "$(decision PowerShell "Register-ScheduledTask -TaskName 'Elevated runs' -Action \$a -Force")"
assert_eq "Unregister-ScheduledTask on Elevated runs is refused" "deny" \
    "$(decision PowerShell "Unregister-ScheduledTask -TaskName 'Elevated runs' -Confirm:\$false")"
assert_eq "Enable-ScheduledTask on Elevated runs is refused" "deny" \
    "$(decision PowerShell "Enable-ScheduledTask -TaskName 'Elevated runs'")"
assert_eq "schtasks /query on Elevated runs is allowed" "allow" \
    "$(decision PowerShell "schtasks /query /tn \"Elevated runs\" /v")"
assert_eq "Get-ScheduledTask on Elevated runs is allowed" "allow" \
    "$(decision PowerShell "Get-ScheduledTask -TaskName 'Elevated runs' | Get-ScheduledTaskInfo")"
assert_eq "Start-ScheduledTask on another task is allowed" "allow" \
    "$(decision PowerShell "Start-ScheduledTask -TaskName 'dotfiles sync'")"
assert_eq "schtasks /run on a task whose name only starts the same is allowed" "allow" \
    "$(decision PowerShell "schtasks /run /tn \"Elevated runs backup\"")"
assert_eq "a commit message naming schtasks /run on Elevated runs is allowed" "allow" \
    "$(decision Bash "git commit -m \"schtasks /run /tn 'Elevated runs' is refused\"")"

assert_eq "ssh to localhost on Windows is refused" "deny" \
    "$(decision_on win32 Bash "ssh localhost")"
assert_eq "ssh to 127.0.0.1 is refused" "deny" \
    "$(decision_on win32 PowerShell "ssh admin@127.0.0.1 whoami")"
assert_eq "ssh to ::1 is refused" "deny" \
    "$(decision_on win32 PowerShell "ssh.exe ::1")"
assert_eq "ssh to the machine's own name, in any case, is refused" "deny" \
    "$(decision_on win32 PowerShell "ssh BOX1")"
assert_eq "ssh to a name under the machine's own is refused" "deny" \
    "$(decision_on win32 Bash "ssh admin@box1.tailnet.example")"
assert_eq "ssh to the machine's own address is refused" "deny" \
    "$(decision_on win32 Bash "ssh 192.0.2.7")"
assert_eq "ssh to an ssh:// URI of the machine is refused" "deny" \
    "$(decision_on win32 Bash "ssh ssh://admin@box1:22")"
assert_eq "ssh to the machine after options with values is refused" "deny" \
    "$(decision_on win32 Bash "ssh -i ~/.ssh/id -o BatchMode=yes -l admin box1 whoami")"
assert_eq "ssh jumping through the machine is refused" "deny" \
    "$(decision_on win32 Bash "ssh -J admin@localhost other")"
assert_eq "ssh to another machine is allowed" "allow" \
    "$(decision_on win32 Bash "ssh box2")"
assert_eq "ssh to a machine whose name only starts the same is allowed" "allow" \
    "$(decision_on win32 Bash "ssh box10")"
assert_eq "ssh to GitHub is allowed" "allow" \
    "$(decision_on win32 Bash "ssh -T -p 22 git@github.com")"
assert_eq "ssh-keygen naming localhost is allowed" "allow" \
    "$(decision_on win32 Bash "ssh-keygen -F localhost")"
assert_eq "ssh to localhost on macOS is allowed" "allow" \
    "$(decision_on darwin Bash "ssh localhost")"
assert_eq "a commit message naming ssh localhost is allowed" "allow" \
    "$(decision_on win32 Bash "git commit -m \"ssh localhost is refused\"")"
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) self_ssh=deny ;;
    *) self_ssh=allow ;;
esac
assert_eq "the hook reads this machine's own name" "$self_ssh" \
    "$(decision Bash "ssh $(hostname)")"

assert_eq "Set-Content into the runner's root is refused" "deny" \
    "$(decision PowerShell "Set-Content C:\ProgramData\ElevatedRuns\inbox\r.json '{}'")"
assert_eq "New-Item under \$env:ProgramData's runner root is refused" "deny" \
    "$(decision PowerShell "New-Item -ItemType File -Path \"\$env:ProgramData\ElevatedRuns\inbox\r.json\"")"
assert_eq "Copy-Item into a lower-case, forward-slash runner root is refused" "deny" \
    "$(decision PowerShell "Copy-Item r.json -Destination 'c:/programdata/elevatedruns/inbox/'")"
assert_eq "Remove-Item under \${env:PROGRAMDATA} is refused" "deny" \
    "$(decision PowerShell "Remove-Item -Recurse \"\${env:PROGRAMDATA}\ElevatedRuns\audit\"")"
assert_eq "a .NET write into the runner's root is refused" "deny" \
    "$(decision PowerShell "[IO.File]::WriteAllText(\"\$env:ProgramData\ElevatedRuns\inbox\r.json\", \$j)")"
assert_eq "cp into the runner's root from Git Bash is refused" "deny" \
    "$(decision Bash "cp r.json /c/ProgramData/ElevatedRuns/inbox/")"
assert_eq "a redirect into the runner's root is refused" "deny" \
    "$(decision Bash "echo x > \"C:\\ProgramData\\ElevatedRuns\\inbox\\r.json\"")"
assert_eq "cmd's copy into %ProgramData%'s runner root is refused" "deny" \
    "$(decision Bash "cmd //c copy r.json %ProgramData%\\\\ElevatedRuns\\\\inbox")"
assert_eq "moving into the runner's root is refused" "deny" \
    "$(decision PowerShell "cd C:\ProgramData\ElevatedRuns\inbox; Set-Content r.json x")"
assert_eq "reading the runner's results is allowed" "allow" \
    "$(decision PowerShell "Get-Content C:\ProgramData\ElevatedRuns\results\r.json")"
assert_eq "listing the runner's root from Git Bash is allowed" "allow" \
    "$(decision Bash "ls /c/ProgramData/ElevatedRuns/results")"
assert_eq "testing for the runner's root is allowed" "allow" \
    "$(decision PowerShell "Test-Path \"\$env:ProgramData\ElevatedRuns\"")"
assert_eq "elevate, naming the runner's root, is allowed" "allow" \
    "$(decision PowerShell "& \"\$HOME\bin\elevate.ps1\" log C:\ProgramData\ElevatedRuns\audit")"
assert_eq "elevate request is allowed" "allow" \
    "$(decision PowerShell "elevate request dotfiles-tools-check --thread t1")"
assert_eq "a write to a folder whose name only starts the same is allowed" "allow" \
    "$(decision PowerShell "Set-Content C:\ProgramData\ElevatedRunsOld\x.txt y")"
assert_eq "a write elsewhere in ProgramData is allowed" "allow" \
    "$(decision PowerShell "Set-Content C:\ProgramData\Other\x.txt y")"
assert_eq "a commit message naming the runner's root is allowed" "allow" \
    "$(decision Bash "git commit -m \"Writes into C:\\ProgramData\\ElevatedRuns go through elevate\"")"

assert_eq "elevate enable asks first" "ask" \
    "$(decision PowerShell "elevate enable")"
assert_eq "elevate.ps1 enable by its path asks first" "ask" \
    "$(decision PowerShell "& \"\$HOME\bin\elevate.ps1\" enable")"
assert_eq "elevate enable through powershell -File asks first" "ask" \
    "$(decision Bash "powershell -NoProfile -File ~/bin/elevate.ps1 enable")"
assert_eq "elevate disable is allowed" "allow" \
    "$(decision PowerShell "elevate disable")"
assert_eq "a commit message naming elevate enable is allowed" "allow" \
    "$(decision Bash "git commit -m \"elevate enable asks first\"")"
assert_eq "a refused elevation wins over elevate enable" "deny" \
    "$(decision PowerShell "elevate enable; runas /user:admin cmd")"
assert_eq "elevate enable after an option asks first" "ask" \
    "$(decision PowerShell "elevate --thread t1 enable")"

# PowerShell's own syntax: here-strings, script blocks, groups, escapes and continuations.
assert_eq "a here-string commit message with an apostrophe, naming runas, is allowed" "allow" \
    "$(decision PowerShell "git commit -m @'${nl}agent-guard: don't miss it${nl}runas /user:x is refused${nl}'@")"
assert_eq "a double-quoted here-string body naming the runner's root is allowed" "allow" \
    "$(decision PowerShell "gh pr create --body @\"${nl}It's here:${nl}Writes into C:\ProgramData\ElevatedRuns go through elevate${nl}\"@")"
assert_eq "a here-string kept in a variable, naming ssh localhost, is allowed" "allow" \
    "$(decision_on win32 PowerShell "\$m = @'${nl}Don't:${nl}ssh localhost${nl}'@${nl}git commit -m \$m")"
assert_eq "Start-Process -Verb RunAs in a script block is refused" "deny" \
    "$(decision PowerShell "if (-not \$isAdmin) { Start-Process pwsh -Verb RunAs -ArgumentList \"-File x.ps1\"; exit }")"
assert_eq "Start-Process -Verb RunAs after the call operator on a block is refused" "deny" \
    "$(decision PowerShell "powershell -Command \"& {Start-Process pwsh -Verb RunAs}\"")"
assert_eq "Start-Process -Verb RunAs in a group is refused" "deny" \
    "$(decision PowerShell "\$p = (Start-Process pwsh -Verb RunAs)")"
assert_eq "Start-Process -Verb RunAs assigned with no spaces is refused" "deny" \
    "$(decision PowerShell "\$p=Start-Process pwsh -Verb RunAs -PassThru")"
assert_eq "Start-Process with typographic dash and quotes is refused" "deny" \
    "$(decision PowerShell "Start-Process pwsh –Verb ‘RunAs’")"
assert_eq "Start-Process -Verb RunAs in a double-quoted subexpression is refused" "deny" \
    "$(decision PowerShell "Write-Output \"\$(Start-Process pwsh -Verb RunAs)\"")"
assert_eq "a PowerShell line ending in a backslash does not join the next" "deny" \
    "$(decision PowerShell "Set-Location D:\\${nl}Start-Process pwsh -Verb RunAs")"
assert_eq "a backslash before a PowerShell closing quote does not escape it" "deny" \
    "$(decision PowerShell "Get-ChildItem \"C:\Temp\\\"; Remove-Item \"C:\ProgramData\ElevatedRuns\inbox\r.json\"")"
assert_eq "an unquoted \${env:ProgramData} path into the runner's root is refused" "deny" \
    "$(decision PowerShell "Remove-Item \${env:ProgramData}\ElevatedRuns\inbox\r.json")"
assert_eq "a doubled quote inside a PowerShell string keeps it one word" "allow" \
    "$(decision PowerShell "git commit -m 'it''s: runas /user:x is refused'")"

# The more ways in: interpreters, pipes, wrappers' redirects, assignments, ssh's other forms.
assert_eq "node writing into the runner's root is refused" "deny" \
    "$(decision Bash "node -e \"require('fs').writeFileSync('C:/ProgramData/ElevatedRuns/inbox/r.json', '{}')\"")"
assert_eq "python writing into the runner's root is refused" "deny" \
    "$(decision Bash "python -c \"open(r'C:\\ProgramData\\ElevatedRuns\\inbox\\r.json','w').write('x')\"")"
assert_eq "a listing piped into Remove-Item is refused" "deny" \
    "$(decision PowerShell "Get-ChildItem C:\ProgramData\ElevatedRuns\inbox | Remove-Item -Force")"
assert_eq "a listing piped into a ForEach-Object block that removes is refused" "deny" \
    "$(decision PowerShell "gci C:\ProgramData\ElevatedRuns\inbox | ForEach-Object { Remove-Item \$_ }")"
assert_eq "a listing piped into xargs is refused" "deny" \
    "$(decision Bash "ls /c/ProgramData/ElevatedRuns/inbox/* | xargs rm")"
assert_eq "a listing piped into a reader is allowed" "allow" \
    "$(decision PowerShell "Get-ChildItem C:\ProgramData\ElevatedRuns -Recurse | Sort-Object LastWriteTime | Select-Object -Last 5")"
assert_eq "a wrapper's own redirect into the runner's root is refused" "deny" \
    "$(decision Bash "bash -c \"echo hi\" > C:/ProgramData/ElevatedRuns/inbox/r.json")"
assert_eq "the task named in a variable, then started, is refused" "deny" \
    "$(decision PowerShell "\$n = 'Elevated runs'; Start-ScheduledTask -TaskName \$n")"
assert_eq "Disable-ScheduledTask on Elevated runs is refused" "deny" \
    "$(decision PowerShell "Disable-ScheduledTask -TaskName 'Elevated runs'")"
assert_eq "schtasks /create over Elevated runs is refused" "deny" \
    "$(decision PowerShell "schtasks /create /tn \"Elevated runs\" /tr x.exe /sc once /st 00:00 /f")"
assert_eq "ssh through -o ProxyJump to the machine is refused" "deny" \
    "$(decision_on win32 Bash "ssh -o ProxyJump=localhost other")"
assert_eq "ssh to the machine under timeout is refused" "deny" \
    "$(decision_on win32 Bash "timeout 10 ssh localhost whoami")"
assert_eq "ssh to the machine in a quoted command substitution is refused" "deny" \
    "$(decision_on win32 Bash "echo \"\$(ssh localhost whoami)\"")"
assert_eq "sudo on Windows in an assignment's command substitution is refused" "deny" \
    "$(decision_on win32 Bash "x=\"\$(sudo whoami)\"")"
assert_eq "ssh to a bracketed IPv6 loopback is refused" "deny" \
    "$(decision_on win32 Bash "ssh -p 22 admin@[::1]")"
assert_eq "ssh to the machine's name with a trailing dot is refused" "deny" \
    "$(decision_on win32 Bash "ssh box1.")"
assert_eq "scp to the machine is refused" "deny" \
    "$(decision_on win32 Bash "scp x.ps1 admin@localhost:C:/Temp/")"
assert_eq "sftp to the machine is refused" "deny" \
    "$(decision_on win32 Bash "sftp admin@box1:/c/Temp")"
assert_eq "scp from a Windows drive path to another machine is allowed" "allow" \
    "$(decision_on win32 Bash "scp C:/Temp/x.ps1 admin@box2:C:/Temp/")"
assert_eq "runas under env is refused" "deny" \
    "$(decision Bash "env FOO=1 runas //user:admin cmd")"
assert_eq "runas after an assignment is refused" "deny" \
    "$(decision Bash "FOO=1 runas //user:admin cmd")"
assert_eq "a dot-sourced elevate enable asks first" "ask" \
    "$(decision PowerShell ". ./elevate.ps1 enable")"
assert_eq "Start-Process -Verb RunAs through iex is refused" "deny" \
    "$(decision PowerShell "iex 'Start-Process pwsh -Verb RunAs'")"
encoded_short="$(node -e "process.stdout.write(Buffer.from('runas /user:admin cmd', 'utf16le').toString('base64'))")"
assert_eq "runas in an -ec encoded command is refused" "deny" \
    "$(decision PowerShell "powershell -ec $encoded_short")"
assert_eq "Start-Process -Verb RunAs through cmd /k is refused" "deny" \
    "$(decision Bash "cmd //k powershell -c Start-Process pwsh -Verb RunAs")"

# The Elevated runs task started or changed through Task Scheduler's COM object, its CIM classes,
# or a wrapper around schtasks, and the reads and other tasks around those.
assert_eq "COM Schedule.Service Run on Elevated runs is refused" "deny" \
    "$(decision PowerShell "\$s = New-Object -ComObject Schedule.Service; \$s.Connect(); \$s.GetFolder('\').GetTask('Elevated runs').Run(\$null)")"
assert_eq "COM Schedule.Service RunEx on Elevated runs is refused" "deny" \
    "$(decision PowerShell "\$s = New-Object -ComObject Schedule.Service; \$s.Connect(); \$s.GetFolder('\').GetTask('Elevated runs').RunEx(\$null, 0, 0, '')")"
assert_eq "COM Run on Elevated runs kept in a variable is refused" "deny" \
    "$(decision PowerShell "\$svc = New-Object -com 'Schedule.Service'; \$svc.Connect(); \$t = \$svc.GetFolder('\').GetTask('\Elevated runs'); [void]\$t.Run(\$null)")"
assert_eq "COM Run on Elevated runs in upper case is refused" "deny" \
    "$(decision PowerShell "(NEW-OBJECT -COMOBJECT SCHEDULE.SERVICE).GETFOLDER('\').GETTASK('ELEVATED RUNS').RUN(\$NULL)")"
assert_eq "COM Run on Elevated runs through a ProgID activator is refused" "deny" \
    "$(decision PowerShell "\$s = [Activator]::CreateInstance([Type]::GetTypeFromProgID('Schedule.Service')); \$s.Connect(); \$s.GetFolder('\').GetTask('Elevated runs').Run(\$null)")"
assert_eq "COM RunEx on Elevated runs through ForEach-Object is refused" "deny" \
    "$(decision PowerShell "\$s = New-Object -ComObject:Schedule.Service; \$s.Connect(); \$s.GetFolder('\').GetTask('Elevated runs') | % RunEx \$null 0 0 ''")"
assert_eq "COM DeleteTask on Elevated runs is refused" "deny" \
    "$(decision PowerShell "\$s = New-Object -ComObject Schedule.Service; \$s.Connect(); \$s.GetFolder('\').DeleteTask('Elevated runs', 0)")"
assert_eq "COM enabling Elevated runs is refused" "deny" \
    "$(decision PowerShell "\$t = (New-Object -ComObject Schedule.Service).GetFolder('\').GetTask('Elevated runs'); \$t.Enabled = \$true")"
assert_eq "COM Run on Elevated runs through powershell -Command from Git Bash is refused" "deny" \
    "$(decision Bash "powershell -NoProfile -Command \"\\\$s = New-Object -ComObject Schedule.Service; \\\$s.Connect(); \\\$s.GetFolder('\\').GetTask('Elevated runs').Run(\\\$null)\"")"
assert_eq "COM reading Elevated runs is allowed" "allow" \
    "$(decision PowerShell "\$s = New-Object -ComObject Schedule.Service; \$s.Connect(); \$s.GetFolder('\').GetTask('Elevated runs').LastRunTime")"
assert_eq "COM stopping Elevated runs is allowed" "allow" \
    "$(decision PowerShell "\$s = New-Object -ComObject Schedule.Service; \$s.Connect(); \$s.GetFolder('\').GetTask('Elevated runs').Stop(0)")"
assert_eq "COM Run on another task is allowed" "allow" \
    "$(decision PowerShell "\$s = New-Object -ComObject Schedule.Service; \$s.Connect(); \$s.GetFolder('\').GetTask('dotfiles sync').Run(\$null)")"
assert_eq "a commit message naming COM Run on Elevated runs is allowed" "allow" \
    "$(decision Bash "git commit -m \"Schedule.Service .Run on 'Elevated runs' is refused\"")"
assert_eq "Invoke-CimMethod Start on MSFT_ScheduledTask Elevated runs is refused" "deny" \
    "$(decision PowerShell "Get-CimInstance -Namespace Root/Microsoft/Windows/TaskScheduler -ClassName MSFT_ScheduledTask -Filter \"TaskName='Elevated runs'\" | Invoke-CimMethod -MethodName Start")"
assert_eq "icim Start on msft_scheduledtask Elevated runs is refused" "deny" \
    "$(decision PowerShell "gcim -Namespace root/microsoft/windows/taskscheduler -ClassName msft_scheduledtask -Filter \"TaskName = 'Elevated runs'\" | icim -MethodName start")"
assert_eq "Invoke-CimMethod Start on a WQL query for Elevated* is refused" "deny" \
    "$(decision PowerShell "Get-CimInstance -Namespace Root/Microsoft/Windows/TaskScheduler -Query \"SELECT * FROM MSFT_ScheduledTask WHERE TaskName LIKE 'Elevated%'\" | Invoke-CimMethod -MethodName:Start")"
assert_eq "Get-ScheduledTask Elevated runs piped into Invoke-CimMethod Start is refused" "deny" \
    "$(decision PowerShell "Get-ScheduledTask -TaskName 'Elevated runs' | Invoke-CimMethod -MethodName Start")"
assert_eq "Invoke-CimMethod StartByPath on PS_ScheduledTask Elevated runs is refused" "deny" \
    "$(decision PowerShell "Invoke-CimMethod -Namespace Root/Microsoft/Windows/TaskScheduler -ClassName PS_ScheduledTask -MethodName StartByPath -Arguments @{TaskName='Elevated runs'; TaskPath='\'}")"
assert_eq "Remove-CimInstance on MSFT_ScheduledTask Elevated runs is refused" "deny" \
    "$(decision PowerShell "Get-CimInstance -Namespace Root/Microsoft/Windows/TaskScheduler -ClassName MSFT_ScheduledTask -Filter \"TaskName='Elevated runs'\" | Remove-CimInstance")"
assert_eq "Invoke-WmiMethod Start on MSFT_ScheduledTask Elevated runs is refused" "deny" \
    "$(decision PowerShell "Get-WmiObject -Namespace root\Microsoft\Windows\TaskScheduler -Class MSFT_ScheduledTask -Filter \"TaskName='Elevated runs'\" | Invoke-WmiMethod -Name Start")"
assert_eq "wmic call Start on MSFT_ScheduledTask Elevated runs is refused" "deny" \
    "$(decision PowerShell "wmic /namespace:\\\\root\Microsoft\Windows\TaskScheduler path MSFT_ScheduledTask where \"TaskName='Elevated runs'\" call Start")"
assert_eq "Get-CimInstance reading MSFT_ScheduledTask Elevated runs is allowed" "allow" \
    "$(decision PowerShell "Get-CimInstance -Namespace Root/Microsoft/Windows/TaskScheduler -ClassName MSFT_ScheduledTask -Filter \"TaskName='Elevated runs'\"")"
assert_eq "Invoke-CimMethod Stop on MSFT_ScheduledTask Elevated runs is allowed" "allow" \
    "$(decision PowerShell "Get-CimInstance -Namespace Root/Microsoft/Windows/TaskScheduler -ClassName MSFT_ScheduledTask -Filter \"TaskName='Elevated runs'\" | Invoke-CimMethod -MethodName Stop")"
assert_eq "Invoke-CimMethod Start on another task is allowed" "allow" \
    "$(decision PowerShell "Get-CimInstance -Namespace Root/Microsoft/Windows/TaskScheduler -ClassName MSFT_ScheduledTask -Filter \"TaskName='dotfiles sync'\" | Invoke-CimMethod -MethodName Start")"
assert_eq "cmd /c schtasks /run on Elevated runs is refused" "deny" \
    "$(decision PowerShell "cmd /c schtasks /run /tn \"Elevated runs\"")"
assert_eq "cmd.exe /C schtasks /Run on Elevated runs is refused" "deny" \
    "$(decision PowerShell "cmd.exe /C schtasks /Run /TN 'Elevated runs'")"
assert_eq "cmd /k schtasks /run on Elevated runs is refused" "deny" \
    "$(decision PowerShell "cmd /k schtasks /run /tn 'Elevated runs'")"
assert_eq "cmd /c with /c glued to schtasks on Elevated runs is refused" "deny" \
    "$(decision PowerShell "cmd /cschtasks /run /tn \"Elevated runs\"")"
assert_eq "cmd //c schtasks //run on Elevated runs from Git Bash is refused" "deny" \
    "$(decision Bash "cmd //c schtasks //run //tn \"Elevated runs\"")"
assert_eq "cmd //c with the whole command quoted from Git Bash is refused" "deny" \
    "$(decision Bash "cmd //s //c \"schtasks //run //tn \\\"Elevated runs\\\"\"")"
assert_eq "cmd /c chaining schtasks /run on Elevated runs after & is refused" "deny" \
    "$(decision PowerShell "cmd /c 'echo hi & schtasks /run /tn \"Elevated runs\"'")"
assert_eq "cmd /c chaining schtasks /run with backtick-escaped quotes is refused" "deny" \
    "$(decision PowerShell "cmd /c \"echo hi && schtasks /run /tn \`\"Elevated runs\`\"\"")"
assert_eq "cmd /c call schtasks /run on Elevated runs is refused" "deny" \
    "$(decision PowerShell "cmd /c call schtasks /run /tn \"Elevated runs\"")"
assert_eq "cmd /c start schtasks /run on Elevated runs is refused" "deny" \
    "$(decision PowerShell "cmd /c start \"\" /b schtasks /run /tn \"Elevated runs\"")"
assert_eq "Start-Process schtasks /run on Elevated runs is refused" "deny" \
    "$(decision PowerShell "Start-Process schtasks -ArgumentList '/run /tn \"Elevated runs\"' -NoNewWindow")"
assert_eq "saps schtasks.exe with an argument array on Elevated runs is refused" "deny" \
    "$(decision PowerShell "saps -FilePath schtasks.exe '/run','/tn','Elevated runs'")"
assert_eq "powershell -Command Start-ScheduledTask with the name quoted outside is refused" "deny" \
    "$(decision PowerShell "powershell -NoProfile -Command Start-ScheduledTask -TaskName 'Elevated runs'")"
assert_eq "cmd /c schtasks /query on Elevated runs is allowed" "allow" \
    "$(decision PowerShell "cmd /c schtasks /query /tn \"Elevated runs\" /v")"
assert_eq "cmd /c schtasks /run on another task is allowed" "allow" \
    "$(decision PowerShell "cmd /c schtasks /run /tn \"dotfiles sync\"")"
assert_eq "cmd /c echo naming schtasks /run on Elevated runs is allowed" "allow" \
    "$(decision PowerShell "cmd /c echo schtasks /run /tn \"Elevated runs\"")"
assert_eq "Start-Process schtasks /query on Elevated runs is allowed" "allow" \
    "$(decision PowerShell "Start-Process schtasks -ArgumentList '/query /tn \"Elevated runs\"' -Wait")"

# cmd's own syntax: only double quotes quote, ^ escapes, and @ , ; = if and for may stand before a command.
assert_eq "cmd /c with apostrophes around schtasks /run on Elevated runs is refused" "deny" \
    "$(decision PowerShell "cmd /c 'echo don''t & schtasks /run /tn \"Elevated runs\" & echo won''t'")"
assert_eq "cmd //c with apostrophes from Git Bash is refused" "deny" \
    "$(decision Bash "cmd //c \"echo ' & schtasks //run //tn \\\"Elevated runs\\\" & echo '\"")"
assert_eq "cmd /c with doubled quotes and an apostrophe is refused" "deny" \
    "$(decision PowerShell "cmd /c \"echo it's & schtasks /run /tn \"\"Elevated runs\"\" & echo it's\"")"
assert_eq "cmd /c with a caret inside schtasks is refused" "deny" \
    "$(decision PowerShell "cmd /c sch^tasks /run /tn \"Elevated runs\"")"
assert_eq "cmd /c with @ before schtasks is refused" "deny" \
    "$(decision PowerShell "cmd /c @schtasks /run /tn \"Elevated runs\"")"
assert_eq "cmd /c with a comma before schtasks is refused" "deny" \
    "$(decision PowerShell "cmd /c ,schtasks /run /tn \"Elevated runs\"")"
assert_eq "cmd /c if before schtasks is refused" "deny" \
    "$(decision PowerShell "cmd /c if 1==1 schtasks /run /tn \"Elevated runs\"")"
assert_eq "cmd /c if not exist before schtasks is refused" "deny" \
    "$(decision PowerShell "cmd /c if not exist x schtasks /run /tn \"Elevated runs\"")"
assert_eq "cmd /c for ... do schtasks is refused" "deny" \
    "$(decision PowerShell "cmd /c for /l %i in (1,1,1) do schtasks /run /tn \"Elevated runs\"")"
assert_eq "cmd /r schtasks /run on Elevated runs is refused" "deny" \
    "$(decision PowerShell "cmd /r schtasks /run /tn \"Elevated runs\"")"
assert_eq "cmd /q/c schtasks /run on Elevated runs is refused" "deny" \
    "$(decision PowerShell "cmd /q/c schtasks /run /tn \"Elevated runs\"")"
assert_eq "cmd /c start with a title before schtasks is refused" "deny" \
    "$(decision PowerShell "cmd /c start \"x\" schtasks /run /tn \"Elevated runs\"")"
assert_eq "cmd /c start /d before schtasks is refused" "deny" \
    "$(decision PowerShell "cmd /c start /d C:\ schtasks /run /tn \"Elevated runs\"")"
assert_eq "cmd /c with an apostrophe in an ordinary command is allowed" "allow" \
    "$(decision PowerShell "cmd /c 'echo it''s fine & dir'")"

# A task name escaped rather than quoted, and named only in a filter.
assert_eq "schtasks //run on Elevated\\ runs from Git Bash is refused" "deny" \
    "$(decision Bash "schtasks //run //tn Elevated\\ runs")"
assert_eq "Start-ScheduledTask on Elevated\` runs is refused" "deny" \
    "$(decision PowerShell "Start-ScheduledTask -TaskName Elevated\` runs")"
assert_eq "Get-ScheduledTask filtered by Where-Object into Start-ScheduledTask is refused" "deny" \
    "$(decision PowerShell "Get-ScheduledTask | ? TaskName -eq 'Elevated runs' | Start-ScheduledTask")"
assert_eq "Get-ScheduledTask filtered by a -like script block into Start-ScheduledTask is refused" "deny" \
    "$(decision PowerShell "Get-ScheduledTask | Where-Object { \$_.TaskName -like 'Elev*' } | Start-ScheduledTask")"
assert_eq "schtasks //run after if ... then from Git Bash is refused" "deny" \
    "$(decision Bash "if true; then schtasks //run //tn \"Elevated runs\"; fi")"
assert_eq "schtasks //run in a for loop from Git Bash is refused" "deny" \
    "$(decision Bash "for i in 1; do schtasks //run //tn \"Elevated runs\"; done")"
assert_eq "schtasks //run after ! from Git Bash is refused" "deny" \
    "$(decision Bash "! schtasks //run //tn \"Elevated runs\"")"

# More of Task Scheduler's object routes.
assert_eq "COM Run with Schedule.Service from GetTypeFromProgID with a server is refused" "deny" \
    "$(decision PowerShell "\$s = [Activator]::CreateInstance([Type]::GetTypeFromProgID(\"Schedule.Service\", \$null)); \$s.Connect(); \$s.GetFolder('\').GetTask('Elevated runs').Run(\$null)")"
assert_eq "COM Run with Schedule.Service by a [guid] CLSID is refused" "deny" \
    "$(decision PowerShell "\$s = [Activator]::CreateInstance([Type]::GetTypeFromCLSID([guid]'0f87369f-a4e5-4cfc-bd3e-73e6154572dd')); \$s.Connect(); \$s.GetFolder('\').GetTask('Elevated runs').Run(\$null)")"
assert_eq "COM Run with Schedule.Service.1 is refused" "deny" \
    "$(decision PowerShell "\$s = New-Object -ComObject Schedule.Service.1; \$s.Connect(); \$s.GetFolder('\').GetTask('Elevated runs').Run(\$null)")"
assert_eq "COM RegisterTaskDefinition over Elevated runs is refused" "deny" \
    "$(decision PowerShell "\$s = New-Object -ComObject Schedule.Service; \$s.Connect(); \$d = \$s.NewTask(0); \$s.GetFolder('\').RegisterTaskDefinition('Elevated runs', \$d, 6, \$null, \$null, 3)")"
assert_eq "COM SetSecurityDescriptor on Elevated runs is refused" "deny" \
    "$(decision PowerShell "\$s = New-Object -ComObject Schedule.Service; \$s.Connect(); \$s.GetFolder('\').GetTask('Elevated runs').SetSecurityDescriptor(\$sd, 0)")"
assert_eq "COM Run through .Invoke on Elevated runs is refused" "deny" \
    "$(decision PowerShell "\$s = New-Object -ComObject Schedule.Service; \$s.Connect(); \$t = \$s.GetFolder('\').GetTask('Elevated runs'); \$t.Run.Invoke(\$null)")"
assert_eq "COM Run through PSObject.Methods on Elevated runs is refused" "deny" \
    "$(decision PowerShell "\$s = New-Object -ComObject Schedule.Service; \$s.Connect(); \$t = \$s.GetFolder('\').GetTask('Elevated runs'); \$t.PSObject.Methods['Run'].Invoke(\$null)")"
assert_eq "COM Run through InvokeMember on Elevated runs is refused" "deny" \
    "$(decision PowerShell "\$s = New-Object -ComObject Schedule.Service; \$s.Connect(); \$t = \$s.GetFolder('\').GetTask('Elevated runs'); [System.__ComObject].InvokeMember('Run', 'InvokeMethod', \$null, \$t, @(\$null))")"
assert_eq "a WMI class's StartByPath on Elevated runs is refused" "deny" \
    "$(decision PowerShell "([wmiclass]'root\Microsoft\Windows\TaskScheduler:PS_ScheduledTask').StartByPath('\', 'Elevated runs')")"
assert_eq "a WMI object's Start on Elevated runs is refused" "deny" \
    "$(decision PowerShell "\$t = Get-WmiObject -Namespace root\Microsoft\Windows\TaskScheduler -Class MSFT_ScheduledTask -Filter \"TaskName='Elevated runs'\"; \$t.Start()")"
assert_eq "Set-CimInstance on MSFT_ScheduledTask Elevated runs is refused" "deny" \
    "$(decision PowerShell "Get-CimInstance -Namespace Root/Microsoft/Windows/TaskScheduler -ClassName MSFT_ScheduledTask -Filter \"TaskName='Elevated runs'\" | Set-CimInstance -Property @{Description='x'}")"
assert_eq "New-CimInstance of MSFT_ScheduledTask Elevated runs is refused" "deny" \
    "$(decision PowerShell "New-CimInstance -Namespace Root/Microsoft/Windows/TaskScheduler -ClassName MSFT_ScheduledTask -Property @{TaskName='Elevated runs'}")"
assert_eq "iwmi Start on MSFT_ScheduledTask Elevated runs is refused" "deny" \
    "$(decision PowerShell "gwmi -Namespace root\Microsoft\Windows\TaskScheduler -Class MSFT_ScheduledTask -Filter \"TaskName='Elevated runs'\" | iwmi -Name Start")"
assert_eq "Remove-WmiObject on MSFT_ScheduledTask Elevated runs is refused" "deny" \
    "$(decision PowerShell "gwmi -Namespace root\Microsoft\Windows\TaskScheduler -Class MSFT_ScheduledTask -Filter \"TaskName='Elevated runs'\" | Remove-WmiObject")"
assert_eq "wmic delete on MSFT_ScheduledTask Elevated runs is refused" "deny" \
    "$(decision PowerShell "wmic /namespace:\\\\root\Microsoft\Windows\TaskScheduler path MSFT_ScheduledTask where \"TaskName='Elevated runs'\" delete")"
assert_eq "Invoke-CimMethod Start on a WQL _ wildcard for Elevated runs is refused" "deny" \
    "$(decision PowerShell "Get-CimInstance -Namespace Root/Microsoft/Windows/TaskScheduler -ClassName MSFT_ScheduledTask -Filter \"TaskName LIKE 'Elevated_runs'\" | Invoke-CimMethod -MethodName Start")"
assert_eq "Start-Process cmd /c schtasks /run on Elevated runs is refused" "deny" \
    "$(decision PowerShell "Start-Process -FilePath cmd -ArgumentList '/c schtasks /run /tn \"Elevated runs\"'")"
assert_eq "Invoke-CimMethod Start on another task with ForEach-Object after it is allowed" "allow" \
    "$(decision PowerShell "Get-ScheduledTask -TaskName 'dotfiles sync' | Invoke-CimMethod -MethodName Start | % ReturnValue")"
assert_eq "COM Run on every task in another folder through ForEach-Object is allowed" "allow" \
    "$(decision PowerShell "\$s = New-Object -ComObject Schedule.Service; \$s.Connect(); \$s.GetFolder('\dotfiles').GetTasks(0) | % { \$_.Run(\$null) }")"
assert_eq "COM Run on another task with Select-Object * after it is allowed" "allow" \
    "$(decision PowerShell "\$s = New-Object -ComObject Schedule.Service; \$s.Connect(); \$s.GetFolder('\').GetTask('dotfiles sync').Run(\$null) | Select-Object *")"
assert_eq "a commit message naming Invoke-CimMethod Start on MSFT_ScheduledTask is allowed" "allow" \
    "$(decision Bash "git commit -m \"Invoke-CimMethod -MethodName Start on MSFT_ScheduledTask 'Elevated runs' is refused\"")"
assert_eq "a commit message naming Start-Process schtasks /run is allowed" "allow" \
    "$(decision PowerShell "git commit -m 'Start-Process schtasks -ArgumentList /run /tn Elevated runs is refused'")"
assert_eq "a hashtable naming the runner's root, splatted into a read, is allowed" "allow" \
    "$(decision PowerShell "\$p = @{Path='C:\ProgramData\ElevatedRuns\outbox'}; Get-ChildItem @p")"
assert_eq "a hashtable naming the runner's root, splatted into a write, is refused" "deny" \
    "$(decision PowerShell "\$p = @{Path='C:\ProgramData\ElevatedRuns\inbox\r.json'}; Set-Content @p -Value x")"
assert_eq "Start-Process launching elevate enable asks first" "ask" \
    "$(decision PowerShell "Start-Process -FilePath elevate -ArgumentList enable")"
assert_eq "Invoke-CimMethod Start on another task inside ForEach-Object is allowed" "allow" \
    "$(decision PowerShell "Get-ScheduledTask -TaskName 'Backup' | % { \$_ | Invoke-CimMethod -MethodName Start }")"
assert_eq "many wildcards in a call that starts a task answer at once" "allow" \
    "$(decision PowerShell "Get-ScheduledTask x | Invoke-CimMethod -MethodName Start; echo '%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%z'; echo '****************************************z'")"

# The runner's root spelled every way the shells spell it, and the reads around it.
assert_eq "a write into the runner's root by its short name is refused" "deny" \
    "$(decision PowerShell "Set-Content C:\PROGRA~3\ElevatedRuns\inbox\r.json x")"
assert_eq "a write into %ALLUSERSPROFILE%'s runner root is refused" "deny" \
    "$(decision Bash "cmd //c del %ALLUSERSPROFILE%\\\\ElevatedRuns\\\\inbox\\\\r.json")"
assert_eq "a write into the runner's root by its long-path prefix is refused" "deny" \
    "$(decision PowerShell "Remove-Item '\\\\?\C:\ProgramData\ElevatedRuns\inbox\r.json'")"
assert_eq "a write into the runner's root by its device prefix is refused" "deny" \
    "$(decision PowerShell "Set-Content '\\\\.\C:\ProgramData\ElevatedRuns\inbox\r.json' x")"
assert_eq "a write into the runner's root through All Users is refused" "deny" \
    "$(decision PowerShell "Set-Content 'C:\Users\All Users\ElevatedRuns\inbox\r.json' x")"
assert_eq "a write into the runner's root through Application Data is refused" "deny" \
    "$(decision PowerShell "Set-Content 'C:\ProgramData\Application Data\ElevatedRuns\inbox\r.json' x")"
assert_eq "a write into the runner's root by both short names is refused" "deny" \
    "$(decision PowerShell "Set-Content C:\PROGRA~3\ELEVAT~1\inbox\r.json x")"
assert_eq "a write into another short-named folder of ProgramData is allowed" "allow" \
    "$(decision PowerShell "Set-Content C:\PROGRA~3\OTHER~1\x.txt y")"
assert_eq "a write into the runner's root under /mnt/c is refused" "deny" \
    "$(decision Bash "touch /mnt/c/ProgramData/ElevatedRuns/inbox/r.json")"
assert_eq "a write into the runner's root under /cygdrive/c is refused" "deny" \
    "$(decision Bash "touch /cygdrive/c/ProgramData/ElevatedRuns/inbox/r.json")"
assert_eq "a write into the runner's root given as --opt=path is refused" "deny" \
    "$(decision Bash "rsync x --temp-dir=/c/ProgramData/ElevatedRuns/inbox y")"
assert_eq "copying a result out of the runner's root is allowed" "allow" \
    "$(decision PowerShell "Copy-Item C:\ProgramData\ElevatedRuns\results\r.json .")"
assert_eq "copying into the runner's root with cp -t is refused" "deny" \
    "$(decision Bash "cp -t /c/ProgramData/ElevatedRuns/inbox r.json")"
assert_eq "reading the runner's results with jq is allowed" "allow" \
    "$(decision Bash "jq . /c/ProgramData/ElevatedRuns/results/r.json")"
assert_eq "icacls reading the runner's root is allowed" "allow" \
    "$(decision PowerShell "icacls C:\ProgramData\ElevatedRuns")"
assert_eq "icacls granting on the runner's root is refused" "deny" \
    "$(decision PowerShell "icacls C:\ProgramData\ElevatedRuns /grant Users:F")"

# The hook sees only the shell tools, so the settings fragment keeps Claude Code's file tools out
# of the runner's root with deny rules. An Edit rule covers Write and NotebookEdit too; Windows
# paths match in POSIX form, case-insensitively, and a `\\?\` path only matches a `//**/` rule.
fragment="$REPO_ROOT/ai/claude/settings.json"
denies() { jq -r --arg rule "$1" '[.permissions.deny // [] | .[] | select(. == $rule)] | length' "$fragment"; }
assert_eq "the file tools are denied the runner's root" "1" \
    "$(denies 'Edit(//c/ProgramData/ElevatedRuns/**)')"
assert_eq "the file tools are denied the runner's root under any prefix or drive" "1" \
    "$(denies 'Edit(//**/ProgramData/ElevatedRuns/**)')"

assert_eq "a call with no command is allowed" "allow" \
    "$(echo '{"tool_name":"Read","tool_input":{"file_path":"a"}}' | node "$guard" | wc -c | tr -d ' ' | sed 's/^0$/allow/')"

assert_summary "agent-guard"
