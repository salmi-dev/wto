#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)
	WTO="$REPO_ROOT/wto"
	VERSION=$(sed -n 's/^VERSION=//p' "$WTO")
}

@test "version prints only semver when stdout is not a terminal" {
	run "$WTO" version

	[ "$status" -eq 0 ]
	[ "$output" = "$VERSION" ]
}

@test "--version prints only semver when stdout is not a terminal" {
	run "$WTO" --version

	[ "$status" -eq 0 ]
	[ "$output" = "$VERSION" ]
}

@test "help includes banner, version, and commands" {
	run env WTO_COLOR=never "$WTO" --help

	[ "$status" -eq 0 ]
	[[ "$output" == *"██╗    ██╗████████╗ ██████╗"* ]]
	[[ "$output" == *"wto v$VERSION - WorkTree Organizer"* ]]
	[[ "$output" == *"wto [status] [--format table|json]"* ]]
	[[ "$output" == *"wto new <branch>"* ]]
	[[ "$output" == *"wto worktree version"* ]]
}

@test "unknown command prints a clear error and compact hint" {
	run env WTO_COLOR=never "$WTO" asdasd

	[ "$status" -eq 1 ]
	[[ "$output" == *"error Unknown command: asdasd"* ]]
	[[ "$output" == *"Usage: wto <command> [options]"* ]]
	[[ "$output" == *"Run 'wto --help' for full usage."* ]]
	[[ "$output" != *"Structure:"* ]]
}

@test "unknown worktree command prints a clear error and compact hint" {
	run env WTO_COLOR=never "$WTO" worktree nope

	[ "$status" -eq 1 ]
	[[ "$output" == *"error Unknown worktree command: nope"* ]]
	[[ "$output" == *"Worktree: wto worktree <status|new|create|tmux|version|close>"* ]]
	[[ "$output" != *"Structure:"* ]]
}

make_managed_repo() {
	tmp=$1
	src="$tmp/src"
	origin="$tmp/origin.git"
	managed="$tmp/managed"

	git init "$src" >/dev/null
	git -C "$src" config user.email test@example.com
	git -C "$src" config user.name Test
	printf 'hello\n' >"$src/README.md"
	git -C "$src" add README.md
	git -C "$src" commit -m init >/dev/null
	git -C "$src" branch -M main
	git -C "$src" checkout -b feature/status >/dev/null 2>&1
	printf 'feature\n' >"$src/feature.txt"
	git -C "$src" add feature.txt
	git -C "$src" commit -m feature >/dev/null
	git clone --bare "$src" "$origin" >/dev/null 2>&1
	git --git-dir="$origin" symbolic-ref HEAD refs/heads/main

	mkdir -p "$managed"
	git clone --bare "$origin" "$managed/.bare" >/dev/null 2>&1
	git --git-dir="$managed/.bare" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
	git --git-dir="$managed/.bare" fetch origin --prune >/dev/null
	git --git-dir="$managed/.bare" update-ref -d refs/heads/main
	git --git-dir="$managed/.bare" update-ref -d refs/heads/feature/status
	git --git-dir="$managed/.bare" worktree add -b main "$managed/managed-main" origin/main >/dev/null
	git --git-dir="$managed/.bare" worktree add -b feature/status "$managed/feature/status" origin/feature/status >/dev/null
}

@test "status is the default command and prints json when stdout is not a terminal" {
	tmp=$(mktemp -d)
	make_managed_repo "$tmp"
	git_dir=$(dirname "$(command -v git)")

	cd "$tmp/managed"
	run env WTO_COLOR=never PATH="$git_dir:/usr/bin:/bin" "$WTO"

	[ "$status" -eq 0 ]
	[[ "$output" == \{\"baseDir\":* ]]
	[[ "$output" == *"\"worktrees\":["* ]]
	[[ "$output" == *"\"name\":\"managed-main\""* ]]
	[[ "$output" == *"\"branch\":\"main\""* ]]
	[[ "$output" == *"\"remoteBranch\":\"origin/main\""* ]]
	[[ "$output" == *"\"name\":\"feature/status\""* ]]
	[[ "$output" == *"\"branch\":\"feature/status\""* ]]
	[[ "$output" == *"\"state\":\"clean\""* ]]
}

@test "status --format table prints a banner and box-drawing table" {
	tmp=$(mktemp -d)
	make_managed_repo "$tmp"
	git_dir=$(dirname "$(command -v git)")
	managed_path=$(cd "$tmp/managed" && pwd -P)

	cd "$tmp/managed"
	run env WTO_COLOR=never PATH="$git_dir:/usr/bin:/bin" "$WTO" status --format table

	[ "$status" -eq 0 ]
	[[ "$output" == *"██╗    ██╗████████╗ ██████╗"* ]]
	[[ "$output" == *"status $managed_path"* ]]
	[[ "$output" == *"┌"* ]]
	[[ "$output" == *"│ here │ worktree"* ]]
	[[ "$output" == *"├"* ]]
	[[ "$output" == *"└"* ]]
	[[ "$output" == *"managed-main"* ]]
	[[ "$output" == *"feature/status"* ]]
	[[ "$output" == *"origin/main"* ]]
}

@test "--format can force default status output without naming status" {
	tmp=$(mktemp -d)
	make_managed_repo "$tmp"
	git_dir=$(dirname "$(command -v git)")

	cd "$tmp/managed"
	run env WTO_COLOR=never PATH="$git_dir:/usr/bin:/bin" "$WTO" --format table

	[ "$status" -eq 0 ]
	[[ "$output" == *"│ here │ worktree"* ]]
	[[ "$output" == *"managed-main"* ]]
}

@test "failed clone reports the failed wto operation and exit code" {
	tmp=$(mktemp -d)

	run env WTO_COLOR=never "$WTO" clone /definitely/not/a/repo "$tmp/managed"

	[ "$status" -eq 1 ]
	[[ "$output" == *"fatal: repository '/definitely/not/a/repo' does not exist"* ]]
	[[ "$output" == *"error Failed to clone bare repository into"* ]]
	[[ "$output" == *"(exit 128)."* ]]
}

@test "missing remote branch reports the branch that failed to fetch" {
	tmp=$(mktemp -d)
	src="$tmp/src"
	origin="$tmp/origin.git"
	managed="$tmp/managed"

	git init "$src" >/dev/null
	git -C "$src" config user.email test@example.com
	git -C "$src" config user.name Test
	printf 'hello\n' >"$src/README.md"
	git -C "$src" add README.md
	git -C "$src" commit -m init >/dev/null
	git -C "$src" branch -M main
	git clone --bare "$src" "$origin" >/dev/null 2>&1
	git --git-dir="$origin" symbolic-ref HEAD refs/heads/main

	printf 'n\n' | env WTO_COLOR=never "$WTO" clone "$origin" "$managed" >/dev/null

	cd "$managed"
	run env WTO_COLOR=never "$WTO" create no-such-branch

	[ "$status" -eq 1 ]
	[[ "$output" == *"fatal: couldn't find remote ref refs/heads/no-such-branch"* ]]
	[[ "$output" == *"error Failed to fetch branch 'no-such-branch' from origin (exit 128)."* ]]
}
