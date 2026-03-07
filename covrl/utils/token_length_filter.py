"""
Filter a testsuite directory by token length before preprocessing.

Copies files whose token count is <= model_max_length into an output
directory. Run as a script or import filter_by_token_length directly.

Usage:
    python -m covrl.utils.token_length_filter \
        --config config/sample_config.json \
        --input  path/to/dataset/testsuites \
        --output path/to/filtered/testsuites
"""

import argparse
import os
import shutil
import sys

# Ensure the project root (two levels up from this file) is on sys.path so
# that `covrl` is importable when the script is run directly.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from tqdm import tqdm
from transformers import AutoTokenizer

from covrl.utils.base_utils import load_testsuites
from covrl.utils.config import Config


def filter_by_token_length(tokenizer_name, input_paths, output_dir, model_max_length):
    """
    Scan every file in input_paths, keep those with <= model_max_length tokens,
    and copy them flat into output_dir.

    Returns (kept, skipped) counts.
    """
    tokenizer = AutoTokenizer.from_pretrained(tokenizer_name)
    testsuites = load_testsuites(input_paths)

    os.makedirs(output_dir, exist_ok=True)

    kept = 0
    skipped = 0

    for filepath in tqdm(testsuites, desc="Filtering"):
        try:
            with open(filepath, "r", encoding="utf-8", errors="replace") as f:
                text = f.read()
        except Exception as e:
            print(f"Warning: could not read {filepath}: {e}", file=sys.stderr)
            skipped += 1
            continue

        tokens = tokenizer.encode(text)
        if len(tokens) > model_max_length:
            skipped += 1
            continue

        dest = os.path.join(output_dir, os.path.basename(filepath))
        shutil.copy2(filepath, dest)
        kept += 1

    return kept, skipped


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Filter JS testsuites by tokenizer token length."
    )
    parser.add_argument("--config", required=True, help="Path to sample_config.json")
    parser.add_argument("--input",  required=True, nargs="+",
                        help="Input directory (or directories) containing .js files")
    parser.add_argument("--output", required=True,
                        help="Output directory for files that pass the filter")
    args = parser.parse_args()

    conf = Config.from_json(args.config)
    max_len = conf.model_max_length
    print(f"Tokenizer : {conf.load_path}")
    print(f"Max tokens: {max_len}")

    kept, skipped = filter_by_token_length(
        tokenizer_name=conf.load_path,
        input_paths=args.input,
        output_dir=args.output,
        model_max_length=max_len,
    )

    total = kept + skipped
    print(f"\nDone. {kept}/{total} files kept, {skipped} skipped (>{max_len} tokens).")
    print(f"Filtered dataset written to: {args.output}")
