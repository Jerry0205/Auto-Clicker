#!/usr/bin/env bash
set -euo pipefail

if (($# != 1)); then
  printf 'usage: %s <klickmeister-binary>\n' "$0" >&2
  exit 2
fi

binary="$1"
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
desktop_entry="$repo_dir/packaging/io.github.jerry0205.klickmeister.desktop"
if [[ ! -f "$desktop_entry" ]]; then
  printf 'QML smoke test failed: desktop entry missing: %s\n' "$desktop_entry" >&2
  exit 1
fi
desktop_id="$(basename -- "$desktop_entry" .desktop)"
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

if ! grep -Fxq "Qt desktop file name: $desktop_id" <<<"$output"; then
  printf 'QML smoke test failed: Qt desktop file name differs from %s:\n%s\n' "$desktop_id" "$output" >&2
  exit 1
fi

printf 'QML smoke test passed: root window created with desktop ID %s.\n' "$desktop_id"
