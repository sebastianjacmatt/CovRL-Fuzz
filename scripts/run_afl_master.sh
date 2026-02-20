#!/bin/bash
# AFL master — full interactive UI
# This window shows: exec/s, unique paths, coverage map, crashes, hangs
#
# Usage: bash scripts/run_afl_master.sh RUN_ID PORT CORE

set -euo pipefail

RUN_ID="${1:?run_id}"
PORT="${2:-1111}"
CORE="${3:-0}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VOCAB_SIZE=32100
TESTSUITES_DIR="../data_store/preprocess/save_dir/testsuites"
OUT_BASE="../data_store/out/${RUN_ID}"
INTERPRETER="../data_store/engines/jerryscript/build/bin/jerry"

echo "========================================"
echo "  AFL MASTER — interactive UI"
echo "  RUN_ID : $RUN_ID"
echo "  PORT   : $PORT"
echo "  CORE   : $CORE"
echo "  OUTPUT : $OUT_BASE"
echo "========================================"

if [ "$CORE" != "-1" ]; then
  PIN="taskset -c $CORE"
else
  PIN=""
fi

exec $PIN env PORT="$PORT" VOCAB_SIZE="$VOCAB_SIZE" ./AFL/afl-fuzz \
  -t 1000 \
  -a 1 \
  -m none \
  -M fuzzer01 \
  -i "$TESTSUITES_DIR" \
  -o "$OUT_BASE" \
  "$INTERPRETER" @@
