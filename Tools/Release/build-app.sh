#!/bin/bash
#
# Builds Pie.app for Apple silicon with the release version stamped into the
# bundle, signs it ad-hoc (arm64 refuses to run unsigned code), and zips it.
#
#   ./Tools/Release/build-app.sh [version]     # default: Tools/Release/version.sh next
#
# Environment:
#   CONFIG=Debug        build configuration (default Release)
#   SYMROOT=/tmp/x      where the .app lands (default /tmp/picode-build)
#   OBJROOT=/tmp/x      intermediates (default /tmp/picode-build-obj)
#   OUT_DIR=dist        where the zip lands (default ./dist)
#   BUILD_NUMBER=n      CFBundleVersion (default: number of commits)
#
# Prints `app=`, `zip=`, `version=` on success — CI reads those lines.
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
[ "$(uname -m)" = "arm64" ] || echo "build-app: not an arm64 host; ARCHS=arm64 still forces Apple silicon" >&2

VERSION=${1:-$(./Tools/Release/version.sh next)}
CONFIG=${CONFIG:-Release}
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

echo "build-app: version $VERSION (build $BUILD_NUMBER), $CONFIG, arm64"
xcodebuild -project PiCode.xcodeproj -target PiCode -configuration "$CONFIG" \
    SYMROOT="$SYMROOT" OBJROOT="$OBJROOT" \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
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

ARCHS_BUILT=$(lipo -archs "$APP/Contents/MacOS/Pie")
case "$ARCHS_BUILT" in
    *arm64*) : ;;
    *) die "built binary is not arm64: $ARCHS_BUILT" ;;
esac

mkdir -p "$OUT_DIR"
ZIP="$OUT_DIR/Pie-$VERSION-arm64.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "version=$VERSION"
echo "app=$APP"
echo "zip=$ZIP"
echo "arch=$ARCHS_BUILT"
