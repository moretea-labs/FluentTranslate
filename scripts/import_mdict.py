#!/usr/bin/env python3
"""Convert an MDict .mdx file into TranslateDesk's mmap-friendly .tdict format.

Requires: pip install mdict-utils==1.3.14
The generated file contains only normalized textual entries. Missing MDD assets are
intentionally removed, so the app never displays broken images or scripts.
"""
from __future__ import annotations

import argparse
import html
import os
import re
import struct
import sys
import unicodedata
from collections import OrderedDict
from pathlib import Path

try:
    from mdict_utils.base.readmdict import MDX
except ImportError as exc:
    raise SystemExit("Install the importer dependency first: pip install mdict-utils==1.3.14") from exc

# mdict-utils ships a pure-Python LZO decoder but older MDX code only tries the
# optional native `lzo` module. Patch the decoder at runtime for MDX 1.x files.
try:
    import mdict_utils.base.readmdict as readmdict_module
    if getattr(readmdict_module, "lzo", None) is None:
        from mdict_utils.base import lzo as pure_lzo
        original_decode = readmdict_module.MDict._decode_block

        def decode_block_with_pure_lzo(self, block: bytes, decompressed_size: int):
            info = struct.unpack("<L", block[:4])[0]
            compression_method = info & 0xF
            if compression_method != 1:
                return original_decode(self, block, decompressed_size)

            # MDX 1.x LZO blocks used by the supplied Collins dictionary are not encrypted.
            # Keep the branch deliberately narrow; unsupported encrypted variants still fail.
            encryption_method = (info >> 4) & 0xF
            if encryption_method != 0:
                return original_decode(self, block, decompressed_size)
            adler32 = struct.unpack(">I", block[4:8])[0]
            decoded = pure_lzo.decompress(
                block[8:],
                initSize=decompressed_size,
                blockSize=max(8192, decompressed_size),
            )
            import zlib
            if (zlib.adler32(decoded) & 0xFFFFFFFF) != adler32:
                raise RuntimeError("LZO block checksum mismatch")
            return decoded

        readmdict_module.MDict._decode_block = decode_block_with_pure_lzo
except Exception:
    # The normal parser path will surface a precise error if this compatibility
    # patch is not applicable.
    pass

MAGIC = b"TDICT01\0"
HEADER = struct.Struct("<8sIIQQQ")
INDEX_RECORD = struct.Struct("<HHQI")
LINK_RE = re.compile(r"^\s*@@@LINK=(.*?)\s*(?:\x00)?\s*$", re.I | re.S)
SCRIPT_STYLE_RE = re.compile(r"(?is)<(script|style)\b.*?</\1\s*>")
MEDIA_RE = re.compile(r"(?is)<(?:link|img|source|audio)\b[^>]*>")
BR_RE = re.compile(r"(?is)<br\s*/?>")
BLOCK_RE = re.compile(r"(?is)</?(?:div|p|h[1-6]|li|ul|ol|table|tr|blockquote|section|article|header|footer|hr|block)\b[^>]*>")
CELL_RE = re.compile(r"(?is)</?td\b[^>]*>")
TAG_RE = re.compile(r"(?is)<[^>]+>")
CONTROL_IMAGE_RE = re.compile(r"[\x1e\x1f][^\x1e\x1f\n]{0,100}[\x1e\x1f]")
SPACE_RE = re.compile(r"[ \t\r\f\v]+")


def normalize_key(value: str) -> str:
    value = unicodedata.normalize("NFC", value)
    value = value.replace("’", "'").replace("‐", "-").replace("‑", "-")
    return " ".join(value.strip().lower().split())


def html_to_text(source: str) -> str:
    source = source.replace("\x00", "")
    source = SCRIPT_STYLE_RE.sub("", source)
    source = MEDIA_RE.sub(" ", source)
    source = BR_RE.sub("\n", source)
    source = BLOCK_RE.sub("\n", source)
    source = CELL_RE.sub(" | ", source)
    source = TAG_RE.sub(" ", source)
    source = CONTROL_IMAGE_RE.sub(" ", source)
    source = html.unescape(source).replace("\xa0", " ")

    lines: list[str] = []
    for raw_line in source.splitlines():
        line = SPACE_RE.sub(" ", raw_line).strip(" |")
        line = line.replace("◆", "").replace("◇", "").strip()
        if line.startswith("＋ "):
            line = line[2:].strip()
        if not line or line == "---":
            continue
        if not lines or line != lines[-1]:
            lines.append(line)
    return "\n".join(lines).strip()


