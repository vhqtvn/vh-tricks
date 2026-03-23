#!/bin/bash
set -e

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/vhqtvn/vh-tricks/main}"
BASE="$REPO_RAW/nvm/global/files"
WRAPPER_DIR="$HOME/.local/bin/once-wrapper/node"
BIN_DIR="$HOME/.local/bin"
MARKER_BEGIN="# >>> vh-tricks: nvm/global >>>"
MARKER_END="# <<< vh-tricks: nvm/global <<<"

remove_rc_block() {
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue
    sed -i "\|$MARKER_BEGIN|,\|$MARKER_END|d" "$rc"
  done
}

if [ "$1" = "--uninstall" ]; then
  rm -f "$WRAPPER_DIR/node" "$WRAPPER_DIR/npm" "$WRAPPER_DIR/pnpm" "$WRAPPER_DIR/yarn"
  rm -f "$HOME/.local/bin/once-wrapper/.include.sh"
  rmdir "$WRAPPER_DIR" 2>/dev/null || true
  rmdir "$HOME/.local/bin/once-wrapper" 2>/dev/null || true
  rm -f "$BIN_DIR/npm-global"
  remove_rc_block
  echo "Uninstalled nvm/global trick."
  exit 0
fi

# Require nvm
if [ ! -s "$HOME/.nvm/nvm.sh" ]; then
  echo "nvm not found. Install nvm first: https://github.com/nvm-sh/nvm"
  exit 1
fi

# Download files
mkdir -p "$WRAPPER_DIR"
curl -fsSL "$BASE/once-wrapper/.include.sh" -o "$HOME/.local/bin/once-wrapper/.include.sh"
curl -fsSL "$BASE/once-wrapper/node/node" -o "$WRAPPER_DIR/node"
curl -fsSL "$BASE/npm-global" -o "$BIN_DIR/npm-global"

# Permissions and symlinks
chmod +x "$WRAPPER_DIR/node" "$BIN_DIR/npm-global"
for cmd in npm pnpm yarn; do
  ln -sf node "$WRAPPER_DIR/$cmd"
done

# Setup npm-global prefix
mkdir -p "$HOME/.npm-global"
[ -f "$HOME/.npm-global/.nvmrc" ] || echo "lts/*" > "$HOME/.npm-global/.nvmrc"

# Idempotent: remove old block then re-add
remove_rc_block
PATH_BLOCK="$MARKER_BEGIN
export PATH=\"\$HOME/.local/bin/once-wrapper/node:\$HOME/.local/bin:\$HOME/.npm-global/bin:\$PATH\"
$MARKER_END"
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [ -f "$rc" ] || continue
  echo "$PATH_BLOCK" >> "$rc"
done

echo "Done! Restart your shell or: source ~/.bashrc (or ~/.zshrc)"
echo "To uninstall: curl -fsSL ... | bash -s -- --uninstall"
