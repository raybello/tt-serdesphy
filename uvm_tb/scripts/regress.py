#!/usr/bin/env python3
"""Run a UVM regression from a CSV config and emit a self-contained
static HTML report.

Usage:
    regress.py -f uvm_tb/regression/config/nightly.csv

Run from the repo root (or wherever the paths inside the config CSV are
relative to) - see uvm_tb/scripts/regress.md for the CSV formats.
"""

import argparse
import csv
import datetime
import json
import os
import shlex
import subprocess
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPORT_TEMPLATE = os.path.join(SCRIPT_DIR, "report_template.html")
DATA_MARKER = "/*__REGRESSION_DATA__*/"

CONFIG_FIELDS = [
    "BUILD_NAME", "TEST_LIST", "GROUP_NAME", "BUILD_OPTIONS", "RUN_OPTIONS",
    "BUILD_SCRIPT", "RUN_SCRIPT",
]
# Fields that inherit the closest prior non-blank value when left blank.
CARRY_FORWARD_FIELDS = ["BUILD_NAME", "BUILD_SCRIPT", "RUN_SCRIPT"]

LIST_FIELDS = ["NUM_SIMS", "TEST_NAME", "RUN_OPTIONS", "SIMULATION_NAME"]


def normalize_header(name):
    """Strips the <ANGLE_BRACKET> notation regress.md's example CSVs use
    for column headers, e.g. "<BUILD_NAME>" -> "BUILD_NAME"."""
    return name.strip().strip("<>").strip()


def strip_row(row):
    return {k: (v.strip() if isinstance(v, str) else v) for k, v in row.items()
            if k is not None}


def open_csv_reader(f):
    reader = csv.DictReader(f, skipinitialspace=True)
    reader.fieldnames = [normalize_header(fn) for fn in reader.fieldnames]
    return reader


def parse_config(path):
    """Parses the top-level config CSV, applying carry-forward rules for
    BUILD_NAME/BUILD_SCRIPT/RUN_SCRIPT (regress.md step 2)."""
    rows = []
    carried = {field: "" for field in CARRY_FORWARD_FIELDS}
    with open(path, newline="") as f:
        reader = open_csv_reader(f)
        for raw_row in reader:
            row = strip_row(raw_row)
            for field in CARRY_FORWARD_FIELDS:
                if row.get(field):
                    carried[field] = row[field]
                else:
                    row[field] = carried[field]
            rows.append(row)
    return rows


def resolve_list_path(lists_dir, test_list):
    """Resolves a <TEST_LIST> config value to a lists/*.csv path. Tries
    an exact match first, then falls back to stripping a trailing
    "_list" suffix (the shipped nightly.csv references "loopback_list"
    while the file on disk is loopback.csv)."""
    candidates = [f"{test_list}.csv"]
    if test_list.endswith("_list"):
        candidates.append(f"{test_list[:-len('_list')]}.csv")
    for candidate in candidates:
        path = os.path.join(lists_dir, candidate)
        if os.path.exists(path):
            return path
    available = ", ".join(sorted(os.listdir(lists_dir))) if os.path.isdir(lists_dir) else "(no such directory)"
    sys.exit(f"error: could not resolve TEST_LIST '{test_list}' under {lists_dir}\n"
              f"       tried: {', '.join(candidates)}\n"
              f"       available: {available}")


def parse_list(path):
    rows = []
    with open(path, newline="") as f:
        reader = open_csv_reader(f)
        for raw_row in reader:
            row = strip_row(raw_row)
            row["NUM_SIMS"] = int(row["NUM_SIMS"])
            rows.append(row)
    return rows


class Plan:
    """The parsed, ordered set of builds and (build -> group -> test)
    run entries derived from a config CSV, per regress.md step 3."""

    def __init__(self):
        self.builds = {}  # build_name -> {"script":, "options":}
        self.groups = {}  # build_name -> group_name -> [test entries]

    def add_build(self, build_name, script, options):
        if build_name not in self.builds:
            self.builds[build_name] = {"script": script, "options": options}

    def add_test(self, build_name, group_name, test_entry):
        groups = self.groups.setdefault(build_name, {})
        groups.setdefault(group_name, []).append(test_entry)


