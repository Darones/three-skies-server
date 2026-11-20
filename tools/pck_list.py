import struct
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = path.read_bytes()
if data[:4] != b"GDPC":
    raise SystemExit("not a PCK")

pack_version = struct.unpack_from("<I", data, 4)[0]
major, minor, patch, flags = struct.unpack_from("<IIII", data, 8)
file_base = struct.unpack_from("<Q", data, 24)[0]
dir_offset = struct.unpack_from("<Q", data, 32)[0]
pos = dir_offset
count = struct.unpack_from("<I", data, pos)[0]
pos += 4
files = []
for _ in range(count):
    path_len = struct.unpack_from("<I", data, pos)[0]
    pos += 4
    name = data[pos:pos + path_len].decode("utf-8", "replace")
    pos += path_len
    offset, size = struct.unpack_from("<QQ", data, pos)
    pos += 16
    md5 = data[pos:pos + 16]
    pos += 16
    entry_flags = struct.unpack_from("<I", data, pos)[0]
    pos += 4
    files.append((size, name, offset, entry_flags))

files.sort(reverse=True)
print(f"pck={path.name} version={pack_version} files={count} size={path.stat().st_size/1024/1024:.2f} MB")
print("--- top 40 ---")
for size, name, offset, entry_flags in files[:40]:
    print(f"{size/1024/1024:7.2f} MB  {name}  (flags={entry_flags})")
print("--- by extension ---")
from collections import defaultdict
by_ext = defaultdict(lambda: [0, 0])
for size, name, _, _ in files:
    ext = Path(name).suffix.lower() or "(none)"
    by_ext[ext][0] += 1
    by_ext[ext][1] += size
for ext, (n, total) in sorted(by_ext.items(), key=lambda kv: kv[1][1], reverse=True):
    print(f"{total/1024/1024:7.2f} MB  {n:4d}  {ext}")
