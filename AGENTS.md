# AGENTS.md

## Shell scripts

- Print with plain `echo` or the helpers in `ai/helpers/output.sh`, rather than a logging function of the script's own.
- Check an optional tool with `command -v` before using it.

## Agent skills

### Issue tracker

Issues are tracked as GitHub Issues on `hugoforte/dotfiles`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
