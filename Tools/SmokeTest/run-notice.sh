#!/bin/bash
#
# Parses the pi-background-tasks terminal notice end to end — snapshot, body
# fallback, transcript row, `entry_appended` event — from literals copied out of
# a real session. No session file and no running `pi` needed.
#
#   ./Tools/SmokeTest/run-notice.sh
set -euo pipefail

cd "$(dirname "$0")/../.."
APP="$PWD/PiCode"
OUT="${TMPDIR:-/tmp}/picode-notice-test"
SDK="$(xcrun --show-sdk-path --sdk macosx)"

mkdir -p "$OUT"
# shellcheck disable=SC2046
SOURCES=$(find "$APP/Models" "$APP/Services" "$APP/Shared" -name '*.swift')

swiftc -Onone -g -sdk "$SDK" -target arm64-apple-macos14.0 -swift-version 5 \
  -o "$OUT/picode-notice" \
  Tools/SmokeTest/BackgroundNoticeTest.swift \
  "$APP/Features/Session/TranscriptBuilder.swift" $SOURCES

exec "$OUT/picode-notice"
