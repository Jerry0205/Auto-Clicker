#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"

target_dir="$(cargo metadata --no-deps --format-version 1 | python3 -c 'import json, sys; print(json.load(sys.stdin)["target_directory"])')"

module_dir="$target_dir/cxxqt/qml_modules"
if [[ ! -f "$module_dir/io/github/jerry0205/klickmeister/qmldir" ]]; then
    printf 'Klickmeister-QML-Modul fehlt in %s. Zuerst cargo build --locked ausführen.\n' "$module_dir" >&2
    exit 1
fi
module_dir="$(cd -- "$module_dir" && pwd -P)"

printf '[General]\nbuildDir="%s"\nno-cmake-calls=true\n' "$module_dir" > "$repo_root/.qmlls.ini"
printf 'QML-Sprachserver-Konfiguration erstellt: %s/.qmlls.ini\n' "$repo_root"
