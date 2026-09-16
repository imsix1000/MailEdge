#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP_ROOT="${SCRIPT_DIR:h}"
BUILD_MODE="${1:-release}"
SIGN_IDENTITY="${MAILEDGE_SIGN_IDENTITY:--}"
ENTITLEMENTS_PATH="${MAILEDGE_ENTITLEMENTS:-$APP_ROOT/Resources/MailEdge.entitlements}"

# SwiftUI 的编译器宏随完整 Xcode 提供。若当前 xcode-select 仍指向
# CommandLineTools，则自动选择已安装的正式版或 Beta 版 Xcode。
if ! xcodebuild -version >/dev/null 2>&1; then
  if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  elif [[ -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
  else
    echo "需要安装完整 Xcode（当前只有 Command Line Tools）。" >&2
    exit 1
  fi
fi

cd "$APP_ROOT"
xcrun swift build -c "$BUILD_MODE"

BIN_PATH="$(xcrun swift build -c "$BUILD_MODE" --show-bin-path)"
BUNDLE_PATH="$APP_ROOT/.build/MailEdge.app"
CONTENTS_PATH="$BUNDLE_PATH/Contents"
ICON_SOURCE="$APP_ROOT/Resources/AppIcon.icns"
RESOURCE_BUNDLE="$BIN_PATH/MailEdgeMac_MailEdgeApp.bundle"

# 每次重建应用包，避免已删除或改名的资源残留在增量产物中。
/bin/rm -rf -- "$BUNDLE_PATH"
mkdir -p "$CONTENTS_PATH/MacOS" "$CONTENTS_PATH/Resources"
cp "$BIN_PATH/MailEdge" "$CONTENTS_PATH/MacOS/MailEdge"
cp "$APP_ROOT/Resources/Info.plist" "$CONTENTS_PATH/Info.plist"

# 可选：为自用构建预置已部署的 Worker/自定义域名。用户仍可在客户端中切换实例。
if [[ -n "${MAILEDGE_SERVER_URL:-}" ]]; then
  case "$MAILEDGE_SERVER_URL" in
    https://*|http://localhost*|http://127.*|http://\[::1\]*) ;;
    *)
      echo "MAILEDGE_SERVER_URL 必须是 HTTPS；HTTP 仅支持本机调试地址。" >&2
      exit 1
      ;;
  esac
  /usr/bin/plutil -replace MailEdgeDefaultServerURL -string "$MAILEDGE_SERVER_URL" "$CONTENTS_PATH/Info.plist"
fi
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  ditto "$RESOURCE_BUNDLE" "$CONTENTS_PATH/Resources/MailEdgeMac_MailEdgeApp.bundle"
fi

# 使用项目内维护的正式 ICNS，避免打包时从网站 favicon 二次缩放。
if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$CONTENTS_PATH/Resources/AppIcon.icns"
else
  echo "找不到应用图标：$ICON_SOURCE" >&2
  exit 1
fi

if command -v codesign >/dev/null 2>&1; then
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - "$BUNDLE_PATH"
  else
    if [[ ! -f "$ENTITLEMENTS_PATH" ]]; then
      echo "找不到签名权限文件：$ENTITLEMENTS_PATH" >&2
      exit 1
    fi
    codesign \
      --force \
      --deep \
      --options runtime \
      --timestamp \
      --entitlements "$ENTITLEMENTS_PATH" \
      --sign "$SIGN_IDENTITY" \
      "$BUNDLE_PATH"
  fi
fi

echo "$BUNDLE_PATH"
