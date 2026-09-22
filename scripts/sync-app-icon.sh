#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SOURCE="$ROOT_DIR/DesignAssets/AppIcon/location-mark.svg"
ASSET_DIR="$ROOT_DIR/Cichu/Resources/AppIcon.icon/Assets"

test -f "$SOURCE"
mkdir -p "$ASSET_DIR"
cp "$SOURCE" "$ASSET_DIR/LocationMark.svg"

echo "Synced the Cichu location mark into AppIcon.icon."
