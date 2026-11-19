#!/usr/bin/env bash
# Build a local MOS plugin .deb for Yazi (host architecture).
# The Yazi release binaries are embedded in the .deb under /usr/lib/yazi.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

VERSION="${1:-${VERSION:-}}"
if [ -z "$VERSION" ]; then
  VERSION="$(node -e "import('./page/plugin.config.js').then(m => console.log(m.default.version))" 2>/dev/null || echo 0.2.0)"
fi

case "$(uname -m)" in
  x86_64|amd64) DEB_ARCH=amd64; YAZI_ARCH=x86_64 ;;
  aarch64|arm64) DEB_ARCH=arm64; YAZI_ARCH=aarch64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

PKG_NAME="yazi-${VERSION}-1+mos-plugin_${DEB_ARCH}"
PKG_DIR="$ROOT/build/${PKG_NAME}"
DEB_FILE="$ROOT/build/${PKG_NAME}.deb"
PAGE_DIST="$ROOT/page/dist/yazi"
ASSET="yazi-${YAZI_ARCH}-unknown-linux-gnu.zip"

echo "==> Yazi MOS plugin ${VERSION} (${DEB_ARCH})"

if [ "${SKIP_PAGE:-0}" != "1" ]; then
  if ! command -v npm >/dev/null 2>&1; then
    echo "npm is required to build the plugin page" >&2
    exit 1
  fi
  if [ ! -d "$ROOT/page/node_modules" ]; then
    echo "==> npm install"
    ( cd "$ROOT/page" && npm install )
  fi
  echo "==> building plugin page"
  ( cd "$ROOT/page" && PLUGIN_VERSION="$VERSION" npm run build )
fi

if [ ! -f "$PAGE_DIST/remoteEntry.js" ]; then
  echo "page build output missing: $PAGE_DIST/remoteEntry.js" >&2
  exit 1
fi

rm -rf "$PKG_DIR"
mkdir -p \
  "$PKG_DIR/DEBIAN" \
  "$PKG_DIR/usr/bin/plugins" \
  "$PKG_DIR/usr/lib/yazi" \
  "$PKG_DIR/usr/share/yazi-plugin" \
  "$PKG_DIR/usr/share/bash-completion/completions" \
  "$PKG_DIR/usr/share/zsh/vendor-completions" \
  "$PKG_DIR/usr/share/fish/vendor_completions.d" \
  "$PKG_DIR/var/www/mos-plugins/yazi"

echo "==> fetching Yazi ${ASSET}"
REL="$(curl -fsSL --retry 2 https://api.github.com/repos/sxyazi/yazi/releases/latest)"
TAG="$(printf '%s' "$REL" | jq -r '.tag_name // empty')"
YAZI_VERSION="${TAG#v}"
[ -n "$YAZI_VERSION" ] || { echo "cannot read Yazi release" >&2; exit 1; }
URL="$(printf '%s' "$REL" | jq -r --arg n "$ASSET" '.assets[] | select(.name == $n) | .browser_download_url' | head -n1)"
DIGEST="$(printf '%s' "$REL" | jq -r --arg n "$ASSET" '.assets[] | select(.name == $n) | .digest // empty' | head -n1)"
[ -n "$URL" ] || { echo "no $ASSET asset" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL --retry 2 "$URL" -o "$TMP/yazi.zip"
if [ -n "$DIGEST" ]; then
  case "$DIGEST" in sha256:*) DIGEST="${DIGEST#sha256:}" ;; esac
  printf '%s  %s\n' "$DIGEST" "$TMP/yazi.zip" | sha256sum -c - >/dev/null
fi
unzip -q "$TMP/yazi.zip" -d "$TMP"
SRC="$TMP/yazi-${YAZI_ARCH}-unknown-linux-gnu"
[ -x "$SRC/yazi" ] || { echo "archive does not contain yazi" >&2; exit 1; }
[ -x "$SRC/ya" ] || { echo "archive does not contain ya" >&2; exit 1; }

