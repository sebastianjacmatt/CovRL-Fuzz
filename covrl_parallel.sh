#!/bin/bash
set -euo pipefail

# covrl_parallel.sh
#
# Purpose
#   Start 1 CovRL server + 1 AFL master (-M) in the foreground (UI visible),
#   and N CovRL servers + AFL slaves (-S) in the background (no UI).
#
# Usage
#   ./covrl_parallel.sh RUN_ID NUM_SLAVES [BASE_PORT] [BASE_CORE]
#
# Example
#   ./covrl_parallel.sh 23 3 1111 0
#   Starts:
#     fuzzer01: port 1111, core 0, CovRL mode=finetune, AFL role=master (-M) with UI
#     fuzzer02: port 1112, core 1, CovRL mode=no_finetune, AFL role=slave (-S) no UI
#     fuzzer03: port 1113, core 2, CovRL mode=no_finetune, AFL role=slave (-S) no UI
#     fuzzer04: port 1114, core 3, CovRL mode=no_finetune, AFL role=slave (-S) no UI
#
# Notes
#   - CovRL must be started before AFL for each fuzzer; we wait for the port to LISTEN.
#   - Slaves use AFL_NO_UI=1 and log to /tmp/afl_fuzzerXX.log
#   - Ctrl+C kills the whole process group spawned by this script.
#   - This script asserts required ports are free and aborts if not.
#   - If you need cleanup, use the built-in "kill" subcommand:
#       ./covrl_parallel.sh kill BASE_PORT NUM_SLAVES
#
# Limitations
#   - Without tmux, you cannot have multiple interactive UIs. Only the master UI is usable.
#     Slaves are intentionally no-UI and log to files.

VOCAB_SIZE=32100
CONFIG_PATH="./config/sample_config.json"
MODEL_PATH="Salesforce/codet5p-220m"
TESTSUITES_DIR="../data_store/preprocess/save_dir/testsuites"
OUT_ROOT="../data_store/out"
INTERPRETER="../data_store/engines/jerryscript/build/bin/jerry"

usage() {
  echo "Usage:"
  echo "  $0 RUN_ID NUM_SLAVES [BASE_PORT] [BASE_CORE]"
  echo "  $0 kill BASE_PORT NUM_SLAVES"
  exit 1
}

if [ "${1:-}" = "kill" ]; then
  BASE_PORT="${2:?base_port}"
  NUM_SLAVES="${3:?num_slaves}"

  for ((i=0; i<=NUM_SLAVES; i++)); do
    p=$((BASE_PORT + i))
    pid="$(ss -ltnp 2>/dev/null | sed -n "s/.*:\\b$p\\b .*pid=\\([0-9]\\+\\).*/\\1/p" | head -n1)"
    if [ -n "${pid:-}" ]; then
      echo "Killing pid=$pid on port $p"
      kill "$pid" || true
    else
      echo "Port $p: no listener"
    fi
  done

  echo "[+] Done."
  exit 0
fi

RUN_ID="${1:?run_id}"
NUM_SLAVES="${2:?num_slaves}"
BASE_PORT="${3:-1111}"
BASE_CORE="${4:-0}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

# Preconditions (no sudo needed)
command -v ss >/dev/null 2>&1 || { echo "Missing 'ss' (iproute2)."; exit 1; }

[ -f "$CONFIG_PATH" ] || { echo "Missing config: $CONFIG_PATH"; exit 1; }
[ -x "./AFL/afl-fuzz" ] || { echo "Missing ./AFL/afl-fuzz"; exit 1; }
[ -x "$INTERPRETER" ] || { echo "Missing interpreter: $INTERPRETER"; exit 1; }
[ -d "$TESTSUITES_DIR" ] || { echo "Missing testsuites dir: $TESTSUITES_DIR"; exit 1; }

OUT_BASE="${OUT_ROOT}/${RUN_ID}"
mkdir -p "$OUT_BASE"

cleanup() {
  echo
  echo "[+] Ctrl+C detected. Killing process group..."
  kill -- -$$ 2>/dev/null || true
  echo "[+] All processes stopped."
  exit 0
}
trap cleanup INT TERM

is_port_listening() {
  local port="$1"
  ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "(:|\\[::\\]:)${port}$"
}

assert_ports_free() {
  local n="$1"
  local base="$2"
  local bad=0

  for ((i=0; i<=n; i++)); do
    local p=$((base + i))
    if is_port_listening "$p"; then
      echo "[-] Port $p is already in use."
      ss -ltnp 2>/dev/null | grep -E "(:|\\[::\\]:)${p}\\b" || true
      bad=1
    fi
  done

  if [ "$bad" -ne 0 ]; then
    echo
    echo "[-] Aborting because one or more ports are in use."
    echo "    Cleanup:"
    echo "      $0 kill $BASE_PORT $NUM_SLAVES"
    exit 1
  fi
}

