#!/bin/sh
# claudeloop uninstaller

set -eu

BIN_NAME="claudeloop"

# Same defaults as install.sh
if [ -w "/usr/local" ] || [ -w "/usr/local/lib" ]; then
  INSTALL_DIR="/usr/local/lib/claudeloop"
  BIN_DIR="/usr/local/bin"
else
  INSTALL_DIR="$HOME/.local/lib/claudeloop"
  BIN_DIR="$HOME/.local/bin"
fi

# Override from env if set
INSTALL_DIR="${INSTALL_DIR_OVERRIDE:-$INSTALL_DIR}"
BIN_DIR="${BIN_DIR_OVERRIDE:-$BIN_DIR}"

rm -rf "$INSTALL_DIR"
rm -f "$BIN_DIR/$BIN_NAME"

# PATH cleanup
MARKER_BEGIN="# >>> claudeloop PATH begin <<<"
MARKER_END="# >>> claudeloop PATH end <<<"

detect_profile() {
  case "${SHELL:-}" in
    */zsh)  printf '%s\n' "$HOME/.zshrc" ;;
    */bash)
      case "$(uname -s)" in
        Darwin) printf '%s\n' "$HOME/.bash_profile" ;;
        *)      printf '%s\n' "$HOME/.bashrc" ;;
      esac
      ;;
    *)      printf '%s\n' "$HOME/.profile" ;;
  esac
}

_profile=$(detect_profile)
if grep -qF "$MARKER_BEGIN" "$_profile" 2>/dev/null; then
  tmp=$(mktemp)
  if awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" \
         '$0 == b, $0 == e { next } 1' \
         "$_profile" > "$tmp"; then
    mv "$tmp" "$_profile"
    echo "Removed PATH entry from $_profile"
  else
    rm -f "$tmp"
    echo "Warning: failed to remove PATH entry from $_profile" >&2
  fi
fi

echo "claudeloop uninstalled."
