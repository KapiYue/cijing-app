#!/usr/bin/env bash
set -euo pipefail

VERSION="2.109.1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$ROOT_DIR/.tools/supabase-$VERSION"
BINARY="$TOOLS_DIR/supabase"

if [[ ! -x "$BINARY" ]]; then
  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  ARCH="$(uname -m)"
  [[ "$ARCH" == "x86_64" ]] && ARCH="amd64"
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
  ARCHIVE="supabase_${VERSION}_${OS}_${ARCH}.tar.gz"
  URL="https://github.com/supabase/cli/releases/download/v${VERSION}/${ARCHIVE}"
  mkdir -p "$TOOLS_DIR"
  echo "Downloading Supabase CLI v${VERSION}..."
  curl -fL "$URL" -o "$TOOLS_DIR/supabase.tar.gz"
  tar -xzf "$TOOLS_DIR/supabase.tar.gz" -C "$TOOLS_DIR"
  rm "$TOOLS_DIR/supabase.tar.gz"
fi

cd "$ROOT_DIR"
exec "$BINARY" "$@"

