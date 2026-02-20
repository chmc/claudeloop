#!/bin/sh
# claudeloop installer
# Supports local mode (run from repo checkout) and download mode (public release)

set -eu

REPO="chmc/claudeloop"
BIN_NAME="claudeloop"

# Resolve mode: local if claudeloop + lib/ exist next to this script
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
if [ -f "$SCRIPT_DIR/claudeloop" ] && [ -d "$SCRIPT_DIR/lib" ]; then
  MODE="local"
  SRC_DIR="$SCRIPT_DIR"
else
  MODE="download"
fi

# Resolve version (download mode only)
if [ "$MODE" = "download" ]; then
  if [ -z "${VERSION:-}" ]; then
    echo "Fetching latest version..."
    VERSION=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
      | grep '"tag_name"' | sed 's/.*"tag_name": *"v\([^"]*\)".*/\1/')
    if [ -z "$VERSION" ]; then
      echo "error: could not determine latest version" >&2
      exit 1
    fi
  fi
  echo "Version: $VERSION"
fi

# Determine install dirs (system-wide if writable, else user-local)
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

echo "Installing to $INSTALL_DIR"

# Download mode: fetch tarball
if [ "$MODE" = "download" ]; then
  TARBALL_URL="https://github.com/$REPO/releases/download/v${VERSION}/claudeloop-v${VERSION}.tar.gz"
  TMP_DIR=$(mktemp -d)
  trap 'rm -rf "$TMP_DIR"' EXIT
  echo "Downloading $TARBALL_URL ..."
  curl -fsSL "$TARBALL_URL" -o "$TMP_DIR/claudeloop.tar.gz"
  tar -xzf "$TMP_DIR/claudeloop.tar.gz" -C "$TMP_DIR"
  SRC_DIR="$TMP_DIR/claudeloop-v${VERSION}"
fi

# Install files
mkdir -p "$INSTALL_DIR/lib"
cp "$SRC_DIR/claudeloop" "$INSTALL_DIR/claudeloop"
chmod +x "$INSTALL_DIR/claudeloop"
cp "$SRC_DIR/lib/"*.sh "$INSTALL_DIR/lib/"

# Determine installed version
if [ "$MODE" = "local" ]; then
  VERSION=$(grep '^VERSION=' "$INSTALL_DIR/claudeloop" | sed 's/VERSION="\(.*\)"/\1/')
fi

# Write wrapper to BIN_DIR
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/$BIN_NAME" <<EOF
#!/bin/sh
exec "$INSTALL_DIR/claudeloop" "\$@"
EOF
chmod +x "$BIN_DIR/$BIN_NAME"

echo "claudeloop v${VERSION} installed → $BIN_DIR/$BIN_NAME"

# PATH warning if needed
case ":${PATH}:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo ""
    echo "Warning: $BIN_DIR is not in your PATH."
    echo "Add this to your shell profile (~/.zshrc, ~/.bashrc, or ~/.profile):"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac
