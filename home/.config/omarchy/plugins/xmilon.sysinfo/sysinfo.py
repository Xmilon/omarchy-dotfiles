#!/usr/bin/env python3
"""Data source for the System Info bar widget.

    sysinfo.py stream [seconds]   one JSON line per interval: CPU, temp, RAM, disk, uptime
    sysinfo.py gpu                one JSON line from nvidia-smi (run only while the popup is open)

Everything except `gpu` reads /proc and /sys directly, so a sample costs almost nothing.
"""

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path


def cpu_times():
    with open("/proc/stat") as fh:
        parts = fh.readline().split()[1:]
    values = [int(p) for p in parts]
    idle = values[3] + (values[4] if len(values) > 4 else 0)  # idle + iowait
    return sum(values), idle


def find_cpu_temp_file():
    """k10temp Tctl on AMD, coretemp Package on Intel; hwmon numbers move between boots."""
    for hw in sorted(Path("/sys/class/hwmon").glob("hwmon*")):
        try:
            name = (hw / "name").read_text().strip()
        except OSError:
            continue
        if name in ("k10temp", "coretemp", "zenpower"):
            for label in sorted(hw.glob("temp*_label")):
                text = label.read_text().strip()
                if text in ("Tctl", "Tdie", "Package id 0"):
                    return label.with_name(label.name.replace("_label", "_input"))
            first = hw / "temp1_input"
            if first.exists():
                return first
    return None


def read_temp(path):
    try:
        return round(int(path.read_text()) / 1000)
    except (OSError, ValueError, AttributeError):
        return None


def meminfo():
    info = {}
    with open("/proc/meminfo") as fh:
        for line in fh:
            key, _, rest = line.partition(":")
            info[key] = int(rest.split()[0]) * 1024
    total = info.get("MemTotal", 0)
    used = total - info.get("MemAvailable", 0)
    swap_total = info.get("SwapTotal", 0)
    swap_used = swap_total - info.get("SwapFree", 0)
    return total, used, swap_total, swap_used


def cpu_model():
    try:
        with open("/proc/cpuinfo") as fh:
            for line in fh:
                if line.startswith("model name"):
                    name = line.split(":", 1)[1].strip()
                    return name.replace(" with Radeon Graphics", "")
    except OSError:
        pass
    return ""


def stream(interval):
    temp_file = find_cpu_temp_file()
    model = cpu_model()
    cores = os.cpu_count() or 1
    prev_total, prev_idle = cpu_times()
    while True:
        time.sleep(interval)
        total, idle = cpu_times()
        dt, di = total - prev_total, idle - prev_idle
        prev_total, prev_idle = total, idle
        cpu = round(100 * (dt - di) / dt) if dt > 0 else 0
        mem_total, mem_used, swap_total, swap_used = meminfo()
        disk = shutil.disk_usage("/")
        with open("/proc/uptime") as fh:
            uptime = int(float(fh.read().split()[0]))
        load = os.getloadavg()
        print(json.dumps({
            "cpu": cpu,
            "cpuModel": model,
            "cores": cores,
            "temp": read_temp(temp_file),
            "memUsed": mem_used,
            "memTotal": mem_total,
            "swapUsed": swap_used,
            "swapTotal": swap_total,
            "diskUsed": disk.used,
            "diskTotal": disk.total,
            "uptime": uptime,
            "load": [round(x, 2) for x in load],
        }), flush=True)


def gpu():
    if not shutil.which("nvidia-smi"):
        print(json.dumps({"available": False}))
        return
    query = "name,utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw"
    try:
        out = subprocess.run(
            ["nvidia-smi", f"--query-gpu={query}", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=3,
        ).stdout.strip().splitlines()[0]
        name, util, temp, mem_used, mem_total, power = [p.strip() for p in out.split(",")]

        def num(value):
            try:
                return float(value)
            except ValueError:
                return None

        print(json.dumps({
            "available": True,
            "name": name.replace("NVIDIA GeForce ", ""),
            "util": num(util),
            "temp": num(temp),
            "memUsed": num(mem_used),
            "memTotal": num(mem_total),
            "power": num(power),
        }))
    except (subprocess.SubprocessError, IndexError, ValueError):
        print(json.dumps({"available": False}))


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "gpu":
        gpu()
    else:
        seconds = 2.0
        if len(sys.argv) >= 3:
            try:
                seconds = max(1.0, min(10.0, float(sys.argv[2])))
            except ValueError:
                pass
        try:
            stream(seconds)
        except (BrokenPipeError, KeyboardInterrupt):
            pass
