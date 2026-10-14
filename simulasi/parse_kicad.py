import re
import json

PCB = "../pa_usrp_ui.kicad_pcb"

text = open(PCB, encoding="utf-8").read()


# ============================================================
# Generic KiCad block extractor
# ============================================================
def extract_block(text, name):
    """
    Extract one KiCad S-expression block such as:
        (polygon ...)
        (pts ...)
    while correctly handling nested parentheses.
    """
    token = "(" + name
    start = text.find(token)

    if start < 0:
        return None

    depth = 0

    for i in range(start, len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1

            if depth == 0:
                return text[start:i+1]

    return None
    
    
def blocks(keyword):
    out = []
    pos = 0
    token = "(" + keyword

    while True:
        start = text.find(token, pos)

        if start < 0:
            break

        depth = 0
        end = None

        for i in range(start, len(text)):
            if text[i] == "(":
                depth += 1
            elif text[i] == ")":
                depth -= 1

                if depth == 0:
                    end = i + 1
                    break

        if end is None:
            break

        out.append(text[start:end])
        pos = end

    return out


def number(pattern, block, default=None):
    m = re.search(pattern, block)
    return float(m.group(1)) if m else default


def string(pattern, block, default=None):
    m = re.search(pattern, block)
    return m.group(1) if m else default


# ============================================================
# Board outline
# ============================================================

outline = None

for b in blocks("gr_rect"):

    layer = string(
        r'\(layer\s+"([^"]+)"\)',
        b
    )

    if layer != "Edge.Cuts":
        continue

    m = re.search(
        r'\(start\s+([-\d.]+)\s+([-\d.]+)\)',
        b
    )

    n = re.search(
        r'\(end\s+([-\d.]+)\s+([-\d.]+)\)',
        b
    )

    if m and n:

        outline = {
            "xmin": float(m.group(1)),
            "ymin": float(m.group(2)),
            "xmax": float(n.group(1)),
            "ymax": float(n.group(2))
        }

        break


# ============================================================
# Stackup
# ============================================================

stackup = {
    "f_cu_thickness_mm": 0.035,
    "b_cu_thickness_mm": 0.035,
    "dielectric_thickness_mm": 1.51,
    "epsilon_r": 4.5,
    "loss_tangent": 0.02
}


# ============================================================
# Segments
# ============================================================

segments = []

for b in blocks("segment"):

    m_start = re.search(
        r'\(start\s+([-\d.]+)\s+([-\d.]+)\)',
        b
    )

    m_end = re.search(
        r'\(end\s+([-\d.]+)\s+([-\d.]+)\)',
        b
    )

    m_width = re.search(
        r'\(width\s+([-\d.]+)\)',
        b
    )

    m_layer = re.search(
        r'\(layer\s+"([^"]+)"\)',
        b
    )

    m_net = re.search(
        r'\(net(?:\s+\d+)?\s+"([^"]+)"\)',
        b
    )

    if not (
        m_start and
        m_end and
        m_width and
        m_layer
    ):
        continue

    segments.append({
        "start": [
            float(m_start.group(1)),
            float(m_start.group(2))
        ],
        "end": [
            float(m_end.group(1)),
            float(m_end.group(2))
        ],
        "width": float(m_width.group(1)),
        "layer": m_layer.group(1),
        "net": m_net.group(1) if m_net else ""
    })


# ============================================================
# Vias
# ============================================================

vias = []

for b in blocks("via"):

    m_at = re.search(
        r'\(at\s+([-\d.]+)\s+([-\d.]+)\)',
        b
    )

    m_size = re.search(
        r'\(size\s+([-\d.]+)\)',
        b
    )

    m_drill = re.search(
        r'\(drill\s+([-\d.]+)\)',
        b
    )

    m_layers = re.search(
        r'\(layers\s+"([^"]+)"\s+"([^"]+)"\)',
        b
    )

    m_net = re.search(
        r'\(net(?:\s+\d+)?\s+"([^"]+)"\)',
        b
    )

    if not (m_at and m_size and m_drill):
        continue

    vias.append({
        "x": float(m_at.group(1)),
        "y": float(m_at.group(2)),
        "diameter": float(m_size.group(1)),
        "drill": float(m_drill.group(1)),
        "layers": [
            m_layers.group(1),
            m_layers.group(2)
        ] if m_layers else ["F.Cu", "B.Cu"],
        "net": m_net.group(1) if m_net else ""
    })


# ============================================================
# Pads
#
# We initially extract pads only from footprints.
# Global pad coordinates are calculated later from footprint
# position/rotation.
# ============================================================

footprints = []

for fb in blocks("footprint"):

    m_name = re.search(
        r'\(footprint\s+"([^"]+)"',
        fb
    )

    m_at = re.search(
        r'\(at\s+([-\d.]+)\s+([-\d.]+)(?:\s+([-\d.]+))?\)',
        fb
    )

    if not m_name or not m_at:
        continue

    name = m_name.group(1)

    fx = float(m_at.group(1))
    fy = float(m_at.group(2))
    rot = float(m_at.group(3)) if m_at.group(3) else 0.0

    pads = []

    # Extract pad blocks inside footprint.
    # Avoid accidentally taking nested pad-like text.
    for pb in re.findall(
        r'\(pad\s+.*?\n\s*\)',
        fb,
        re.S
    ):

        m_num = re.search(
            r'\(pad\s+"([^"]+)"',
            pb
        )

        m_type = re.search(
            r'\(pad\s+"[^"]+"\s+([^\s]+)',
            pb
        )

        m_shape = re.search(
            r'\(pad\s+"[^"]+"\s+[^\s]+\s+([^\s]+)',
            pb
        )

        m_atp = re.search(
            r'\(at\s+([-\d.]+)\s+([-\d.]+)(?:\s+([-\d.]+))?\)',
            pb
        )

        m_size = re.search(
            r'\(size\s+([-\d.]+)\s+([-\d.]+)\)',
            pb
        )

        m_layer = re.search(
            r'\(layers\s+([^\n]+?)\)',
            pb
        )

        m_net = re.search(
            r'\(net(?:\s+\d+)?\s+"([^"]+)"\)',
            pb
        )

        if not m_num or not m_atp or not m_size:
            continue

        pads.append({
            "number": m_num.group(1),
            "type": m_type.group(1) if m_type else "",
            "shape": m_shape.group(1) if m_shape else "",
            "x": float(m_atp.group(1)),
            "y": float(m_atp.group(2)),
            "rotation": (
                float(m_atp.group(3))
                if m_atp.group(3)
                else 0.0
            ),
            "width": float(m_size.group(1)),
            "height": float(m_size.group(2)),
            "layers_raw": (
                m_layer.group(1).strip()
                if m_layer else ""
            ),
            "net": m_net.group(1) if m_net else ""
        })

    footprints.append({
        "name": name,
        "x": fx,
        "y": fy,
        "rotation": rot,
        "pads": pads
    })



# ============================================================
# Zones
#
# IMPORTANT:
# Use the original polygon, NOT filled_polygon.
# ============================================================

# ============================================================
# Helper: extract a complete KiCad S-expression block
# ============================================================

def extract_block(text, name):
    """
    Extract a complete KiCad block such as:

        (polygon
            (pts
                (xy ...)
                (xy ...)
            )
        )

    Handles nested parentheses correctly.
    """

    token = "(" + name
    start = text.find(token)

    if start < 0:
        return None

    depth = 0

    for i in range(start, len(text)):

        if text[i] == "(":
            depth += 1

        elif text[i] == ")":
            depth -= 1

            if depth == 0:
                return text[start:i+1]

    return None


# ============================================================
# Zones
#
# IMPORTANT:
# Use the original polygon, NOT filled_polygon.
# ============================================================

zones = []

for zb in blocks("zone"):

    m_net = re.search(
        r'\(net(?:\s+\d+)?\s+"([^"]+)"\)',
        zb
    )

    m_layer = re.search(
        r'\(layer\s+"([^"]+)"\)',
        zb
    )

    m_priority = re.search(
        r'\(priority\s+([-\d.]+)\)',
        zb
    )

    # --------------------------------------------------------
    # Extract complete polygon block
    # --------------------------------------------------------

    polyblock = extract_block(
        zb,
        "polygon"
    )

    if not polyblock:
        continue

    # --------------------------------------------------------
    # Extract complete pts block
    # --------------------------------------------------------

    ptsblock = extract_block(
        polyblock,
        "pts"
    )

    if not ptsblock:
        continue

    # --------------------------------------------------------
    # Extract XY points
    # --------------------------------------------------------

    points = []

    for m in re.finditer(
        r'\(xy\s+([-\d.]+)\s+([-\d.]+)\)',
        ptsblock
    ):
        points.append([
            float(m.group(1)),
            float(m.group(2))
        ])

    # --------------------------------------------------------
    # Save zone
    # --------------------------------------------------------

    zones.append({
        "net": m_net.group(1) if m_net else "",
        "layer": m_layer.group(1) if m_layer else "",
        "priority": (
            float(m_priority.group(1))
            if m_priority else None
        ),
        "polygon": points
    })

# ============================================================
# RF interfaces
# ============================================================

rf_interfaces = {
    "J1_RF_IN": {
        "net": "Net-(U1-RFIN)",
        "x": 104.9125,
        "y": 90.5
    },

    "U1_RF_IN": {
        "net": "Net-(U1-RFIN)",
        "x": 128.485,
        "y": 90.56
    },

    "U1_RF_OUT": {
        "net": "Net-(F1-B3DL)",
        "x": 134.885,
        "y": 88.44
    },

    "F1_B3DL": {
        "net": "Net-(F1-B3DL)",
        "x": 145.0,
        "y": 89.55
    },

    "F1_B3UL": {
        "net": "Net-(F1-B3UL)",
        "x": 145.0,
        "y": 91.45
    },

    "F1_ANT": {
        "net": "Net-(F1-ANT)",
        "x": 146.4,
        "y": 90.5
    },

    "J2_RF_OUT": {
        "net": "Net-(F1-ANT)",
        "x": 158.6875,
        "y": 90.5
    }
}


# ============================================================
# Complete geometry
# ============================================================

geometry = {
    "format": "pcb_geometry_v1",

    "source": PCB,

    "board": outline,

    "stackup": stackup,

    "segments": segments,

    "vias": vias,

    "footprints": footprints,

    "zones": zones,

    "rf_interfaces": rf_interfaces
}


# ============================================================
# Write JSON
# ============================================================

with open("pcb_geometry.json", "w") as f:
    json.dump(geometry, f, indent=2)


# ============================================================
# Summary
# ============================================================

print()
print("=" * 70)
print("KiCad PCB GEOMETRY")
print("=" * 70)

print(
    "Board:",
    f"{outline['xmin']} .. {outline['xmax']} mm,",
    f"{outline['ymin']} .. {outline['ymax']} mm"
)

print(
    "Size:",
    f"{outline['xmax'] - outline['xmin']:.3f} x",
    f"{outline['ymax'] - outline['ymin']:.3f} mm"
)

print("Segments :", len(segments))
print("Vias     :", len(vias))
print("Footprints:", len(footprints))
print(
    "Pads     :",
    sum(len(fp["pads"]) for fp in footprints)
)
print("Zones    :", len(zones))

print()
print("Zones:")

for i, z in enumerate(zones, 1):
    print(
        f"  {i}: "
        f"{z['layer']:5s} "
        f"{z['net']:10s} "
        f"points={len(z['polygon'])}"
    )

print()
print("RF interfaces:")

for name, p in rf_interfaces.items():
    print(
        f"  {name:12s} "
        f"({p['x']:.4f}, {p['y']:.4f}) "
        f"{p['net']}"
    )

print()
print("Saved: pcb_geometry.json")
