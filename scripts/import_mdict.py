#!/usr/bin/env python3
"""Convert an unencrypted MDict MDX file into FluentTranslate SQLite.

Supports MDict engine 1.2 LZO-compressed dictionaries through readmdict + lzokay.
Install dependencies with:
    python3 -m pip install readmdict lzokay

The MDD sidecar is not required for plain-text lookup. It normally contains
images/audio/CSS referenced by the MDX HTML.
"""
from __future__ import annotations

import argparse
import html
import re
import sqlite3
import struct
import sys
import types
import unicodedata
from pathlib import Path


def install_lzo_compat() -> None:
    """Expose the python-lzo API expected by readmdict using MIT lzokay."""
    try:
        import lzo  # type: ignore  # noqa: F401
        return
    except ImportError:
        pass

    try:
        import lzokay  # type: ignore
    except ImportError as exc:
        raise SystemExit(
            "Missing dependency. Run: python3 -m pip install readmdict lzokay"
        ) from exc

    shim = types.ModuleType("lzo")

    def decompress(data: bytes) -> bytes:
        if len(data) < 5 or data[0] != 0xF0:
            raise ValueError("Unsupported LZO stream framing")
        expected_size = struct.unpack(">I", data[1:5])[0]
        return lzokay.decompress(data[5:], expected_size)

    shim.decompress = decompress  # type: ignore[attr-defined]
    sys.modules["lzo"] = shim


def normalize_headword(value: str) -> str:
    value = unicodedata.normalize("NFKC", value).casefold().strip()
    return re.sub(r"\s+", " ", value)


def html_to_plain(value: str) -> str:
    value = value.replace("\r", "\n")
    value = re.sub(r"(?i)<br\s*/?>", "\n", value)
    value = re.sub(r"(?i)</(?:p|div|li|h[1-6])>", "\n", value)
    value = re.sub(r"(?is)<script\b.*?</script>", "", value)
    value = re.sub(r"(?is)<style\b.*?</style>", "", value)
    value = re.sub(r"(?is)<img\b[^>]*>", "", value)
    value = re.sub(r"(?s)<[^>]+>", "", value)
    value = html.unescape(value)
    value = value.replace("\x1e", "").replace("\x1f", "")
    value = re.sub(r"[ \t\f\v]+", " ", value)
    value = re.sub(r" *\n *", "\n", value)
    value = re.sub(r"\n{3,}", "\n\n", value)
    return value.strip()


def convert(mdx_path: Path, output_path: Path, source_name: str) -> None:
    install_lzo_compat()
    try:
        from readmdict import MDX  # type: ignore
    except ImportError as exc:
        raise SystemExit(
            "Missing dependency. Run: python3 -m pip install readmdict lzokay"
        ) from exc

    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists():
        output_path.unlink()

    dictionary = MDX(str(mdx_path))
    connection = sqlite3.connect(output_path)
    try:
        connection.executescript(
            """
            PRAGMA journal_mode = OFF;
            PRAGMA synchronous = OFF;
            PRAGMA temp_store = MEMORY;
            CREATE TABLE dictionary_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                headword TEXT NOT NULL,
                normalized_headword TEXT NOT NULL,
                plain_text TEXT NOT NULL,
                source_name TEXT NOT NULL
            );
            CREATE INDEX idx_dictionary_entries_normalized
                ON dictionary_entries(normalized_headword);
            CREATE INDEX idx_dictionary_entries_headword
                ON dictionary_entries(headword COLLATE NOCASE);
            CREATE TABLE dictionary_metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """
        )

        insert_sql = """
            INSERT INTO dictionary_entries
                (headword, normalized_headword, plain_text, source_name)
            VALUES (?, ?, ?, ?)
        """
        batch: list[tuple[str, str, str, str]] = []
        count = 0
        for key_bytes, value_bytes in dictionary.items():
            headword = key_bytes.decode("utf-8", errors="ignore").strip()
            raw_html = value_bytes.decode("utf-8", errors="ignore").strip("\x00")
            if not headword or not raw_html:
                continue
            plain = html_to_plain(raw_html)
            batch.append(
                (headword, normalize_headword(headword), plain, source_name)
            )
            if len(batch) >= 1000:
                connection.executemany(insert_sql, batch)
                connection.commit()
                count += len(batch)
                print(f"Imported {count} entries…", file=sys.stderr)
                batch.clear()

        if batch:
            connection.executemany(insert_sql, batch)
            count += len(batch)

        metadata = {
            "schema_version": "1",
            "source_name": source_name,
            "entry_count": str(count),
            "source_filename": mdx_path.name,
            "format": "mdict-mdx",
        }
        connection.executemany(
            "INSERT INTO dictionary_metadata(key, value) VALUES (?, ?)",
            metadata.items(),
        )
        connection.execute("ANALYZE")
        connection.commit()
    finally:
        connection.close()

    print(f"Created {output_path} with {count} entries")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("mdx", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--source-name", default="Imported MDict")
    args = parser.parse_args()
    convert(args.mdx.expanduser(), args.output.expanduser(), args.source_name)


if __name__ == "__main__":
    main()