install -m 0755 "$SRC/yazi" "$PKG_DIR/usr/lib/yazi/yazi"
install -m 0755 "$SRC/ya" "$PKG_DIR/usr/lib/yazi/ya"
install -m 0644 "$SRC/completions/yazi.bash" "$PKG_DIR/usr/share/bash-completion/completions/yazi"
install -m 0644 "$SRC/completions/ya.bash" "$PKG_DIR/usr/share/bash-completion/completions/ya"
install -m 0644 "$SRC/completions/_yazi" "$PKG_DIR/usr/share/zsh/vendor-completions/_yazi"
install -m 0644 "$SRC/completions/_ya" "$PKG_DIR/usr/share/zsh/vendor-completions/_ya"
install -m 0644 "$SRC/completions/yazi.fish" "$PKG_DIR/usr/share/fish/vendor_completions.d/yazi.fish"
install -m 0644 "$SRC/completions/ya.fish" "$PKG_DIR/usr/share/fish/vendor_completions.d/ya.fish"

"$PKG_DIR/usr/lib/yazi/yazi" --version >/dev/null 2>&1 || { echo "Yazi does not run" >&2; exit 1; }

install -m 0755 "$ROOT/yazi-backend" "$PKG_DIR/usr/bin/plugins/yazi"
install -m 0755 "$ROOT/yazi-wrapper" "$PKG_DIR/usr/bin/yazi"
install -m 0755 "$ROOT/ya-wrapper" "$PKG_DIR/usr/bin/ya"

install -m 0755 "$ROOT/yazi-backend" "$PKG_DIR/usr/share/yazi-plugin/yazi-backend"
install -m 0755 "$ROOT/yazi-wrapper" "$PKG_DIR/usr/share/yazi-plugin/yazi-wrapper"
install -m 0755 "$ROOT/ya-wrapper" "$PKG_DIR/usr/share/yazi-plugin/ya-wrapper"
install -m 0755 "$ROOT/functions" "$PKG_DIR/usr/share/yazi-plugin/functions"
install -m 0644 "$ROOT/yazi-env" "$PKG_DIR/usr/share/yazi-plugin/yazi-env"
install -m 0644 "$ROOT/settings.json" "$PKG_DIR/usr/share/yazi-plugin/settings.json"
install -m 0644 "$ROOT/packages" "$PKG_DIR/usr/share/yazi-plugin/packages"

cp -a "$PAGE_DIST/." "$PKG_DIR/var/www/mos-plugins/yazi/"
install -m 0644 "$ROOT/images/yazi.png" "$PKG_DIR/var/www/mos-plugins/yazi/icon.png"

cat > "$PKG_DIR/DEBIAN/control" <<EOF
Package: yazi-plugin
Version: ${VERSION}-1+mos-plugin
Architecture: ${DEB_ARCH}
Maintainer: hustyanzu
Section: utils
Priority: optional
Description: Yazi plugin for MOS
 Blazing fast terminal file manager with optional user-selected app directory.
EOF

install -m 0755 "$ROOT/debian/postinst" "$PKG_DIR/DEBIAN/postinst"
install -m 0755 "$ROOT/debian/postrm" "$PKG_DIR/DEBIAN/postrm"

echo "==> building ${DEB_FILE}"
if command -v dpkg-deb >/dev/null 2>&1; then
  dpkg-deb --build --root-owner-group "$PKG_DIR" "$DEB_FILE"
else
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  printf '2.0\n' > "$WORK/debian-binary"
  ( cd "$PKG_DIR/DEBIAN" && tar --owner=0 --group=0 --numeric-owner -czf "$WORK/control.tar.gz" . )
  ( cd "$PKG_DIR" && tar --owner=0 --group=0 --numeric-owner --exclude=./DEBIAN -czf "$WORK/data.tar.gz" . )
  ( cd "$WORK" && ar rcs "$DEB_FILE" debian-binary control.tar.gz data.tar.gz )
fi

md5sum "$DEB_FILE" | awk '{print $1}' > "$DEB_FILE.md5"

echo
echo "Package: $DEB_FILE"
echo "MD5:     $(cat "$DEB_FILE.md5")"
echo "Yazi:    $YAZI_VERSION"
echo
echo "Install the plugin via MOS Hub."