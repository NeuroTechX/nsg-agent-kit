#!/usr/bin/env python3
"""Print the comparison from the REVE motor imagery starter's NSG summary."""

import argparse
import json
from pathlib import Path


def report(summary, seed):
    if summary.get("pip_ok") is False:
        raise ValueError("The job could not install its dependencies. Check pip_err and the job log.")
    if summary.get("cuda") is not True or not summary.get("gpu"):
        raise ValueError("No CUDA device recorded. Check the NSG tool and the job log.")
    if summary.get("partial") or summary.get("shard_error"):
        raise ValueError("The job returned an incomplete summary. Check the job log.")

    rows = [
        row for row in summary.get("rows", [])
        if row.get("dataset") == "braindecode/bcic2a" and row.get("backbone") == "REVE"
        and row.get("head") == "linear" and row.get("training") == "sgd" and row.get("seed") == seed
        and row.get("finetuning") in ("frozen", "lora")
    ]
    if len(rows) != 2 or {row["finetuning"] for row in rows} != {"frozen", "lora"}:
        raise ValueError(f"Expected one frozen and one LoRA row for REVE on BCI IV 2a, seed {seed}.")

    lines = [
        f"Device: {summary['gpu']} | PyTorch: {summary.get('torch', 'unknown')}",
        f"REVE on BCI Competition IV 2a, seed {seed}, linear head",
        "Method   Balanced acc.    Cell time    Peak GPU",
    ]
    for row in sorted(rows, key=lambda result: result["finetuning"]):
        method = row["finetuning"]
        if row.get("status") != "completed":
            raise ValueError(f"{method} failed. {row.get('exception') or 'Check the job log.'}")
        accuracy = row.get("test_balanced_accuracy")
        seconds = row.get("cell_wall_seconds")
        gpu_gib = row.get("cell_peak_gib")
        if any(value is None for value in (accuracy, seconds, gpu_gib)):
            raise ValueError(f"{method} result is missing a required metric.")
        lines.append(f"{method:<8} {accuracy:>13.2%} {seconds:>9.1f} s {gpu_gib:>9.2f} GiB")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("summary", type=Path)
    parser.add_argument("--seed", type=int, default=0)
    args = parser.parse_args()
    try:
        print(report(json.loads(args.summary.read_text(encoding="utf-8")), args.seed))
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
