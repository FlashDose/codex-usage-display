#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="0.1.0"
APP_DIR="$PROJECT_DIR/dist/Codex Usage Bar.app"
RELEASE_DIR="$PROJECT_DIR/dist/releases"
ARCHIVE_NAME="CodexUsageBar-v${VERSION}-arm64.zip"
BUNDLE_ID="io.github.flashdose.codex-usage-display"

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "This release script must run on an Apple silicon Mac." >&2
    exit 1
fi

if [[ -e "$RELEASE_DIR/$ARCHIVE_NAME" || -e "$RELEASE_DIR/$ARCHIVE_NAME.sha256" ]]; then
    echo "Release files already exist; move or rename them before rerunning." >&2
    exit 1
fi

"$PROJECT_DIR/build_app.sh"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-display.XXXXXX")"
STAGED_APP="$STAGE_DIR/Codex Usage Bar.app"
ditto --norsrc --noextattr "$APP_DIR" "$STAGED_APP"
codesign --force --sign - --identifier "$BUNDLE_ID" "$STAGED_APP"
codesign --verify --verbose=2 "$STAGED_APP"
mkdir -p "$RELEASE_DIR"
ditto -c -k --norsrc --noextattr --keepParent "$STAGED_APP" "$RELEASE_DIR/$ARCHIVE_NAME"
(
    cd "$RELEASE_DIR"
    shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"
)

echo "Release archive: $RELEASE_DIR/$ARCHIVE_NAME"
echo "SHA-256: $RELEASE_DIR/$ARCHIVE_NAME.sha256"
echo "Temporary signed app retained at: $STAGED_APP"
