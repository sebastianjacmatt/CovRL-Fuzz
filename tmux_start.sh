#!/bin/bash
# tmux_start.sh
#
# Usage:
#   ./tmux_start.sh RUN_ID NUM_SLAVES [BASE_PORT] [BASE_CORE]
#
# Example (paper setup — 1 master + 3 slaves):
#   ./tmux_start.sh run01 3 1111 0
#
# This creates a tmux session named "covrl" with one window per process:
#   window 0: covrl-master   — CovRL finetune server (training loss visible)
#   window 1: afl-master     — AFL master with full UI (bugs, coverage, paths)
#   window 2: covrl-slave01  — CovRL inference-only server (slave 1)
#   window 3: afl-slave01    — AFL slave 1 (no UI, raw log)
#   ... repeated for each slave
#
# Prerequisites:
#   tmux must be installed: sudo apt install tmux
#
# To attach after running:
#   tmux attach -t covrl
#
# To kill everything:
#   tmux kill-session -t covrl

set -euo pipefail

RUN_ID="${1:?Usage: $0 RUN_ID NUM_SLAVES [BASE_PORT] [BASE_CORE]}"
NUM_SLAVES="${2:?Usage: $0 RUN_ID NUM_SLAVES [BASE_PORT] [BASE_CORE]}"
BASE_PORT="${3:-1111}"
BASE_CORE="${4:-0}"
SESSION="covrl"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Kill existing session if present
tmux kill-session -t "$SESSION" 2>/dev/null || true

# Create session (first window = covrl-master)
tmux new-session -d -s "$SESSION" -x 220 -y 50 -n "covrl-master"

# Window 0: CovRL master (finetune mode — shows training loss)
tmux send-keys -t "$SESSION:covrl-master" \
  "cd '$ROOT_DIR' && bash scripts/run_covrl_master.sh '$RUN_ID' '$BASE_PORT' '$BASE_CORE'" Enter

# Wait for the CovRL master port to be listening before starting AFL master
echo "[+] Waiting for CovRL master to listen on port $BASE_PORT ..."
for i in $(seq 1 180); do
  ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "(:|\\[::\\]:)${BASE_PORT}$" && break
  sleep 1
done
echo "[+] CovRL master ready."

# Window 1: AFL master (full UI)
tmux new-window -t "$SESSION" -n "afl-master"
tmux send-keys -t "$SESSION:afl-master" \
  "cd '$ROOT_DIR' && bash scripts/run_afl_master.sh '$RUN_ID' '$BASE_PORT' '$BASE_CORE'" Enter

# Slave windows
for ((i=1; i<=NUM_SLAVES; i++)); do
  SLAVE_NUM=$(printf "%02d" "$i")
  FUZZER="fuzzer$(printf "%02d" $((i + 1)))"
  PORT=$((BASE_PORT + i))
  CORE=$((BASE_CORE + i))

  # CovRL slave window
  tmux new-window -t "$SESSION" -n "covrl-slave${SLAVE_NUM}"
  tmux send-keys -t "$SESSION:covrl-slave${SLAVE_NUM}" \
    "cd '$ROOT_DIR' && bash scripts/run_covrl_slave.sh '$RUN_ID' '$FUZZER' '$PORT' '$CORE'" Enter

  # Wait for this slave's port before starting its AFL
  echo "[+] Waiting for CovRL slave $SLAVE_NUM on port $PORT ..."
  for j in $(seq 1 180); do
    ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "(:|\\[::\\]:)${PORT}$" && break
    sleep 1
  done
  echo "[+] CovRL slave $SLAVE_NUM ready."

  # AFL slave window
  tmux new-window -t "$SESSION" -n "afl-slave${SLAVE_NUM}"
  tmux send-keys -t "$SESSION:afl-slave${SLAVE_NUM}" \
    "cd '$ROOT_DIR' && bash scripts/run_afl_slave.sh '$RUN_ID' '$FUZZER' '$PORT' '$CORE'" Enter

  sleep 2
done

echo
echo "[+] All processes started in tmux session '$SESSION'"
echo "[+] Attach with:  tmux attach -t $SESSION"
echo "[+] Switch windows with:  Ctrl-b  then window number (0, 1, 2, ...)"
echo "[+] Kill everything with: tmux kill-session -t $SESSION"
echo
tmux attach -t "$SESSION"
