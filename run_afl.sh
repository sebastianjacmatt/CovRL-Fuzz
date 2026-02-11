#!/bin/bash

RUN_ID=$1
PORT=1111
VOCAB_SIZE=32100

PORT=$PORT VOCAB_SIZE=$VOCAB_SIZE ./AFL/afl-fuzz \
  -t 1000 \
  -a 1 \
  -m none \
  -M fuzzer01 \
  -i ../data_store/preprocess/save_dir/testsuites \
  -o ../data_store/out/${RUN_ID} \
  ../data_store/engines/jerryscript/build/bin/jerry @@
