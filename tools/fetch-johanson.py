"""Fetch the pinned public sample for local verification, not redistribution."""
import hashlib
import sys
import urllib.request
from pathlib import Path

URL = 'https://www.johansontechnology.com/docs/1886/5500BP41A0665_sT2aflU.s2p'
SHA = '404804182b54e3c37d4438b9b685ddb16d264768c8f1368ddd14f494d55310e6'
if len(sys.argv) != 2:
    raise SystemExit('Usage: python tools/fetch-johanson.py OUTPUT.s2p')
destination = Path(sys.argv[1])
if destination.exists():
    raise SystemExit('Destination already exists; no overwrite')
with urllib.request.urlopen(URL, timeout=30) as response:
    data = response.read(1_000_001)
if len(data) > 1_000_000 or hashlib.sha256(data).hexdigest() != SHA:
    raise SystemExit('Source changed or too large; review source revision before use')
with destination.open('xb') as output:
    output.write(data)
print(f'{len(data)} bytes; SHA-256 {SHA}')
