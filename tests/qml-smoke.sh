#!/usr/bin/env bash
set -euo pipefail

if (($# != 1)); then
  printf 'usage: %s <klickmeister-binary>\n' "$0" >&2
  exit 2
fi

binary="$1"
if ! output="$(
  QT_QPA_PLATFORM=offscreen \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/klickmeister-smoke-no-bus \
    "$binary" --smoke-test 2>&1
)"; then
  printf 'QML smoke test failed:\n%s\n' "$output" >&2
  exit 1
fi

if grep -Eq 'QQmlApplicationEngine failed|Main\.qml: No such file|Type .* unavailable' <<<"$output"; then
  printf 'QML smoke test failed:\n%s\n' "$output" >&2
  exit 1
fi

printf 'QML smoke test passed: QQmlApplicationEngine created a root window.\n'
