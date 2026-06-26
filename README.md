# WorkTree Organizer

[![CI](https://github.com/salmi-dev/wto/actions/workflows/ci.yml/badge.svg)](https://github.com/salmi-dev/wto/actions/workflows/ci.yml)
[![Auto Release](https://github.com/salmi-dev/wto/actions/workflows/auto-release.yml/badge.svg)](https://github.com/salmi-dev/wto/actions/workflows/auto-release.yml)
[![Latest Release](https://img.shields.io/github/v/release/salmi-dev/wto?label=release)](https://github.com/salmi-dev/wto/releases/latest)
![POSIX sh](https://img.shields.io/badge/POSIX-sh-4EAA25)

`wto` is a POSIX `sh` script for managing GitHub repositories cloned as a bare
repository with sibling worktrees.

## Dependency Choice

The first version is intentionally shell-based:

- `git` owns cloning, fetching, worktree creation, and branch removal.
- `gh` is used only for GitHub PR metadata and PR listing.
- `fzf` is used for interactive selection.
- POSIX `read` handles yes/no prompts, so no extra prompt dependency is needed.
- `tmux` is optional and required only for `wto tmux` or when accepting the
  tmux prompt after worktree creation.

A Deno/TypeScript rewrite can make sense later if this grows into a richer CLI
with config files, structured tests, completions, previews, or a TUI. The
`hunk` package is not a good direct dependency for this script: it is a
Bun/Node-oriented terminal diff viewer/TUI stack, while this tool is mostly
Git/GitHub/tmux orchestration.

## Layout

For a repository directory named `my-repo`:

```text
my-repo/
  .bare/
  my-repo-main
  pr/<pr-branch-name>
  <ctx>/<name>
  br/<name>
```

Rules:

- Main worktree path: `<basedir>/<basedir>-main`
- PR local branch: `<basedir>-PR<NUM>`
- PR worktree path: `<basedir>/pr/<headRefName>`
- Two-part branch path, such as `feat/login`: `<basedir>/feat/login`
- Other branch path: `<basedir>/br/<branch>`

## Usage

```sh
./wto [status] [--format table|json]
./wto clone <git-url> [directory]
./wto new <branch-name>
./wto create [#123|branch-name|main]
./wto tmux
./wto version
./wto close [#123|branch-name|main]
```

The `worktree` namespace is also supported:

```sh
./wto worktree status [--format table|json]
./wto worktree new <branch-name>
./wto worktree create [#123|branch-name|main]
./wto worktree tmux
./wto worktree version
./wto worktree close [#123|branch-name|main]
```

The help screen includes a compact ASCII banner:

```sh
./wto --help
```

Run `create`, `tmux`, and `close` from anywhere inside the managed repository
root, the `.bare` repository, or one of its worktrees.

Run `status`, or just `wto` with no subcommand, to list managed worktrees. In a
terminal, the default output is a colored box-drawing table with the `wto`
banner. When stdout is piped or redirected, the default output is JSON. Use
`--format table` or `--format json` to force either format.

Run `new` to create a local branch from the repository's default branch, push it
to `origin` with upstream tracking, and create a worktree using the same path
layout as `create`.

When `create` is run without a target, `fzf` shows candidates ordered by newest
commit date first. Rows include the target, associated open PR number when
known, and date. Open PRs whose head branch is not present under `origin/*` are
still listed, using the PR update date because no local branch commit exists
yet.

When `tmux` is run without a target, `fzf` shows existing tmux sessions for this
managed repository first, followed by worktrees that do not already have a
session. Selecting a session switches or attaches to it directly. Selecting a
worktree creates a session only when one does not already exist for that
worktree path.

## Version

`wto` follows SemVer and starts at `0.1.0`. The script carries its version in
the `VERSION` variable.

```sh
./wto version
./wto --version
```

In a terminal, the command prints the `wto` banner and version, then checks
dependency availability and versions for `git`, `gh`, `fzf`, and optional
`tmux`. When stdout is piped or redirected, it prints only the version number.

## CI/CD

GitHub Actions runs shell validation on pushes to `main` and pull requests:

- `sh -n wto`
- `shellcheck wto`
- `bats test`
- smoke checks for `./wto --help` and `./wto version`

Run the same test suite locally with:

```sh
bats test
```

After CI succeeds on a push to `main`, the auto-release workflow bumps the patch
version in `wto`, commits the bump, pushes the release commit, and creates a
GitHub release with `gh`. The release step creates the Git tag with the release,
so tags are only added after release creation succeeds.

The auto-release workflow can also be run manually from GitHub Actions. Choose
the SemVer part to bump: `major`, `minor`, or `patch`. The manual default is
`minor`.

There is no tag-triggered release workflow. Use the Auto Release workflow for
both automatic and manual releases.

## Output Styling

`wto` uses color to improve scanability:

- `info`, `ok`, `warn`, and `error` prefixes identify message severity.
- Prompts highlight the question and dim the default choice.
- The `create` picker highlights target, PR, and date columns.
- The help and version banner color `WT` as WorkTree and `O` as Organizer when
  enabled.
- The version dependency report uses colored status glyphs and dependency names
  when enabled.

Color follows the `NO_COLOR` convention by default. Use:

```sh
NO_COLOR=1 ./wto create
WTO_COLOR=never ./wto create
WTO_COLOR=always ./wto create
```

## Tmux Naming

Sessions are named:

```text
<num>| <basedir> | <worktree_name>
```

Numbers start at `100` for main worktrees and `200` for branch or PR worktrees.
The next session uses the largest existing number in that class plus one.

Examples:

```text
100| my-repo | Main
200| my-repo | feature/login
201| my-repo | PR#42
```

## Close Behavior

`wto close`:

1. Selects a worktree with `fzf` unless a selector is provided.
2. Checks for uncommitted changes.
3. Checks whether the branch is ahead of its upstream.
4. Warns when no upstream is configured.
5. Asks before abandoning risky work.
6. Kills tmux sessions whose initial path matches the worktree.
7. Removes the worktree.
8. Deletes the local branch.
