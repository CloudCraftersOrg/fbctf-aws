#!/usr/bin/env python3
"""Turn fleet.yaml + connections.yaml into the upload AWS Transform's migration
assessment ingests.

    python3 generate.py            # writes out/fbctf-assessment.zip (+ the loose files)
    python3 generate.py --check    # validate only, write nothing (CI / pre-commit)

The assessment importer only processes a network-connections file when it is
**zipped together with the servers file** (verified against a live upload
2026-08-27, and in docs/demo-runbook.md). So the deliverable is one ZIP:

    fbctf-assessment.zip
      mpa_servers.csv          MPA "Server" import columns, fixed order  <- required
      network_connections.csv  source/target host + IP + process name   <- required
      ASSESSMENT_INTENT.md     the modernization brief                   <- convenience

Only the two CSVs are a documented input. ASSESSMENT_INTENT.md is bundled so it
travels with the data, but Transform consumes it by you pasting it into the job
chat. If an upload is ever rejected, re-zip with just the two CSVs.

Column names and order in the CSVs are fixed by the MPA template. Do not rename
or reorder them.
"""

from __future__ import annotations

import argparse
import csv
import io
import sys
import zipfile
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:
    sys.exit("PyYAML is required: python3 -m pip install -r inventory/requirements.txt")

HERE = Path(__file__).parent
OUT = HERE / "out"
INTENT = "ASSESSMENT_INTENT.md"
ZIP_NAME = "fbctf-assessment.zip"
VMWARE_ZIP_NAME = "fbctf-vmware-import.zip"

# --vmware: re-tag every host as VMware-sourced so it feeds the VMware migration
# job's "import independently collected discovery data" step. Assessment-import
# hypervisor tags do not invoke the VMware migration path; the dedicated job's
# import step does.
VMWARE_HYPERVISOR = "VMware ESXi 7.0"
VMWARE_DATACENTER = "vcenter-dc-01"
VMWARE_HOST_COLUMNS = ["Server ID", "ESXi Host", "Cluster", "Datastore"]

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
    if not (HERE / INTENT).exists():
        errors.append(f"{INTENT} missing next to generate.py")
    return errors


def _csv_bytes(columns: list[str], rows: list[dict]) -> str:
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=columns)
    w.writeheader()
    w.writerows(rows)
    return buf.getvalue()


def vmware_view(servers: list[dict]) -> tuple[list[dict], list[dict]]:
    tagged = []
    hosts = []
    for i, r in enumerate(servers):
        row = dict(r)
        row["Hypervisor"] = VMWARE_HYPERVISOR
        row["Datacenter ID"] = VMWARE_DATACENTER
        tagged.append(row)
        hosts.append(
            {
                "Server ID": r["Server ID"],
                "ESXi Host": f"esx{(i // 4) + 1:02d}.vcenter.local",
                "Cluster": "prod-cluster-01",
                "Datastore": f"ds-{'ssd' if i % 2 else 'sas'}-0{(i % 3) + 1}",
            }
        )
    return tagged, hosts


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="validate only, write nothing")
    ap.add_argument(
        "--vmware",
        action="store_true",
        help="also emit fbctf-vmware-import.zip for the VMware migration job",
    )
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
    servers_csv = _csv_bytes(SERVER_COLUMNS, servers)
    conns_csv = _csv_bytes(CONNECTION_COLUMNS, connections)
    intent_md = (HERE / INTENT).read_text()

    (OUT / "mpa_servers.csv").write_text(servers_csv)
    (OUT / "network_connections.csv").write_text(conns_csv)

    with zipfile.ZipFile(OUT / ZIP_NAME, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("mpa_servers.csv", servers_csv)
        z.writestr("network_connections.csv", conns_csv)
        z.writestr(INTENT, intent_md)

    print(f"wrote {OUT / ZIP_NAME}")
    print(f"  mpa_servers.csv          {len(servers)} rows")
    print(f"  network_connections.csv  {len(connections)} rows")
    print(f"  {INTENT}")

    if args.vmware:
        vm_servers, vm_hosts = vmware_view(servers)
        vm_servers_csv = _csv_bytes(SERVER_COLUMNS, vm_servers)
        vm_hosts_csv = _csv_bytes(VMWARE_HOST_COLUMNS, vm_hosts)
        with zipfile.ZipFile(OUT / VMWARE_ZIP_NAME, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("mpa_servers.csv", vm_servers_csv)
            z.writestr("network_connections.csv", conns_csv)
            z.writestr("vmware_hosts.csv", vm_hosts_csv)
        print(f"wrote {OUT / VMWARE_ZIP_NAME} (hypervisor -> {VMWARE_HYPERVISOR})")

    print("\nUpload the ZIP to the assessment; paste ASSESSMENT_INTENT.md into the chat.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
