#!/bin/bash
# CovRL master server — finetune mode
# This window shows: model loading, PPO training loss, fine-tune triggers
#
# Usage: bash scripts/run_covrl_master.sh RUN_ID PORT CORE

set -euo pipefail

RUN_ID="${1:?run_id}"
PORT="${2:-1111}"
CORE="${3:-0}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONFIG_PATH="./config/sample_config.json"
MODEL_PATH="Salesforce/codet5p-220m"
OUT_BASE="../data_store/out/${RUN_ID}"
PREDICT_PATH="${OUT_BASE}/fuzzer01"

mkdir -p "$PREDICT_PATH"

source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate cov-rl

echo "========================================"
echo "  CovRL MASTER — finetune mode"
echo "  RUN_ID : $RUN_ID"
echo "  PORT   : $PORT"
echo "  CORE   : $CORE"
echo "  OUTPUT : $PREDICT_PATH"
echo "========================================"

python do_covrl.py \
  --config "$CONFIG_PATH" \
  --port "$PORT" \
  --cpu_core "$CORE" \
  --mode finetune \
  --model_path "$MODEL_PATH" \
  --predict_path "$PREDICT_PATH"
