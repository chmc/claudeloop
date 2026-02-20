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

echo "claudeloop uninstalled."
