#!/bin/bash
# Update every installed vh-tricks trick by re-running its install.sh.
#   curl -fsSL https://raw.githubusercontent.com/vhqtvn/vh-tricks/main/update.sh | bash
#   ... | bash -s -- --list        show which tricks are installed
#   ... | bash -s -- nvm/global    update only the named tricks

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/vhqtvn/vh-tricks/main}"
export REPO_RAW
BIN_DIR="$HOME/.local/bin"

# trick name -> file whose presence means it is installed
TRICKS=(
  "nvm/global:$BIN_DIR/npm-global"
  "claude/multi:$BIN_DIR/claude-multi"
)

installed() { [ -e "${1#*:}" ]; }

if [ "$1" = "--list" ]; then
  for t in "${TRICKS[@]}"; do
    installed "$t" && echo "${t%%:*}: installed" || echo "${t%%:*}: not installed"
  done
  exit 0
fi

# Run installers from an empty dir: some prefer ./files from a local clone
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

updated=() failed=() skipped=()
for t in "${TRICKS[@]}"; do
  name="${t%%:*}"
  if [ $# -gt 0 ] && [[ " $* " != *" $name "* ]]; then
    continue
  fi
  if ! installed "$t"; then
    skipped+=("$name")
    continue
  fi
  echo "==> Updating $name"
  if (cd "$WORK" && curl -fsSL "$REPO_RAW/$name/install.sh" | bash) </dev/null; then
    updated+=("$name")
  else
    failed+=("$name")
  fi
  echo
done

echo "Updated: ${updated[*]:-none}"
[ ${#skipped[@]} -gt 0 ] && echo "Not installed (skipped): ${skipped[*]}"
if [ ${#failed[@]} -gt 0 ]; then
  echo "Failed: ${failed[*]}"
  exit 1
fi
exit 0