wait_listen() {
  local port="$1"
  local timeout="${2:-180}"
  local i=0
  while true; do
    if is_port_listening "$port"; then
      return 0
    fi
    i=$((i + 1))
    if [ "$i" -ge "$timeout" ]; then
      echo "[-] Timeout waiting for LISTEN on port $port"
      ss -ltnp 2>/dev/null | grep -E "(:|\\[::\\]:)${port}\\b" || true
      return 1
    fi
    sleep 1
  done
}

pin_prefix() {
  local core="$1"
  if [ "$core" = "-1" ]; then
    echo ""
  else
    echo "taskset -c $core"
  fi
}

start_covrl_bg() {
  local fuzzer="$1"
  local port="$2"
  local core="$3"
  local mode="$4"

  mkdir -p "${OUT_BASE}/${fuzzer}"

  echo "[+] Starting CovRL $fuzzer port=$port core=$core mode=$mode"
  (
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
    conda activate cov-rl
    python do_covrl.py \
      --config "$CONFIG_PATH" \
      --port "$port" \
      --cpu_core "$core" \
      --mode "$mode" \
      --model_path "$MODEL_PATH" \
      --predict_path "${OUT_BASE}/${fuzzer}"
  ) &
  wait_listen "$port" 180
}

start_afl_slave_bg() {
  local fuzzer="$1"
  local port="$2"
  local core="$3"

  echo "[+] Starting AFL slave $fuzzer port=$port core=$core (no UI) -> /tmp/afl_${fuzzer}.log"
  local pin
  pin="$(pin_prefix "$core")"

  # Slaves are -S and no UI; logs to /tmp
  $pin env AFL_NO_UI=1 PORT="$port" VOCAB_SIZE="$VOCAB_SIZE" ./AFL/afl-fuzz \
    -t 1000 \
    -a 1 \
    -m none \
    -S "$fuzzer" \
    -i "$TESTSUITES_DIR" \
    -o "$OUT_BASE" \
    "$INTERPRETER" @@ \
    >/tmp/afl_"$fuzzer".log 2>&1 &
}

start_afl_master_fg() {
  local fuzzer="$1"
  local port="$2"
  local core="$3"

  echo
  echo "[+] Starting AFL master $fuzzer in FOREGROUND (UI should show)"
  echo "[*] Slaves log to /tmp/afl_fuzzerXX.log"
  echo "[*] Ctrl+C stops everything"
  echo

  local pin
  pin="$(pin_prefix "$core")"

  # Master is -M and must be in the foreground to own the TTY UI.
  exec $pin env PORT="$port" VOCAB_SIZE="$VOCAB_SIZE" ./AFL/afl-fuzz \
    -t 1000 \
    -a 1 \
    -m none \
    -M "$fuzzer" \
    -i "$TESTSUITES_DIR" \
    -o "$OUT_BASE" \
    "$INTERPRETER" @@
}

echo
echo "[+] Starting parallel CovRL fuzzing"
echo "    RUN_ID=$RUN_ID"
echo "    NUM_SLAVES=$NUM_SLAVES"
echo "    BASE_PORT=$BASE_PORT"
echo "    BASE_CORE=$BASE_CORE"
echo

assert_ports_free "$NUM_SLAVES" "$BASE_PORT"

# Start CovRL master first, then slaves. Stagger to reduce concurrent heavy loads.
start_covrl_bg "fuzzer01" "$BASE_PORT" "$BASE_CORE" "finetune"
sleep 2

for ((i=1; i<=NUM_SLAVES; i++)); do
  fuzzer=$(printf "fuzzer%02d" $((i + 1)))
  port=$((BASE_PORT + i))
  core=$((BASE_CORE + i))
  start_covrl_bg "$fuzzer" "$port" "$core" "no_finetune"
  sleep 2
done

# Start AFL slaves in background (no UI)
for ((i=1; i<=NUM_SLAVES; i++)); do
  fuzzer=$(printf "fuzzer%02d" $((i + 1)))
  port=$((BASE_PORT + i))
  core=$((BASE_CORE + i))
  start_afl_slave_bg "$fuzzer" "$port" "$core"
done

# Finally start AFL master in foreground (UI)
start_afl_master_fg "fuzzer01" "$BASE_PORT" "$BASE_CORE"