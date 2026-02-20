#!/bin/bash
# CovRL slave server — inference only (no_finetune mode)
# Output here is minimal: just connection messages and predict/decode calls
#
# Usage: bash scripts/run_covrl_slave.sh RUN_ID FUZZER_ID PORT CORE
# Example: bash scripts/run_covrl_slave.sh run01 fuzzer02 1112 1

set -euo pipefail

RUN_ID="${1:?run_id}"
FUZZER="${2:?fuzzer_id}"   # e.g. fuzzer02
PORT="${3:?port}"
CORE="${4:--1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONFIG_PATH="./config/sample_config.json"
MODEL_PATH="Salesforce/codet5p-220m"
OUT_BASE="../data_store/out/${RUN_ID}"
PREDICT_PATH="${OUT_BASE}/${FUZZER}"

mkdir -p "$PREDICT_PATH"

source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate cov-rl

echo "========================================"
echo "  CovRL SLAVE — inference only"
echo "  RUN_ID : $RUN_ID"
echo "  FUZZER : $FUZZER"
echo "  PORT   : $PORT"
echo "  CORE   : $CORE"
echo "  OUTPUT : $PREDICT_PATH"
echo "========================================"

python do_covrl.py \
  --config "$CONFIG_PATH" \
  --port "$PORT" \
  --cpu_core "$CORE" \
  --mode no_finetune \
  --model_path "$MODEL_PATH" \
  --predict_path "$PREDICT_PATH"
