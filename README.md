# w(ork)t(rees)

A fast CLI for managing git worktrees. One command to create a branch, set up the worktree, and `cd` into it.

```bash
wtb feature-x   # creates branch + worktree and cd's into it
```

Git worktrees let you work on multiple branches simultaneously without stashing or cloning, but the built-in commands are verbose. `wt` stores all worktrees in `~/.local/share/wt/<repo>/<branch>` and lets you jump between them from anywhere. It also includes optional Docker integration to spin up isolated containers per worktree, with built-in support for running [Claude Code](https://claude.ai/code) inside them.

## Quick Start

### Prerequisites

- **OCaml >= 4.14** and **opam** (OCaml package manager)
- **Git**

If you don't have OCaml installed:

```bash
# macOS
brew install opam
opam init
eval $(opam env)

# Ubuntu/Debian
sudo apt install opam
opam init
eval $(opam env)
```

### Install

```bash
git clone https://github.com/cristeahub/wt.git
cd wt
opam install . --deps-only
./install.sh
```

The install script will:

1. Build the project with `dune build`
2. Install the `wt` binary to `~/.local/bin/`
3. Optionally add the `wtb` shell function and tab completion to your `.zshrc`

Make sure `~/.local/bin` is in your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Usage

### Create or navigate to a worktree

```bash
wt b feature-x    # creates branch + worktree, prints path
wtb feature-x     # same, but also cd's into it (requires shell function)
```

If a worktree for the branch already exists (in any repo), `wt b` navigates to it. Otherwise it creates a new branch and worktree from the current repo.

When the same branch name exists in multiple repos, you'll be prompted to choose:

```
Branch 'feature-x' exists in multiple repos:

  1) myapp -> /home/you/.local/share/wt/myapp/feature-x
  2) mylib -> /home/you/.local/share/wt/mylib/feature-x

Select [1-2]:
```

### Delete a worktree

```bash
wt d feature-x    # removes worktree, keeps the branch
wt db feature-x   # removes worktree AND deletes the branch
```

### List all worktrees

```bash
wt list
```

```
myrepo:
  feature-x    -> /home/you/.local/share/wt/myrepo/feature-x
  bugfix_auth  -> /home/you/.local/share/wt/myrepo/bugfix_auth

other-repo:
  main         -> /home/you/.local/share/wt/other-repo/main
```

## Shell Integration

The `wtb` function wraps `wt b` and cd's into the result:

```bash
wtb() { local dir=$(wt b "$1" | tail -1); [ -d "$dir" ] && cd "$dir"; }
```

The installer adds this to `.zshrc` with zsh-specific tab completion. For bash, add the function to `.bashrc` manually. Tab completion autocompletes from:

- Git branches in the current repo
- Existing worktree branch names from `~/.local/share/wt/`

## Copying Untracked Files (`.wtfiles`)

Projects often have untracked files — `.env`, local configs, secrets — that aren't in git but are needed to work. You can create a `.wtfiles` file in your repo root listing these paths, and `wt` will automatically copy them into every new worktree.

```
# .wtfiles — one path per line
.env
secrets/api_key.json
config/local.yml
```

When you run `wt b <branch>` and a new worktree is created, each listed file or directory is copied from the current repo root into the new worktree:

```
$ wt b feature-x
Copied .env
Copied config/local.yml
Warning: secrets/api_key.json not found, skipping
Created branch 'feature-x' and worktree at: ~/.local/share/wt/myrepo/feature-x
```

- Lines starting with `#` are comments
- Directories are copied recursively
- Missing files are skipped with a warning
- Files are independent copies — changes in one worktree won't affect others
- `.wtfiles` itself can be committed to the repo (it only references untracked paths)

## How it works

### Storage layout

```
~/.local/share/wt/
└── <repo>/
    ├── feature-x/         # worktree directories
    └── feature_auth/      # slashes in branch names are underscore-escaped
```

### Design decisions

- **Centralized storage** - All worktrees live under `~/.local/share/wt/` regardless of where you invoke `wt`, so you can navigate to any branch from any directory.
- **Non-destructive by default** - `wt d` only removes the worktree; the git branch is preserved. Use `wt db` to remove both.
### Dependencies

No external OCaml dependencies beyond the standard library.

## Building from source

```bash
opam install . --deps-only   # install OCaml dependencies
dune build                   # compile
dune exec wt -- --help       # run without installing
./install.sh                 # build + install to ~/.local/bin/wt
```

## License

MIT License. See [LICENSE](LICENSE) for details.
