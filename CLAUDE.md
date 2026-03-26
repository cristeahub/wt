# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
dune build              # Build the project
dune clean              # Clean build artifacts
./install.sh            # Build and install to ~/.local/bin/wt
```

## Architecture

This is an OCaml CLI tool for managing git worktrees. It stores worktrees in `~/.local/share/wt/<repo>/<branch>`.

### Project Structure

- `bin/main.ml` - CLI entry point, argument parsing, routes to `Wt_lib` modules
- `lib/utils.ml` - Shared utilities: shell escaping, branch name encoding, file I/O, command execution
- `lib/git.ml` - Git operations: branch/worktree CRUD via git CLI
- `lib/worktree.ml` - Core logic: worktree path management, branch/delete/list commands
- `lib/docker.ml` - Docker container management for worktrees
- `docker/Dockerfile` - Polyglot base image (Ubuntu + Python, Node, Rust, Go, Claude CLI)

### Dependencies

- Docker - Required for `wt docker` and `wt run` commands

### Key Design Decisions

- Uses `Unix.open_process_in` for git command execution (no external process libraries)
- Worktree paths use underscore escaping (`/` → `_`, `_` → `__`) for branch names to avoid collisions
- `wt b <branch>` outputs the worktree path on the last line, enabling the shell function `wtb()` to auto-cd
- Can navigate to existing worktrees from any directory, but creating new ones requires being in a git repo
- `wt d` only removes the worktree (non-destructive), `wt db` removes both worktree and branch
- When same branch exists in multiple repos, prompts user to select via numbered list
- Docker containers are named `wt-<repo>-<branch>` and are reused across sessions
- Worktree is mounted at `/workspace`
- Host's `~/.claude` mounted to `/home/dev/.claude`, `~/.claude.json` to `/home/dev/.claude.json`
- Claude OAuth token stored in `~/.local/share/wt/token`, injected via `CLAUDE_CODE_OAUTH_TOKEN` env var
- `wt login` command saves token for container authentication
