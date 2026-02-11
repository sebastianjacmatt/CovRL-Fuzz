#!/bin/bash

RUN_ID=$1

conda activate cov-rl

python do_covrl.py \
  --config ./config/sample_config.json \
  --port 1111 \
  --model_path Salesforce/codet5p-220m \
  --predict_path ../data_store/out/${RUN_ID}/fuzzer01
