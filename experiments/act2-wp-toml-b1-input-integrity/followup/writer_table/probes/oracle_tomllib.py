#!/usr/bin/env python3
r"""tomllib oracle driver — WRITER-TABLE Task 3 (cross-check column).

Walks a raw output directory, parses every *.toml with Python 3.12 tomllib,
and emits TSV: <relpath>\t<OK|RAISE>\t<short message>.

AUTHORITY LIMIT (do not remove): Python 3.12 tomllib implements TOML
v1.0.0 ONLY. Its verdict is authoritative exclusively for documents whose
validity is being judged against TOML v1.0.0 (e.g. Toml_v100-flavor
emissions). For v1.1.0-only syntax (\e, \xHH, multi-line inline tables,
trailing commas) a RAISE here is EXPECTED and carries no v1.1.0 verdict
weight; the pinned spec text (followup/SPEC_BASELINE.md) is the only
v1.1.0 authority.
"""
import sys
import tomllib
from pathlib import Path


def main() -> None:
    raw = Path(sys.argv[1])
    out = Path(sys.argv[2])
    rows = []
    for p in sorted(raw.rglob("*.toml")):
        rel = p.relative_to(raw).as_posix()
        data = p.read_bytes()
        try:
            tomllib.loads(data.decode("utf-8"))
            rows.append(f"{rel}\tOK\t")
        except UnicodeDecodeError as e:
            rows.append(f"{rel}\tRAISE\tutf8: {e}")
        except tomllib.TOMLDecodeError as e:
            msg = str(e).replace("\t", " ").replace("\n", " ")[:160]
            rows.append(f"{rel}\tRAISE\t{msg}")
    out.write_text("relpath\ttomllib\tmsg\n" + "\n".join(rows) + "\n")
    ok = sum(1 for r in rows if r.split("\t")[1] == "OK")
    print(f"tomllib oracle: {len(rows)} docs, {ok} OK, {len(rows) - ok} RAISE")


if __name__ == "__main__":
    main()
