#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC="$ROOT_DIR/assets/app-icon.png"
DEST="$ROOT_DIR/Sources/StockMonitorNativeApp/Assets.xcassets/AppIcon.appiconset"

if ! command -v magick >/dev/null 2>&1; then
  echo "error: ImageMagick 'magick' is required to render app icons" >&2
  exit 1
fi

render_icon() {
  pixels="$1"
  name="$2"
  magick "$SRC" -resize "${pixels}x${pixels}!" -strip "png24:$DEST/$name"
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

echo "Rendered app icons from $SRC"
