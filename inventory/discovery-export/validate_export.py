#!/usr/bin/env python3
"""Validate the fbctf discovery export before uploading to AWS Transform."""
import csv, json, sys, io, zipfile
from pathlib import Path

D = Path("/Users/Diego_Imbus/aws-personal/workdir/fbctf-discovery-2026-08-27")
errors, warnings, notes = [], [], []

# --- expected discovery-tool CSV schemas (verbatim from AWS docs) ---
SCHEMAS = {
 "server_inventory.csv": ["server_id","server_name","resource_type","power_state","os_type","os_name","os_version","primary_hostname","primary_ip_address","netmask","total_num_network_cards","total_num_disks","cpu_count","total_memory_gb","server_uuid","smbios_uuid","cluster_name","hypervisor_object_id","hypervisor_type","hypervisor_version","hypervisor_hostname","hypervisor_host_id","hypervisor_id","disk_read_iops_avg","disk_read_iops_peak","disk_write_iops_avg","disk_write_iops_peak","disk_total_iops_avg","disk_total_iops_peak","disk_read_throughput_avg_mbps","disk_read_throughput_peak_mbps","disk_write_throughput_avg_mbps","disk_write_throughput_peak_mbps","disk_total_throughput_avg_mbps","disk_total_throughput_peak_mbps"],
 "server_performance_metrics.csv": ["server_id","data_source","cpu_utilization_avg_pct","cpu_utilization_peak_pct","cpu_count","memory_total_gb","memory_utilization_avg_pct","memory_utilization_peak_pct","network_in_avg_mbps","network_in_peak_mbps","network_out_avg_mbps","network_out_peak_mbps","network_total_avg_mbps","network_total_peak_mbps"],
 "server_storage_performance.csv": ["server_id","data_source","disk_volume_id","disk_mount_point","file_system","disk_total_gb","disk_used_gb","disk_free_gb","disk_read_iops_avg","disk_read_iops_peak","disk_write_iops_avg","disk_write_iops_peak","disk_total_iops_avg","disk_total_iops_peak","disk_read_throughput_avg_mbps","disk_read_throughput_peak_mbps","disk_write_throughput_avg_mbps","disk_write_throughput_peak_mbps","disk_total_throughput_avg_mbps","disk_total_throughput_peak_mbps"],
 "storage_config.csv": ["server_id","disk_controller_id","vmdk_vhd_file_name","disk_volume_type","disk_provisioned_gb","disk_device_type","disk_interface_type","disk_protocol"],
 "network_interfaces.csv": ["server_id","interface_name","interface_index","mac_address","adapter_type","virtual_network_name","virtual_network_id","virtual_switch","ipv4_address","ipv4_subnet_mask","ipv4_gateway","ipv6_address","ipv6_prefix_length","ipv6_gateway","dns_servers","dhcp_enabled","interface_status","vlan_id","is_primary"],
 "process_metrics.csv": ["server_id","process_name","process_id","process_command_line","process_user"],
}
SERVER_IDS = {"i-0422e26203cb709b2", "i-0d6b944117ba6302b"}

def load_csv(name):
    p = D / name
    raw = p.read_bytes()
    if raw[:3] == b"\xef\xbb\xbf":
        errors.append(f"{name}: has a UTF-8 BOM (Transform/MPA importers choke on this)")
        raw = raw[3:]
    try:
        raw.decode("utf-8")
    except UnicodeDecodeError as e:
        errors.append(f"{name}: not valid UTF-8 ({e})")
    rows = list(csv.reader(io.StringIO(raw.decode("utf-8", "replace"))))
    return rows

def check_csv(name, id_col=0, expect_ids=True):
    rows = load_csv(name)
    if not rows:
        errors.append(f"{name}: empty"); return
    header = rows[0]
    ncol = len(header)
    for i, r in enumerate(rows[1:], start=2):
        if len(r) != ncol:
            errors.append(f"{name}:{i}: {len(r)} fields, header has {ncol} -> {r}")
    # schema check
    if name in SCHEMAS:
        exp = SCHEMAS[name]
        missing = [c for c in exp if c not in header]
        extra = [c for c in header if c not in exp]
        if missing:
            errors.append(f"{name}: missing documented columns: {missing}")
        if header[:len(exp)] != exp:
            if set(exp).issubset(set(header)):
                warnings.append(f"{name}: documented columns present but not in canonical order (importer maps by name, low risk)")
            else:
                errors.append(f"{name}: header diverges from documented schema\n   expected {exp}\n   got      {header}")
        if extra:
            notes.append(f"{name}: {len(extra)} extra column(s) beyond the tool schema: {extra} (importer ignores unmapped columns)")
    # id consistency
    if expect_ids and id_col < ncol:
        ids = {r[id_col] for r in rows[1:] if r and r[id_col]}
        bad = ids - SERVER_IDS
        if bad:
            warnings.append(f"{name}: rows reference non-server ids in col {id_col}: {bad}")
    return rows