def build_plan(config_rows, lists_dir):
    plan = Plan()
    for row in config_rows:
        if not row["BUILD_NAME"] or not row["BUILD_SCRIPT"]:
            sys.exit(f"error: config row missing BUILD_NAME/BUILD_SCRIPT: {row}")
        plan.add_build(row["BUILD_NAME"], row["BUILD_SCRIPT"], row["BUILD_OPTIONS"])

        if not row["TEST_LIST"]:
            continue  # build-config-only row, contributes no tests

        list_path = resolve_list_path(lists_dir, row["TEST_LIST"])
        for list_row in parse_list(list_path):
            num_sims = list_row["NUM_SIMS"]
            for i in range(1, num_sims + 1):
                display_name = list_row["SIMULATION_NAME"]
                if num_sims > 1:
                    display_name = f"{display_name} [{i}/{num_sims}]"
                plan.add_test(row["BUILD_NAME"], row["GROUP_NAME"], {
                    "display_name": display_name,
                    "test_name": list_row["TEST_NAME"],
                    "run_script": row["RUN_SCRIPT"],
                    "run_options": f"{list_row['RUN_OPTIONS']} {row['RUN_OPTIONS']}".strip(),
                })
    return plan


def run_step(cmd, cwd):
    """Runs cmd, streaming+capturing combined stdout/stderr, and returns
    (combined_output, returncode, elapsed_seconds)."""
    print("+ " + shlex.join(cmd))
    start = time.monotonic()
    process = subprocess.Popen(
        cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1)
    lines = []
    for line in process.stdout:
        sys.stdout.write(line)
        lines.append(line)
    process.wait()
    elapsed = time.monotonic() - start
    return "".join(lines), process.returncode, elapsed


def write_log(results_dir, *parts, content):
    path = os.path.join(results_dir, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(content)
    return path


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-f", "--config", required=True, help="regression config CSV")
    parser.add_argument("--lists-dir", default=None,
                         help="directory of test list CSVs (default: <config's parent>/../lists)")
    parser.add_argument("--results-dir", default=None,
                         help="directory to store captured logs (default: <config's parent>/../results)")
    parser.add_argument("--out", default=None,
                         help="output report path (default: <config's parent>/../report.html)")
    args = parser.parse_args()

    config_path = args.config
    regression_dir = os.path.dirname(os.path.dirname(os.path.abspath(config_path)))
    lists_dir = args.lists_dir or os.path.join(regression_dir, "lists")
    results_dir = args.results_dir or os.path.join(regression_dir, "results")
    out_path = args.out or os.path.join(regression_dir, "report.html")

    run_id = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_results_dir = os.path.join(results_dir, run_id)

    config_rows = parse_config(config_path)
    plan = build_plan(config_rows, lists_dir)

    report_builds = []
    for build_name, build_info in plan.builds.items():
        cmd = [sys.executable, build_info["script"], "-b", build_name] + shlex.split(build_info["options"])
        output, returncode, elapsed = run_step(cmd, cwd=os.getcwd())
        write_log(run_results_dir, build_name, "build.log", content=output)

        groups = plan.groups.get(build_name, {})
        report_groups = []
        for group_name, tests in groups.items():
            report_tests = []
            for i, test in enumerate(tests, start=1):
                run_cmd = ([sys.executable, test["run_script"], "-t", test["test_name"],
                            "-b", build_name] + shlex.split(test["run_options"]))
                test_output, test_returncode, test_elapsed = run_step(run_cmd, cwd=os.getcwd())
                write_log(run_results_dir, build_name, group_name,
                          f"{test['test_name']}_{i}.log", content=test_output)
                report_tests.append({
                    "test_name": test["display_name"],
                    "run_command": shlex.join(run_cmd),
                    "status": "pass" if test_returncode == 0 else "fail",
                    "run_time_sec": round(test_elapsed, 2),
                    "log": test_output,
                })
            report_groups.append({"group_name": group_name, "tests": report_tests})

        report_builds.append({
            "build_name": build_name,
            "build_command": shlex.join(cmd),
            "status": "pass" if returncode == 0 else "fail",
            "build_time_sec": round(elapsed, 2),
            "log": output,
            "groups": report_groups,
        })

    data = {
        "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "config_file": config_path,
        "builds": report_builds,
    }

    with open(REPORT_TEMPLATE) as f:
        template = f.read()
    payload = json.dumps(data).replace("</script>", "<\\/script>")
    html = template.replace(DATA_MARKER, payload)

    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, "w") as f:
        f.write(html)

    any_fail = any(b["status"] == "fail" for b in report_builds) or any(
        t["status"] == "fail" for b in report_builds for g in b["groups"] for t in g["tests"])
    print(f"\nReport: {out_path}")
    sys.exit(1 if any_fail else 0)


if __name__ == "__main__":
    main()
