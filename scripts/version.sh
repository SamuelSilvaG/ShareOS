#!/bin/sh
# Prints the ShareOS version: git tag if present, else 0.0-<date>-<short hash>.
cd "$(dirname "$0")/.." || exit 1
if v=$(git describe --tags --exact-match 2>/dev/null); then
	echo "${v#v}"
elif h=$(git rev-parse --short HEAD 2>/dev/null); then
	echo "0.0-$(date -u +%Y%m%d)-$h"
else
	echo "0.0-$(date -u +%Y%m%d)"
fi
