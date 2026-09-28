#!/bin/bash
#
# The acceptance gate: everything that proves the tree still builds and the
# Foundation half of the app still behaves, without a model call and without a
# window server. Used by CI before a release, and by the agent before a commit.
#
#   ./Tools/CI/verify.sh
#
# Environment:
#   REQUIRE_PI=1  fail (instead of skip) when `pi` is not installed; CI sets this.
set -euo pipefail

cd "$(dirname "$0")/../.."
APP="$PWD/PiCode"

echo "== typecheck =="
# SwiftUI's macros (@State and friends) expand through a plugin that ships
# with the Xcode toolchain only. Under bare Command Line Tools the whole-app
# type-check fails for a reason that has nothing to do with the code, so the
# gate degrades to the Foundation half — which is everything the harnesses
# below compile — and CI (full Xcode) still checks every source file.
if xcodebuild -version >/dev/null 2>&1; then
    TARGET_ALL=1
    echo "all sources (Xcode toolchain)"
else
    TARGET_ALL=0
    echo "Foundation half only — no Xcode: SwiftUIMacros is unavailable"
    echo "(Features/ and App/ are type-checked by CI, which always has Xcode)"
fi

SDK="$(xcrun --show-sdk-path --sdk macosx)"
if [ "$TARGET_ALL" = "1" ]; then
    # shellcheck disable=SC2046
    swiftc -typecheck -sdk "$SDK" -target arm64-apple-macos14.0 -swift-version 5 \
        $(find "$APP" -name '*.swift')
else
    # shellcheck disable=SC2046
    swiftc -typecheck -sdk "$SDK" -target arm64-apple-macos14.0 -swift-version 5 \
        $(find "$APP/Models" "$APP/Services" "$APP/Shared" -name '*.swift')
fi
echo "ok"

echo "== JSON scanner vs Foundation =="
./Tools/SmokeTest/run-json.sh

echo "== background-task notice (parse, row, event) =="
./Tools/SmokeTest/run-notice.sh

if command -v pi >/dev/null 2>&1 || [ -x "$HOME/.pi/agent/bin/pi" ]; then
    echo "== RPC layer against a real pi =="
    ./Tools/SmokeTest/run.sh

    echo "== Pi path resolution against a real pi =="
    ./Tools/SmokeTest/run-paths.sh
else
    if [ "${REQUIRE_PI:-0}" = "1" ]; then
        echo "verify.sh: pi is required here but was not found" >&2
        exit 1
    fi
    echo "verify.sh: pi not installed — skipping the RPC and path harnesses"
fi

echo "verify: all checks passed"
