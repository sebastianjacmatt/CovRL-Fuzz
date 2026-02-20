#!/bin/bash

set -euo pipefail
RUN_ID=$1

export TOKENIZERS_PARALLELISM=true

source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate cov-rl

python do_covrl.py \
  --config ./config/sample_config.json \
  --port 1111 \
  --model_path Salesforce/codet5p-220m \
  --sample_method greedy \
  --predict_path ../data_store/out/${RUN_ID}/fuzzer01
