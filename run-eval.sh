#!/bin/bash
# Compiles Eval/main.swift directly alongside Sources/Mailify/*.swift (minus
# MailifyApp.swift, which owns @main — can't coexist with main.swift's
# top-level code in one module) and runs the result. See Eval/main.swift's
# header comment for why this isn't a SwiftPM test/executable target.
set -e

cd "$(dirname "$0")"

SOURCES=$(find Sources/Mailify -name "*.swift" ! -name "MailifyApp.swift")
BIN="$(mktemp -d)/mailify-eval"

swiftc $SOURCES Eval/main.swift -o "$BIN"

set +e
"$BIN"
STATUS=$?
set -e

rm -f "$BIN"
exit $STATUS
