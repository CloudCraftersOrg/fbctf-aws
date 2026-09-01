#!/usr/bin/env python3
"""Turn fleet.yaml + connections.yaml into the two CSVs AWS Transform's
Migration Portfolio Assessment ingests.

    python3 generate.py            # writes out/mpa_servers.csv + out/network_connections.csv
    python3 generate.py --check    # validate only, write nothing (used by CI/pre-commit)

Column names and order are fixed by the MPA import template and were verified
against a live upload on 2026-08-27 (see docs/decisions/004-demo-scope-expansion.md).
Do not rename or reorder them.
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:
    sys.exit("PyYAML is required: python3 -m pip install -r inventory/requirements.txt")

HERE = Path(__file__).parent
OUT = HERE / "out"

SERVER_COLUMNS = [
    "Server ID",
    "Hostname",
    "Physical/Virtual",
    "OS Name",
    "OS Version",
    "CPU-Number of Processors",
    "CPU-Cores per Processor",
    "CPU-Number of Threads per CPU-Core",
    "CPU-Peak Utilization",
    "CPU-Average Utilization",
    "RAM-Total Size",
    "RAM-Peak Utilization",
    "RAM-Average Utilization",
    "Storage-Total Disk Size",
    "Storage-Utilization",
    "Environment Type",
    "Hypervisor",
    "Datacenter ID",
]

CONNECTION_COLUMNS = [
    "Source Server ID",
    "Source Server IP Address",
    "Target Server ID",
    "Target Server IP Address",
    "Source Process Name",
    "Target Process Name",
]


def load(name: str) -> dict:
    with open(HERE / name) as fh:
        return yaml.safe_load(fh)


def server_rows(fleet: dict) -> list[dict]:
    defaults = fleet.get("defaults", {})
    rows = []
    for s in fleet["servers"]:
        cpu, ram, storage, os_ = s["cpu"], s["ram"], s["storage"], s["os"]
        rows.append(
            {
                "Server ID": s["id"],
                "Hostname": s["hostname"],
                "Physical/Virtual": "Virtual",
                "OS Name": os_["name"],
                "OS Version": os_["version"],
                "CPU-Number of Processors": cpu["sockets"],
                "CPU-Cores per Processor": cpu["cores_per_socket"],
                "CPU-Number of Threads per CPU-Core": s.get(
                    "threads_per_core", defaults.get("threads_per_core", 1)
                ),
                "CPU-Peak Utilization": cpu["peak"],
                "CPU-Average Utilization": cpu["avg"],
                "RAM-Total Size": ram["total"],
                "RAM-Peak Utilization": ram["peak"],
                "RAM-Average Utilization": ram["avg"],
                "Storage-Total Disk Size": storage["total"],
                "Storage-Utilization": storage["used_pct"],
                "Environment Type": s.get("environment", defaults["environment"]),
                "Hypervisor": s.get("hypervisor", defaults["hypervisor"]),
                "Datacenter ID": s.get("datacenter", defaults["datacenter"]),
            }
        )
    return rows


def connection_rows(fleet: dict, conns: dict) -> list[dict]:
    ip = {s["id"]: s["ip"] for s in fleet["servers"]}
    rows = []
    for c in conns["connections"]:
        for end in ("from", "to"):
            if c[end] not in ip:
                raise KeyError(f"connections.yaml references unknown server id: {c[end]}")
        rows.append(
            {
                "Source Server ID": c["from"],
                "Source Server IP Address": ip[c["from"]],
                "Target Server ID": c["to"],
                "Target Server IP Address": ip[c["to"]],
                "Source Process Name": c["from_proc"],
                "Target Process Name": c["to_proc"],
            }
        )
    return rows


def check(fleet: dict, servers: list[dict], conns_rows: list[dict]) -> list[str]:
    errors = []
    seen = set()
    for s in fleet["servers"]:
        if s["id"] in seen:
            errors.append(f"duplicate server id: {s['id']}")
        seen.add(s["id"])
    reachable = {r["Source Server ID"] for r in conns_rows} | {
        r["Target Server ID"] for r in conns_rows
    }
    for s in fleet["servers"]:
        if s["id"] not in reachable:
            errors.append(f"{s['id']} has no dependency edge - it will land in its own wave")
    for r in servers:
        if not 0 <= float(r["Storage-Utilization"]) <= 100:
            errors.append(f"{r['Server ID']}: Storage-Utilization out of range")
        if not 0 <= float(r["CPU-Peak Utilization"]) <= 100:
            errors.append(f"{r['Server ID']}: CPU-Peak Utilization out of range")
    return errors


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="validate only, write nothing")
    args = ap.parse_args()

    fleet = load("fleet.yaml")
    conns = load("connections.yaml")
    servers = server_rows(fleet)
    connections = connection_rows(fleet, conns)

    errors = check(fleet, servers, connections)
    if errors:
        print("\n".join(f"  - {e}" for e in errors), file=sys.stderr)
        return 1

    if args.check:
        print(f"ok: {len(servers)} servers, {len(connections)} connections")
        return 0

    OUT.mkdir(exist_ok=True)
    _write(OUT / "mpa_servers.csv", SERVER_COLUMNS, servers)
    _write(OUT / "network_connections.csv", CONNECTION_COLUMNS, connections)
    print(f"wrote {OUT}/mpa_servers.csv ({len(servers)} rows)")
    print(f"wrote {OUT}/network_connections.csv ({len(connections)} rows)")
    return 0


def _write(path: Path, columns: list[str], rows: list[dict]) -> None:
    with open(path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=columns)
        w.writeheader()
        w.writerows(rows)


if __name__ == "__main__":
    raise SystemExit(main())
