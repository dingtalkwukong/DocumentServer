#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
exec node "$ROOT/web-apps/test/preview-optimizations/real-preview-test.js" "$@"
