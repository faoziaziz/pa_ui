import re
import json

PCB = "../pa_usrp_ui.kicad_pcb"

RF_NETS = {
    "Net-(U1-RFIN)",
    "Net-(F1-B3DL)",
    "Net-(F1-B3UL)",
    "Net-(F1-ANT)",
}

lines = open(PCB, encoding="utf-8").read().splitlines()

segments = []
current = None

for line in lines:
    s = line.strip()

    # Start of a PCB segment
    if s == "(segment":
        current = {}
        continue

    if current is None:
        continue

    # Start coordinate
    m = re.match(
        r'\(start\s+([-\d.]+)\s+([-\d.]+)\)',
        s
    )
    if m:
        current["start"] = [
            float(m.group(1)),
            float(m.group(2))
        ]
        continue

    # End coordinate
    m = re.match(
        r'\(end\s+([-\d.]+)\s+([-\d.]+)\)',
        s
    )
    if m:
        current["end"] = [
            float(m.group(1)),
            float(m.group(2))
        ]
        continue

    # Trace width
    m = re.match(
        r'\(width\s+([-\d.]+)\)',
        s
    )
    if m:
        current["width"] = float(m.group(1))
        continue

    # Copper layer
    m = re.match(
        r'\(layer\s+"([^"]+)"\)',
        s
    )
    if m:
        current["layer"] = m.group(1)
        continue

    # KiCad 10:
    # (net "Net-(U1-RFIN)")
    #
    # Also accept older:
    # (net 12 "Net-(U1-RFIN)")
    m = re.match(
        r'\(net(?:\s+\d+)?\s+"([^"]+)"\)',
        s
    )
    if m:
        current["net"] = m.group(1)
        continue

    # End of segment
    if s == ")":
        if current.get("net") in RF_NETS:

            required = [
                "start",
                "end",
                "width",
                "layer",
                "net"
            ]

            if all(k in current for k in required):
                segments.append(current)

        current = None


print()
print("=" * 90)
print("RF SEGMENTS EXTRACTED FROM KiCad")
print("=" * 90)

for i, seg in enumerate(segments, 1):
    x1, y1 = seg["start"]
    x2, y2 = seg["end"]

    print(
        f"{i:3d}  "
        f"{seg['net']:24s} "
        f"{seg['layer']:5s} "
        f"({x1:9.4f}, {y1:9.4f}) -> "
        f"({x2:9.4f}, {y2:9.4f}) "
        f"width={seg['width']:.4f} mm"
    )

print()
print("=" * 90)
print(f"RF segments found: {len(segments)}")
print("=" * 90)

# Count per net
print()
print("SEGMENTS PER NET:")

for net in sorted(RF_NETS):
    count = sum(
        1 for s in segments
        if s["net"] == net
    )
    print(f"  {net:24s}: {count}")

# Save JSON
data = {
    "source": PCB,
    "rf_nets": sorted(RF_NETS),
    "segments": segments
}

with open("rf_segments.json", "w") as f:
    json.dump(data, f, indent=2)

print()
print("Saved: rf_segments.json")
