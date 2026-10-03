#!/usr/bin/env node

// md-lint: markdownlint-cli2 with the dotfiles default rules.
//
// markdownlint-cli2 reads a config only from the current directory downwards - a config in a
// parent directory or in your home directory is ignored - so there is no way to set defaults
// globally. This passes powershell/markdownlint.jsonc with --config, unless the current
// directory has a config of its own, in which case the repo wins and nothing is passed.
//
//   md-lint                 every .md under the current directory
//   md-lint README.md       one file
//   md-lint --fix "**/*.md" arguments pass straight through
//
// A program on PATH rather than a profile function, so agents can run it: their shells are Git
// Bash or PowerShell started with -NoProfile, and neither loads the profile.

import { spawnSync } from 'node:child_process';
import { existsSync, realpathSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoConfigs = ['.markdownlint-cli2.jsonc', '.markdownlint-cli2.yaml', '.markdownlint-cli2.cjs',
                     '.markdownlint.jsonc', '.markdownlint.json', '.markdownlint.yaml', '.markdownlint.yml'];

export const defaultConfig = join(dirname(fileURLToPath(import.meta.url)), '..', 'powershell', 'markdownlint.jsonc');

export function hasOwnConfig(dir) {
    return repoConfigs.some((name) => existsSync(join(dir, name)));
}

// The arguments for markdownlint-cli2, given md-lint's own.
export function markdownlintArguments(args, ownConfig) {
    const files = args.length > 0 ? args : ['**/*.md'];
    return ownConfig ? files : ['--config', defaultConfig, ...files];
}

// npm installs markdownlint-cli2 on Windows as a .cmd, which Node runs only through a shell,
// and cmd.exe needs each argument quoted for a path with a space in it to survive.
function run(args) {
    if (process.platform !== 'win32') {
        return spawnSync('markdownlint-cli2', args, { stdio: 'inherit' });
    }
    const quoted = args.map((arg) => `"${arg}"`);
    return spawnSync('markdownlint-cli2', quoted, { stdio: 'inherit', shell: true });
}

// The shims in bin/ call this file by path; when imported, it only exports.
if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
    const result = run(markdownlintArguments(process.argv.slice(2), hasOwnConfig(process.cwd())));
    if (result.error) {
        console.error(`md-lint: could not run markdownlint-cli2 (${result.error.message}). Install it with powershell\\install-tools.ps1`);
        process.exit(1);
    }
    process.exit(result.status ?? 1);
}
