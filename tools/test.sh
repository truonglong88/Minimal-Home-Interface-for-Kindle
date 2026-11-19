#!/bin/sh
# Run the unit tests, and the layout smoke test when a KOReader checkout is given.
# Usage: tools/test.sh [/path/to/koreader]
set -eu
cd "$(dirname "$0")/.."
# KOReader has no plain "lfs" module on the device (only libs/libkoreader-lfs)
if grep -rn 'require("lfs")' minimalhome.koplugin; then echo 'FAIL: use require("libs/libkoreader-lfs")'; exit 1; fi
luajit spec/model_spec.lua
PWD= luajit spec/font_spec.lua
luajit spec/light_spec.lua
luajit spec/search_spec.lua
if [ "${1:-}" != "" ]; then
    luajit spec/smoke_home.lua "$1"
    luajit spec/smoke_reader.lua "$1"
    luajit spec/library_spec.lua "$1"
    # KOReader's Telex layout loads its data relative to the KOReader folder
    [ -e frontend ] || { ln -s "$1/frontend" frontend; trap 'rm -f frontend' EXIT; }
    luajit spec/smoke_screens.lua "$1"
    luajit spec/menu_hint_spec.lua "$1"
fi
