#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${THEOS:-}" ]]; then
    echo "Set THEOS to your RootHide Theos installation first." >&2
    exit 1
fi

make clean
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide ARCHS=arm64e "$@"
