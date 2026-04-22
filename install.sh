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

# Completion function for wtb - provides tab completion for branch names
COMPLETION_FUNCTION='_wtb() {
  local branches=()
  # Add git branches from current repo
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    branches+=(${(f)"$(git branch --format='"'"'%(refname:short)'"'"' 2>/dev/null)"})
  fi
  # Add branches from existing worktrees
  local wt_base="$HOME/.local/share/wt"
  if [[ -d "$wt_base" ]]; then
    for repo_dir in "$wt_base"/*(/N); do
      for branch_dir in "$repo_dir"/*(/N); do
        branches+=("${branch_dir:t}")
      done
    done
  fi
  # Remove duplicates
  branches=(${(u)branches})
  _describe '"'"'branch'"'"' branches
}
compdef _wtb wtb'

echo ""
read -p "Would you like to add the 'wtb' shell function to ~/.zshrc for auto-cd? [y/N] " -n 1 -r
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

    # Check if completion function already exists
    if grep -q "_wtb()" "$ZSHRC" 2>/dev/null; then
        echo "The wtb completion already exists in $ZSHRC"
    else
        echo "" >> "$ZSHRC"
        echo "# Tab completion for wtb" >> "$ZSHRC"
        echo "$COMPLETION_FUNCTION" >> "$ZSHRC"
        echo "Added wtb tab completion to $ZSHRC"
        ADDED_SOMETHING=true
    fi

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
echo "  wt repo <name>      Print absolute path of a repo"
echo "  wt list             List all worktrees"
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "  wtb <branch>       Create and cd into worktree"
fi

