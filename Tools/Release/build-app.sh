#!/bin/bash
#
# Builds Pie.app as a universal binary (Apple silicon + Intel) with the release
# version stamped into the bundle, signs it ad-hoc (arm64 refuses to run
# unsigned code), and packages it as a zip and a DMG.
#
#   ./Tools/Release/build-app.sh [version]     # default: Tools/Release/version.sh next
#
# Environment:
#   CONFIG=Debug        build configuration (default Release)
#   ARCHS="arm64 x86_64"  architectures (default: both — a universal app)
#   SYMROOT=/tmp/x      where the .app lands (default /tmp/picode-build)
#   OBJROOT=/tmp/x      intermediates (default /tmp/picode-build-obj)
#   OUT_DIR=dist        where the zip/DMG land (default ./dist)
#   BUILD_NUMBER=n      CFBundleVersion (default: number of commits)
#
# Prints `app=`, `zip=`, `dmg=`, `arch=`, `version=` — CI reads those lines.
#
# Needs Xcode (Command Line Tools alone are not enough). Without it this exits
# with status 2 and says so instead of dumping an xcodebuild error.
set -euo pipefail

cd "$(dirname "$0")/../.."

die() { echo "build-app: $*" >&2; exit 1; }

if ! command -v xcodebuild >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
    echo "build-app: no usable Xcode (active developer directory: $(xcode-select -p 2>/dev/null || echo unknown))" >&2
    echo "build-app: Command Line Tools are not enough — install Xcode, then: xcode-select -s /Applications/Xcode.app" >&2
    exit 2
fi
command -v hdiutil >/dev/null 2>&1 || die "hdiutil not found — DMGs cannot be built here"

VERSION=${1:-$(./Tools/Release/version.sh next)}
CONFIG=${CONFIG:-Release}
# Universal by default: one binary that runs on arm64 and Intel Macs.
ARCHS=${ARCHS:-"arm64 x86_64"}
# Products are addressed through SYMROOT, not -derivedDataPath: xcodebuild
# refuses -derivedDataPath next to -target (it demands a scheme, and this
# project shares none — its scheme lives in xcuserdata).
SYMROOT=${SYMROOT:-/tmp/picode-build}
OBJROOT=${OBJROOT:-/tmp/picode-build-obj}
OUT_DIR=${OUT_DIR:-$PWD/dist}
BUILD_NUMBER=${BUILD_NUMBER:-$(git rev-list --count HEAD)}

case "$VERSION" in
    *[!0-9.]*|'') die "refusing to stamp a malformed version '$VERSION'" ;;
esac

echo "build-app: version $VERSION (build $BUILD_NUMBER), $CONFIG, ARCHS=$ARCHS"
xcodebuild -project PiCode.xcodeproj -target PiCode -configuration "$CONFIG" \
    SYMROOT="$SYMROOT" OBJROOT="$OBJROOT" \
    ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGNING_ALLOWED=NO \
    VALIDATE_PRODUCT=NO \
    build

APP="$SYMROOT/$CONFIG/Pie.app"
[ -d "$APP" ] || die "expected $APP after the build"

# Ad-hoc signature: enough to run locally, and it makes the bundle verifiable.
codesign --force --sign - "$APP"
codesign --verify --verbose=2 "$APP" || die "codesign verification failed"

PLIST_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
[ "$PLIST_VERSION" = "$VERSION" ] ||
    die "bundle says $PLIST_VERSION, expected $VERSION — the stamp did not reach Info.plist"

# Every requested architecture must really be in the binary — a universal
# build that silently dropped Intel is the one failure users feel too late.
ARCHS_BUILT=$(lipo -archs "$APP/Contents/MacOS/Pie")
for wanted in $ARCHS; do
    case " $ARCHS_BUILT " in
        *" $wanted "*) ;;
        *) die "binary is missing $wanted (it has: $ARCHS_BUILT)" ;;
    esac
done

mkdir -p "$OUT_DIR"
ZIP="$OUT_DIR/Pie-$VERSION-universal.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# A DMG with the usual drag-to-Applications layout: the app plus a symlink.
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/piedmg.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Pie.app"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT_DIR/Pie-$VERSION-universal.dmg"
rm -f "$DMG"
hdiutil create -volname "Pie $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
[ -f "$DMG" ] || die "hdiutil produced no DMG at $DMG"

echo "version=$VERSION"
echo "app=$APP"
echo "zip=$ZIP"
echo "dmg=$DMG"
echo "arch=$ARCHS_BUILT"
