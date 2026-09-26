#!/usr/bin/env python3
"""Print the UDID of the newest available iPhone simulator (no jq needed).

Reads `xcrun simctl list devices available -j` from stdin or runs it itself.
Newest = highest iOS runtime version, then highest iPhone model number, with
plain (non-Pro/Max/Plus/SE) models preferred on ties so tests run on the
smallest fast device. Exit 1 if none is available.
"""
import json
import re
import subprocess
import sys


def main() -> int:
    if sys.stdin.isatty():
        raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"])
    else:
        raw = sys.stdin.read() or subprocess.check_output(
            ["xcrun", "simctl", "list", "devices", "available", "-j"])
    devices = json.loads(raw)["devices"]

    candidates = []
    for runtime, devs in devices.items():
        if "iOS" not in runtime:
            continue
        m = re.search(r"iOS[-.](\d+)[-.](\d+)", runtime)
        version = (int(m.group(1)), int(m.group(2))) if m else (0, 0)
        for dev in devs:
            name = dev.get("name", "")
            if not dev.get("isAvailable", False) or not name.startswith("iPhone"):
                continue
            gen = re.search(r"iPhone (\d+)", name)
            model = int(gen.group(1)) if gen else 0
            plain = 1 if re.fullmatch(r"iPhone \d+", name) else 0
            candidates.append((version, model, plain, name, dev["udid"]))

    if not candidates:
        print("no available iPhone simulator found", file=sys.stderr)
        return 1
    candidates.sort()
    version, model, plain, name, udid = candidates[-1]
    print(f"picked {name} (iOS {version[0]}.{version[1]}) {udid}", file=sys.stderr)
    print(udid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
