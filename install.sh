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

# PATH auto-configuration
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

case ":${PATH}:" in
  *":$BIN_DIR:"*) ;;
  *)
    _profile=$(detect_profile)
    if grep -qF "$MARKER_BEGIN" "$_profile" 2>/dev/null; then
      echo ""
      echo "Warning: $BIN_DIR is not in your PATH."
      echo "PATH entry already present in $_profile — open a new shell or run:"
      echo "  source $_profile"
    else
      printf '\n%s\nexport PATH="%s:$PATH"\n%s\n' \
        "$MARKER_BEGIN" "$BIN_DIR" "$MARKER_END" >> "$_profile"
      echo ""
      echo "Warning: $BIN_DIR is not in your PATH."
      echo "Added PATH entry to $_profile"
      echo "To apply now, run: source $_profile"
    fi
    ;;
esac
