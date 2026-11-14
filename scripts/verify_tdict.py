#!/usr/bin/env python3
"""Validate bundled TranslateDesk dictionary indexes without third-party modules."""
from __future__ import annotations

import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HEADER = struct.Struct("<8sIIQQQ")
INDEX = struct.Struct("<HHQI")
EXPECTED = {
    "cambridge-en-zh.tdict": (63_762, {"apple": "苹果", "running": "running"}),
    "collins-han-en.tdict": (86_145, {"苹果": "apple", "部署": "to deploy", "接口": "interface"}),
    "collins-cobuild-en.tdict": (33_261, {"apple": "An apple is a round fruit", "running": "Running is the activity"}),
}


def parse(path: Path):
    data = path.read_bytes()
    magic, version, count, table_offset, index_offset, data_offset = HEADER.unpack_from(data, 0)
    assert magic == b"TDICT01\0", f"{path.name}: bad magic"
    assert version == 1, f"{path.name}: bad version"
    assert 0 < table_offset <= index_offset <= data_offset <= len(data)

    rows = []
    previous = None
    for i in range(count):
        record_offset = struct.unpack_from("<Q", data, table_offset + i * 8)[0]
        key_len, display_len, content_offset, content_len = INDEX.unpack_from(data, record_offset)
        key_start = record_offset + INDEX.size
        key = data[key_start:key_start + key_len]
        display = data[key_start + key_len:key_start + key_len + display_len]
        assert previous is None or previous < key, f"{path.name}: unsorted or duplicate key"
        previous = key
        absolute = data_offset + content_offset
        assert absolute + content_len <= len(data), f"{path.name}: content out of bounds"
        rows.append((key, display, absolute, content_len))
    return data, rows


def lookup(data: bytes, rows, word: str) -> str | None:
    key = word.lower().encode("utf-8")
    low, high = 0, len(rows)
    while low < high:
        mid = (low + high) // 2
        if rows[mid][0] < key:
            low = mid + 1
        else:
            high = mid
    if low >= len(rows) or rows[low][0] != key:
        return None
    _, _, offset, length = rows[low]
    return data[offset:offset + length].decode("utf-8")


def main() -> None:
    resource_dir = ROOT / "Sources" / "TranslateCore" / "Resources"
    for filename, (expected_count, probes) in EXPECTED.items():
        path = resource_dir / filename
        data, rows = parse(path)
        assert len(rows) == expected_count, f"{filename}: expected {expected_count}, got {len(rows)}"
        for word, expected_text in probes.items():
            body = lookup(data, rows, word)
            assert body and expected_text in body, f"{filename}: probe failed for {word}"
        print(f"OK {filename}: {len(rows):,} keys, {len(data) / 1024 / 1024:.1f} MiB")


if __name__ == "__main__":
    main()