print("=" * 64)
print("DISCOVERY-TOOL SCHEMA CSVs")
print("=" * 64)
inv = check_csv("server_inventory.csv")
perf = check_csv("server_performance_metrics.csv")
check_csv("server_storage_performance.csv")
check_csv("storage_config.csv")
check_csv("network_interfaces.csv")
check_csv("process_metrics.csv")

print("\n" + "=" * 64)
print("MPA FILES")
print("=" * 64)
mpa = check_csv("mpa_exports/servers.csv", id_col=0)
conn = load_csv("mpa_exports/connections.csv")
ch = conn[0]
for i, r in enumerate(conn[1:], start=2):
    if len(r) != len(ch):
        errors.append(f"mpa_exports/connections.csv:{i}: {len(r)} fields vs {len(ch)}")
# connections: at least the source must be a known server
src_idx = ch.index("Source Server Id") if "Source Server Id" in ch else 0
for i, r in enumerate(conn[1:], start=2):
    if r and r[src_idx] and r[src_idx] not in SERVER_IDS:
        warnings.append(f"connections.csv:{i}: source '{r[src_idx]}' not in server inventory")
notes.append("connections.csv: RDS/memcached targets have blank Destination Server Id by design "
             "(managed services are not discoverable OS instances); MPA will treat them as external and "
             "likely drop those edges from wave planning - expected.")

print("\n" + "=" * 64)
print("CROSS-FILE CONSISTENCY")
print("=" * 64)
# memory / cpu must agree across inventory + performance
def col(rows, name):
    h = rows[0]; return {r[0]: r[h.index(name)] for r in rows[1:]}
inv_mem = col(inv, "total_memory_gb"); perf_mem = col(perf, "memory_total_gb")
inv_cpu = col(inv, "cpu_count"); perf_cpu = col(perf, "cpu_count")
for sid in SERVER_IDS:
    if inv_mem.get(sid) != perf_mem.get(sid):
        errors.append(f"{sid}: memory mismatch inventory={inv_mem.get(sid)} perf={perf_mem.get(sid)}")
    if inv_cpu.get(sid) != perf_cpu.get(sid):
        errors.append(f"{sid}: cpu mismatch inventory={inv_cpu.get(sid)} perf={perf_cpu.get(sid)}")
# every server present in every per-server file
for name, rows in [("server_inventory.csv", inv), ("server_performance_metrics.csv", perf),
                   ("mpa_exports/servers.csv", mpa)]:
    present = {r[0] for r in rows[1:]}
    if present != SERVER_IDS:
        errors.append(f"{name}: server set {present} != {SERVER_IDS}")
print(f"  servers: {sorted(SERVER_IDS)}")
print(f"  memory (GiB): {inv_mem}")
print(f"  cpu: {inv_cpu}")

# value sanity
for sid in SERVER_IDS:
    h = perf[0]
    row = [r for r in perf[1:] if r[0] == sid][0]
    cpu_pk = float(row[h.index("cpu_utilization_peak_pct")])
    mem_pk = float(row[h.index("memory_utilization_peak_pct")])
    if not (0 <= cpu_pk <= 100): errors.append(f"{sid}: cpu peak {cpu_pk} out of range")
    if not (0 <= mem_pk <= 100): errors.append(f"{sid}: mem peak {mem_pk} out of range")

print("\n" + "=" * 64)
print("JSON")
print("=" * 64)
for j in ["managed_dependencies.json", "infrastructure_topology.json"]:
    try:
        json.loads((D / j).read_text()); print(f"  {j}: valid")
    except Exception as e:
        errors.append(f"{j}: {e}")

print("\n" + "=" * 64)
print("RESULT")
print("=" * 64)
for n in notes: print(f"  NOTE  {n}")
for w in warnings: print(f"  WARN  {w}")
for e in errors: print(f"  ERROR {e}")
print()
print(f"  {len(errors)} errors, {len(warnings)} warnings, {len(notes)} notes")
sys.exit(1 if errors else 0)
