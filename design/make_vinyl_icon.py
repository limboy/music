"""Generates design/AppIcon-Vinyl.svg — a minimal vinyl record app icon.

Run:  python3 design/make_vinyl_icon.py && rsvg-convert -w 1024 -h 1024 design/AppIcon-Vinyl.svg -o out.png
"""
import math
from pathlib import Path

C = 512          # centre
R = 404          # record radius
LABEL = 138      # label radius
HOLE = 13        # spindle hole radius

# Fine grooves between the label and the rim, with a couple of wider "track gaps".
grooves = []
r = LABEL + 26
i = 0
while r < R - 10:
    opacity = 0.055 if i % 2 else 0.03
    grooves.append(f'<circle cx="{C}" cy="{C}" r="{r:.1f}" stroke="#FFFFFF" stroke-opacity="{opacity}" stroke-width="1.2" fill="none"/>')
    r += 5.2
    i += 1
for gap in (215, 288, 346):   # track separators: slightly darker, wider rings
    grooves.append(f'<circle cx="{C}" cy="{C}" r="{gap}" stroke="#000000" stroke-opacity="0.55" stroke-width="5" fill="none"/>')

def wedge(angle_deg: float, spread_deg: float) -> str:
    """A pie slice from the centre to beyond the rim — used for light reflections."""
    a0 = math.radians(angle_deg - spread_deg / 2)
    a1 = math.radians(angle_deg + spread_deg / 2)
    far = R + 40
    x0, y0 = C + far * math.cos(a0), C + far * math.sin(a0)
    x1, y1 = C + far * math.cos(a1), C + far * math.sin(a1)
    return f"M{C},{C} L{x0:.1f},{y0:.1f} A{far},{far} 0 0 1 {x1:.1f},{y1:.1f} Z"

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <radialGradient id="bg" cx="50%" cy="42%" r="75%">
      <stop offset="0" stop-color="#3B3943"/>
      <stop offset="0.6" stop-color="#232228"/>
      <stop offset="1" stop-color="#121215"/>
    </radialGradient>

    <radialGradient id="vinyl" cx="50%" cy="50%" r="50%">
      <stop offset="0" stop-color="#1C1C20"/>
      <stop offset="0.9" stop-color="#0E0E10"/>
      <stop offset="1" stop-color="#050506"/>
    </radialGradient>

    <!-- Label: Songs (coral) → Jazz (gold) → Piano (blue) -->
    <linearGradient id="label" x1="0.15" y1="0.1" x2="0.85" y2="0.9">
      <stop offset="0" stop-color="#FF7A59"/>
      <stop offset="0.52" stop-color="#E5B567"/>
      <stop offset="1" stop-color="#9DB8FF"/>
    </linearGradient>
    <radialGradient id="labelShade" cx="50%" cy="50%" r="50%">
      <stop offset="0.75" stop-color="#000000" stop-opacity="0"/>
      <stop offset="1" stop-color="#000000" stop-opacity="0.22"/>
    </radialGradient>

    <radialGradient id="sheen" cx="{C}" cy="{C}" r="{R}" gradientUnits="userSpaceOnUse">
      <stop offset="0.3" stop-color="#FFFFFF" stop-opacity="0"/>
      <stop offset="0.75" stop-color="#FFFFFF" stop-opacity="0.2"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0.05"/>
    </radialGradient>

    <clipPath id="record"><circle cx="{C}" cy="{C}" r="{R}"/></clipPath>
    <filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="18"/></filter>
    <filter id="shadow" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="28"/></filter>
  </defs>

  <rect width="1024" height="1024" fill="url(#bg)"/>

  <!-- Drop shadow -->
  <circle cx="{C}" cy="{C + 22}" r="{R}" fill="#000000" opacity="0.6" filter="url(#shadow)"/>

  <!-- Record -->
  <circle cx="{C}" cy="{C}" r="{R}" fill="url(#vinyl)"/>
  <g clip-path="url(#record)">
    {''.join(grooves)}
    <!-- Two opposing light reflections across the grooves -->
    <g filter="url(#soft)">
      <path d="{wedge(-50, 26)}" fill="url(#sheen)"/>
      <path d="{wedge(130, 26)}" fill="url(#sheen)"/>
    </g>
  </g>
  <!-- Rim highlight -->
  <circle cx="{C}" cy="{C}" r="{R - 1}" fill="none" stroke="#FFFFFF" stroke-opacity="0.10" stroke-width="2"/>

  <!-- Label -->
  <circle cx="{C}" cy="{C}" r="{LABEL}" fill="url(#label)"/>
  <circle cx="{C}" cy="{C}" r="{LABEL}" fill="url(#labelShade)"/>
  <circle cx="{C}" cy="{C}" r="{LABEL * 0.62:.1f}" fill="none" stroke="#FFFFFF" stroke-opacity="0.22" stroke-width="2"/>

  <!-- Spindle hole -->
  <circle cx="{C}" cy="{C}" r="{HOLE}" fill="#0B0B0D"/>
  <circle cx="{C}" cy="{C}" r="{HOLE}" fill="none" stroke="#000000" stroke-opacity="0.35" stroke-width="2"/>
</svg>
'''

Path(__file__).with_name("AppIcon-Vinyl.svg").write_text(svg)
print("wrote", Path(__file__).with_name("AppIcon-Vinyl.svg"))
