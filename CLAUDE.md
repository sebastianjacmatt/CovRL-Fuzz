# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**CovRL-Fuzz** is a coverage-guided fuzzing tool for JavaScript interpreters that combines LLMs (CodeT5) with Reinforcement Learning (PPO). It was published at ISSTA 2024. The system mutates JS test cases using a fine-tuned CodeT5 model, guided by AFL coverage feedback.

## Commands

### Build

```bash
# Build the modified AFL fuzzer
cd AFL && make

# Build a JS interpreter with AFL instrumentation (example for jerry)
export CC=/path_to_AFL/afl-clang
export CXX=/path_to_AFL/afl-clang++
# Then run the interpreter's build script
```

### Setup & Preprocessing

```bash
pip install -r requirements.txt

# Tokenize test suites (one-time, before first run)
python preprocess_dataset.py --config ./config/sample_config.json
```

### Running

Two terminals required:

```bash
# Terminal 1: CovRL server (mutation + fine-tuning)
python do_covrl.py \
  --config ./config/sample_config.json \
  --port 1111 \
  --model_path Salesforce/codet5p-220m \
  --predict_path path_to_fuzz_dir

# Terminal 2: AFL fuzzer
PORT=1111 VOCAB_SIZE=32100 ./AFL/afl-fuzz \
  -t 1000 -a 1 -m none \
  -i path_to_seed_dir \
  -o path_to_fuzz_dir \
  path_to_interpreter_binary @@
```

### Parallel Fuzzing

```bash
# Starts 1 master + NUM_SLAVES slave fuzzers
./covrl_parallel.sh RUN_ID NUM_SLAVES [BASE_PORT] [BASE_CORE]
# Example: ./covrl_parallel.sh 23 3 1111 0
```

### Tests

```bash
pytest
```

## Architecture

### System Overview

The system runs as two processes communicating over a socket:

1. **AFL fuzzer** (C, in `AFL/`) — token-level coverage-guided fuzzer that sends test cases to the CovRL server for mutation and triggers fine-tuning
2. **CovRL server** (`do_covrl.py`) — Python server managing model inference and periodic PPO fine-tuning

### Socket Protocol

AFL sends one of three messages to the CovRL server on a configurable port (default 1111):
- `"predict"` — send a masked test case, receive mutated tokens
- `"decode"` — decode a token sequence to text
- `"finetune"` — trigger a model fine-tuning cycle

### Python Module: `covrl/`

**`models/`** — ML pipeline:
- `inferencer.py` — Loads CodeT5, applies random masking to JS tokens, generates mutations via `model.generate()`
- `finetuner.py` — Orchestrates the PPO training cycle; calls `ActorTrainer` (updates CodeT5) and `CriticTrainer` (reward predictor)
- `critic.py` — T5-based classifier with 8 output classes mapping to reward scores
- `actor_dataset.py` / `critic_dataset.py` — PyTorch datasets for fine-tuning
- `rewarding.py` — Computes TF-IDF-weighted coverage rewards, maps coverage bitmap to scalar scores

**`utils/`**:
- `config.py` — Reads JSON config into a `NamedTuple`
- `base_utils.py` — Hex/decimal token conversion, reward-to-label mapping, seeding
- `preprocess.py` — Tokenizes JS test suites into token sequences for training
- `map_target_error.py` — Per-engine error type mapping (V8, JSC, Chakra, Jerry)

### Reward System

Rewards are computed from AFL coverage bitmaps using TF-IDF weighting (`alpha` and `beta` in config). Scalar scores are bucketed into 8 labels (–1.0 to 1.0) for critic training. The actor is updated with PPO using the critic's predictions as baseline.

### Configuration (`config/sample_config.json`)

Key fields to set for a new run:
- `testsuites` — paths to JS test corpora
- `save_dir` — output directory
- `train_dataset_path` — output of `preprocess_dataset.py`
- `interpreter_path` — path to instrumented JS binary
- `target_interpreter` — one of `jerry`, `v8`, `jsc`, `chakra`
- `load_path` — HuggingFace model ID or local path (default: `Salesforce/codet5p-220m`)
- `alpha`, `beta` — IDF weight and coverage scaling in reward computation
- `mask_probability` — MLM masking rate (default 0.15)
- `model_max_length` — token sequence length (default 768)

### 3-Step Fuzzing Cycle

1. **Mutation**: Inferencer masks tokens in a test case and uses CodeT5 to fill them in
2. **Execution**: AFL runs the mutated JS file against the target interpreter and captures coverage
3. **Fine-tuning**: When triggered by AFL, FineTuner runs critic then actor training on accumulated (mutation, reward) pairs
