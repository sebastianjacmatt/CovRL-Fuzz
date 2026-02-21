#!/usr/bin/env python3
"""Usage: python analyze_run.py <run_id>  (place in ~/CovRL-Fuzz/)"""

import sys, re, subprocess
from pathlib import Path

BASE_DIR  = Path.home() / "data_store/out"
JERRY_BIN = Path.home() / "data_store/engines/jerryscript/build/bin/jerry"
PAPER     = {"error_rate": 58.84, "total_coverage": 23246, "valid_coverage": 20844}

def main():
    if len(sys.argv) < 2:
        sys.exit("Usage: analyze_run.py <run_id>")
    run_dir = BASE_DIR / sys.argv[1]
    fuzzer  = run_dir / "fuzzer01"

    print(f"\n=== CovRL Run {sys.argv[1]} ===\n")

    # ── 1. BITMAP
    bitmap = (fuzzer / "fuzz_bitmap").read_bytes()
    edges  = sum(1 for b in bitmap if b > 0)
    pct    = edges / len(bitmap) * 100
    print(f"[BITMAP]")
    print(f"  size         : {len(bitmap)} (2^{len(bitmap).bit_length()-1})")
    print(f"  edges hit    : {edges}")
    print(f"  coverage     : {pct:.2f}%")
    print(f"  paper total  : {PAPER['total_coverage']}")
    if pct > 70:
        print(f"  !! SATURATED — rebuild Jerry with AFL_MAP_SIZE=131072 (2^17)")

    # ── 2. FUZZER STATS
    stats = {}
    for line in (fuzzer / "fuzzer_stats").read_text().splitlines():
        k, _, v = line.partition(":")
        stats[k.strip()] = v.strip()
    start, last = int(stats["start_time"]), int(stats["last_update"])
    hours = (last - start) / 3600
    print(f"\n[FUZZER STATS]")
    print(f"  runtime       : {hours:.2f}h")
    print(f"  execs_done    : {int(stats['execs_done']):,}")
    print(f"  exec/sec avg  : {int(stats['execs_done'])/(hours*3600):.2f}")
    print(f"  paths_total   : {stats['paths_total']}")
    print(f"  unique_crashes: {stats['unique_crashes']}")
    print(f"  unique_hangs  : {stats['unique_hangs']}")
    print(f"  bitmap_cvg    : {stats['bitmap_cvg']}")

    # ── 3. COVERAGE OVER TIME
    lines = [l for l in (fuzzer/"plot_data").read_text().splitlines()
             if l.strip() and not l.startswith("#")]
    print(f"\n[COVERAGE OVER TIME]  ({len(lines)} datapoints)")
    print(f"  {'time(h)':>8}  {'paths':>7}  {'crashes':>8}  {'exec/s':>7}")
    t0   = int(lines[0].split(",")[0])
    step = max(1, len(lines) // 8)
    for i in range(0, len(lines), step):
        p = lines[i].split(",")
        h = (int(p[0]) - t0) / 3600
        print(f"  {h:8.1f}  {p[3].strip():>7}  {p[7].strip():>8}  {p[10].strip():>7}")

    # ── 4. RL CYCLES
    print(f"\n[RL CYCLES]")
    log_path = run_dir / "covrl.log"
    if log_path.exists():
        text     = log_path.read_text()
        ft_calls = len(re.findall(r"Start fine-tuning", text))
        cycles   = ft_calls // 2
        losses   = [round(float(x), 4) for x in re.findall(r"'train_loss': ([\d.]+)", text)]
        runtimes = [float(x) for x in re.findall(r"'train_runtime': ([\d.]+)", text)]
        print(f"  finetune calls : {ft_calls}  (critic + actor per cycle)")
        print(f"  cycles done    : {cycles}  (paper: ~9 in 24h)")
        if losses:    print(f"  train losses   : {losses}")
        if runtimes:  print(f"  total finetune : {sum(runtimes)/60:.1f} min  |  per call: {[round(r,1) for r in runtimes]}s")
    else:
        print(f"  covrl.log not found")

    # ── 5. ERROR RATE
    print(f"\n[ERROR RATE]")

if __name__ == "__main__":
    main()