def read_entries(path: Path):
    mdx = MDX(str(path))
    content_by_key: dict[str, list[str]] = OrderedDict()
    display_by_key: dict[str, str] = {}
    alias_by_key: dict[str, str] = {}

    for key_bytes, value_bytes in mdx.items():
        display = key_bytes.decode("utf-8", errors="ignore").strip().strip("\x00")
        key = normalize_key(display)
        if not key:
            continue
        display_by_key.setdefault(key, display)

        raw = value_bytes.decode("utf-8", errors="ignore").strip("\x00").strip()
        link_match = LINK_RE.match(raw)
        if link_match:
            alias_by_key.setdefault(key, normalize_key(link_match.group(1)))
            continue

        text = html_to_text(raw)
        if text:
            content_by_key.setdefault(key, []).append(text)

    combined: dict[str, str] = {}
    for key, parts in content_by_key.items():
        unique_parts: list[str] = []
        seen: set[str] = set()
        for part in parts:
            if part not in seen:
                unique_parts.append(part)
                seen.add(part)
        combined[key] = "\n\n".join(unique_parts)

    def resolve(key: str, visited: set[str] | None = None) -> str | None:
        if key in combined:
            return key
        target = alias_by_key.get(key)
        if not target:
            return None
        visited = visited or set()
        if key in visited:
            return None
        visited.add(key)
        return resolve(target, visited)

    index_rows: list[tuple[str, str, str]] = []
    all_keys = set(combined) | set(alias_by_key)
    for key in sorted(all_keys):
        target = resolve(key)
        if target and combined.get(target):
            index_rows.append((key, display_by_key.get(key, key), target))
    return mdx, index_rows, combined


def build_tdict(source: Path, output: Path) -> None:
    mdx, rows, combined = read_entries(source)

    # Store each canonical content body once; aliases reuse the same byte range.
    content_offsets: dict[str, tuple[int, int]] = {}
    data_parts: list[bytes] = []
    cursor = 0
    for canonical in sorted({target for _, _, target in rows}):
        encoded = combined[canonical].encode("utf-8")
        content_offsets[canonical] = (cursor, len(encoded))
        data_parts.append(encoded)
        cursor += len(encoded)

    index_parts: list[bytes] = []
    relative_offsets: list[int] = []
    index_cursor = 0
    for key, display, canonical in rows:
        key_bytes = key.encode("utf-8")
        display_bytes = display.encode("utf-8")
        if len(key_bytes) > 0xFFFF or len(display_bytes) > 0xFFFF:
            continue
        content_offset, content_length = content_offsets[canonical]
        if content_length > 0xFFFFFFFF:
            raise RuntimeError(f"Entry too large: {display}")
        record = INDEX_RECORD.pack(
            len(key_bytes), len(display_bytes), content_offset, content_length
        ) + key_bytes + display_bytes
        relative_offsets.append(index_cursor)
        index_parts.append(record)
        index_cursor += len(record)

    count = len(index_parts)
    header_size = HEADER.size
    offset_table_offset = header_size
    index_offset = offset_table_offset + count * 8
    data_offset = index_offset + sum(map(len, index_parts))

    output.parent.mkdir(parents=True, exist_ok=True)
    temp = output.with_suffix(output.suffix + ".tmp")
    with temp.open("wb") as handle:
        handle.write(HEADER.pack(MAGIC, 1, count, offset_table_offset, index_offset, data_offset))
        for relative in relative_offsets:
            handle.write(struct.pack("<Q", index_offset + relative))
        for part in index_parts:
            handle.write(part)
        for part in data_parts:
            handle.write(part)
    os.replace(temp, output)

    print(
        f"{source.name}: {len(mdx):,} MDX records -> {count:,} searchable keys, "
        f"{output.stat().st_size / 1024 / 1024:.1f} MiB"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    build_tdict(args.source, args.output)


if __name__ == "__main__":
    main()
