#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.local/bin"
EXECUTABLE="$SCRIPT_DIR/_build/default/bin/main.exe"

# Build first
echo "Building wt..."
cd "$SCRIPT_DIR"
dune build

# Ensure install directory exists
mkdir -p "$INSTALL_DIR"

# Remove existing executable if present (avoids permission issues)
rm -f "$INSTALL_DIR/wt"

# Copy executable
echo "Installing wt to $INSTALL_DIR..."
cp "$EXECUTABLE" "$INSTALL_DIR/wt"
chmod +x "$INSTALL_DIR/wt"

echo "Installed wt to $INSTALL_DIR/wt"

# Check if ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo ""
    echo "Note: $INSTALL_DIR is not in your PATH."
    echo "Add this to your ~/.zshrc:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
fi

# Ask about zshrc integration
ZSHRC="$HOME/.zshrc"

# Shell function for wtb
SHELL_FUNCTION='wtb() { local dir=$(wt b "$1" | tail -1); [ -d "$dir" ] && cd "$dir"; }'

# Completion functions for wt and wtb
COMPLETION_FUNCTION='_wt_decode_branch_name() {
  local encoded="$1"
  local decoded=""
  local i=1

  while (( i <= ${#encoded} )); do
    local ch="${encoded[$i]}"
    local next="${encoded[$((i + 1))]}"
    if [[ "$ch" == "_" && "$next" == "_" ]]; then
      decoded+="_"
      ((i += 2))
    elif [[ "$ch" == "_" ]]; then
      decoded+="/"
      ((i += 1))
    else
      decoded+="$ch"
      ((i += 1))
    fi
  done

  print -r -- "$decoded"
}

_wt_worktree_branch_names() {
  local branches=()
  local wt_base="$HOME/.local/share/wt"

  if [[ -d "$wt_base" ]]; then
    for repo_dir in "$wt_base"/*(/N); do
      for branch_dir in "$repo_dir"/*(/N); do
        branches+=("$(_wt_decode_branch_name "${branch_dir:t}")")
      done
    done
  fi

  print -l -- "${branches[@]}"
}

_wt_add_matches() {
  local cur="${words[$CURRENT]}"
  local matches=()
  local candidate

  for candidate in "$@"; do
    if [[ "$candidate" == "$cur"* ]]; then
      matches+=("$candidate")
    fi
  done

  matches=("${(@u)matches}")
  if (( ${#matches} > 0 )); then
    compadd -U -Q -- "${matches[@]}"
  fi
}

_wt_branch_names() {
  local branches=()

  # Add git branches from current repo
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    branches+=( ${(f)"$(git branch --format="%(refname:short)" 2>/dev/null)"} )
  fi

  # Add branches from existing worktrees
  branches+=( $(_wt_worktree_branch_names) )

  _wt_add_matches "${branches[@]}"
}

_wt_repo_names() {
  local names=()
  local wt_base="$HOME/.local/share/wt"

  if [[ -d "$wt_base" ]]; then
    for repo_dir in "$wt_base"/*(/N); do
      local repo_name="${repo_dir:t}"
      if [[ "$repo_name" == *_* ]]; then
        names+=("${repo_name//_//}")
      else
        names+=("$repo_name")
      fi
    done
  fi

  # wt repo accepts either repo names or existing worktree branch names.
  names+=( $(_wt_worktree_branch_names) )

  _wt_add_matches "${names[@]}"
}

_wt() {
  local -a commands
  commands=(
    "b:Create branch and worktree, or navigate to existing"
    "d:Delete worktree, keeping branch"
    "db:Delete worktree and branch"
    "repo:Print path of a repo or existing worktree"
    "da:Delete all worktrees and branches"
    "list:List all worktrees"
  )

  if (( CURRENT == 2 )); then
    _describe "command" commands
    return
  fi

  case "${words[2]}" in
    b|d|db) _wt_branch_names ;;
    repo) _wt_repo_names ;;
  esac
}

_wtb() {
  _wt_branch_names
}

compdef _wt wt
compdef _wtb wtb'

echo ""
read -p "Would you like to add shell integration to ~/.zshrc (wtb auto-cd + tab completion)? [y/N] " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    ADDED_SOMETHING=false

    # Check if function already exists
    if grep -q "wtb()" "$ZSHRC" 2>/dev/null; then
        echo "The wtb function already exists in $ZSHRC"
    else
        echo "" >> "$ZSHRC"
        echo "# wt - git worktree helper" >> "$ZSHRC"
        echo "$SHELL_FUNCTION" >> "$ZSHRC"
        echo "Added wtb function to $ZSHRC"
        ADDED_SOMETHING=true
    fi

    # Always append the latest completion block. If an older _wt() exists earlier
    # in .zshrc, this later definition overrides it when the file is sourced.
    HAD_COMPLETION=false
    if grep -q "_wt()" "$ZSHRC" 2>/dev/null; then
        HAD_COMPLETION=true
    fi
    echo "" >> "$ZSHRC"
    echo "# Tab completion for wt and wtb" >> "$ZSHRC"
    echo "$COMPLETION_FUNCTION" >> "$ZSHRC"
    if $HAD_COMPLETION; then
        echo "Updated wt and wtb tab completion in $ZSHRC"
    else
        echo "Added wt and wtb tab completion to $ZSHRC"
    fi
    ADDED_SOMETHING=true

    if $ADDED_SOMETHING; then
        echo "Run 'source ~/.zshrc' or restart your shell to use it."
    fi
fi

echo ""
echo "Installation complete!"
echo ""
echo "Usage:"
echo "  wt b <branch>       Create/navigate to branch worktree"
echo "  wt d <branch>       Delete worktree (keeps branch)"
echo "  wt db <branch>      Delete both worktree and branch"
echo "  wt repo <name>      Print path of a repo or existing worktree"
echo "  wt list             List all worktrees"
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "  wtb <branch>       Create and cd into worktree"
fi

