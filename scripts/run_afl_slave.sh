#!/bin/bash
# AFL slave — no UI, raw stdout log
# Output here is minimal: AFL startup messages, then silent
# Check /tmp/afl_FUZZER.log if you need to debug a specific slave
#
# Usage: bash scripts/run_afl_slave.sh RUN_ID FUZZER_ID PORT CORE
# Example: bash scripts/run_afl_slave.sh run01 fuzzer02 1112 1

set -euo pipefail

RUN_ID="${1:?run_id}"
FUZZER="${2:?fuzzer_id}"   # e.g. fuzzer02
PORT="${3:?port}"
CORE="${4:--1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VOCAB_SIZE=32100
TESTSUITES_DIR="../data_store/preprocess/save_dir/testsuites"
OUT_BASE="../data_store/out/${RUN_ID}"
INTERPRETER="../data_store/engines/jerryscript/build/bin/jerry"
LOGFILE="/tmp/afl_${FUZZER}.log"

echo "========================================"
echo "  AFL SLAVE — no UI"
echo "  RUN_ID : $RUN_ID"
echo "  FUZZER : $FUZZER"
echo "  PORT   : $PORT"
echo "  CORE   : $CORE"
echo "  LOGFILE: $LOGFILE"
echo "========================================"
echo "  AFL output is shown below."
echo "  Full log also written to $LOGFILE"
echo "========================================"

if [ "$CORE" != "-1" ]; then
  PIN="taskset -c $CORE"
else
  PIN=""
fi

$PIN env AFL_NO_UI=1 PORT="$PORT" VOCAB_SIZE="$VOCAB_SIZE" ./AFL/afl-fuzz \
  -t 1000 \
  -a 1 \
  -m none \
  -S "$FUZZER" \
  -i "$TESTSUITES_DIR" \
  -o "$OUT_BASE" \
  "$INTERPRETER" @@ 2>&1 | tee "$LOGFILE"
