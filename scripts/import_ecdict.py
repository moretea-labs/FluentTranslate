#!/usr/bin/env python3
"""Convert ECDICT CSV into the SQLite database expected by FluentTranslate.

Usage:
  python3 scripts/import_ecdict.py /path/to/ecdict.csv

Output:
  ~/Library/Application Support/FluentTranslate/ecdict.sqlite
"""

from __future__ import annotations

import csv
import os
import sqlite3
import sys
from pathlib import Path


def output_path() -> Path:
    return Path.home() / "Library" / "Application Support" / "FluentTranslate" / "ecdict.sqlite"


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: import_ecdict.py /path/to/ecdict.csv", file=sys.stderr)
        return 2

    source = Path(sys.argv[1]).expanduser().resolve()
    if not source.exists():
        print(f"ECDICT CSV not found: {source}", file=sys.stderr)
        return 2

    destination = output_path()
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(".sqlite.tmp")
    if temporary.exists():
        temporary.unlink()

    connection = sqlite3.connect(temporary)
    try:
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA synchronous=OFF")
        connection.execute(
            """
            CREATE TABLE stardict (
                word TEXT NOT NULL,
                phonetic TEXT,
                definition TEXT,
                translation TEXT,
                pos TEXT,
                collins INTEGER,
                oxford INTEGER,
                tag TEXT,
                bnc INTEGER,
                frq INTEGER,
                exchange TEXT,
                detail TEXT,
                audio TEXT
            )
            """
        )

        insert_sql = """
            INSERT INTO stardict (
                word, phonetic, definition, translation, pos, collins,
                oxford, tag, bnc, frq, exchange, detail, audio
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        count = 0
        with source.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            batch: list[tuple[object, ...]] = []
            for row in reader:
                batch.append(
                    (
                        row.get("word", ""),
                        row.get("phonetic", ""),
                        row.get("definition", ""),
                        row.get("translation", ""),
                        row.get("pos", ""),
                        int(row["collins"]) if row.get("collins", "").isdigit() else None,
                        int(row["oxford"]) if row.get("oxford", "").isdigit() else None,
                        row.get("tag", ""),
                        int(row["bnc"]) if row.get("bnc", "").isdigit() else None,
                        int(row["frq"]) if row.get("frq", "").isdigit() else None,
                        row.get("exchange", ""),
                        row.get("detail", ""),
                        row.get("audio", ""),
                    )
                )
                if len(batch) >= 5000:
                    connection.executemany(insert_sql, batch)
                    count += len(batch)
                    batch.clear()
                    print(f"Imported {count:,} entries...", flush=True)
            if batch:
                connection.executemany(insert_sql, batch)
                count += len(batch)

        connection.execute("CREATE INDEX idx_stardict_word_nocase ON stardict(word COLLATE NOCASE)")
        connection.commit()
    finally:
        connection.close()

    os.replace(temporary, destination)
    print(f"Done: {count:,} entries -> {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
