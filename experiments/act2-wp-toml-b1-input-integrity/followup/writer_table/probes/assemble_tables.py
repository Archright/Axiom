#!/usr/bin/env python3
"""Assemble the WRITER-TABLE deliverable TSVs from probe outputs.

Inputs (produced by probe_esc_sweep / probe_key_sweep / oracle_tomllib.py):
  <raw>/esc_sweep_v100.tsv, <raw>/esc_sweep_v110.tsv
  <raw>/keys_sweep_v100.tsv, <raw>/keys_sweep_v110.tsv
  <raw>/tomllib_oracle.tsv

Outputs:
  escapes.tsv, keys.tsv, roundtrip.tsv, preservation.tsv

Validity oracle: followup/SPEC_BASELINE.md (pinned spec text), NOT tomllib:
  - \\e            : reserved escape in v1.0.0 (INVALID) / listed in v1.1.0 (valid)
  - \\xHH          : reserved escape in v1.0.0 (INVALID) / listed in v1.1.0 (valid)
  - \\'            : reserved escape in BOTH versions (INVALID)
  - \\uXXXX \\UXXXXXXXX \\b \\t \\n \\f \\r \\\" \\\\ : valid both
  - bare keys      : only A-Za-z0-9_- (both versions)
  - quoted keys    : follow basic-string rules (both versions)
tomllib verdicts are carried in roundtrip.tsv for cross-checking and are
authoritative ONLY for v1.0.0 (Python 3.12 tomllib is v1.0.0-only).
"""
import sys
from pathlib import Path

RAW = Path(sys.argv[1])
OUT = Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)

FLAVORS = ("v100", "v110")


def read_tsv(path: Path) -> list[dict]:
    # plain tab-split: emitted tokens contain raw '"' chars, which would
    # corrupt csv-module quoting; fields never contain tabs/newlines
    lines = path.read_text().rstrip("\n").split("\n")
    header = lines[0].split("\t")
    rows = []
    for line in lines[1:]:
        parts = line.split("\t")
        assert len(parts) == len(header), f"{path}: {len(parts)} fields != {len(header)}: {line!r}"
        rows.append(dict(zip(header, parts)))
    return rows


def write_tsv(path: Path, header: list[str], rows: list[list]) -> None:
    lines = ["\t".join(header)]
    for r in rows:
        parts = [str(x) for x in r]
        assert all("\t" not in p and "\n" not in p for p in parts), f"field with tab/newline: {parts!r}"
        lines.append("\t".join(parts))
    path.write_text("\n".join(lines) + "\n")


def escape_validity(token: str) -> tuple[str, str, str]:
    """Per SPEC_BASELINE §1. Returns (v100, v110, reason)."""
    has_e = "\\e" in token
    has_x = "\\x" in token
    has_apos = "\\'" in token
    if has_apos:
        return "INVALID", "INVALID", "\\' is not an escape in either version (reserved both; writer.nim:153)"
    if has_e and has_x:
        return "INVALID", "VALID", "\\e and \\xHH: reserved escapes in v1.0.0; both listed in v1.1.0 (SPEC_BASELINE §1)"
    if has_e:
        return "INVALID", "VALID", "\\e: reserved escape in v1.0.0; listed escape in v1.1.0 (SPEC_BASELINE §1)"
    if has_x:
        return "INVALID", "VALID", "\\xHH: reserved escape in v1.0.0; listed escape in v1.1.0 (SPEC_BASELINE §1)"
    return "VALID", "VALID", ""


LIT_NOTE = "writer has no literal-string emission path (writer.nim:131-164); token shown is the basic-string form it emits"


# ---------------------------------------------------------------- escapes.tsv
esc_rows = []
esc_sweeps = {}
for fl in FLAVORS:
    esc_sweeps[fl] = read_tsv(RAW / f"esc_sweep_{fl}.tsv")
for fl in FLAVORS:
    for r in esc_sweeps[fl]:
        tok = r["emitted_token"]
        v1, v11, why = escape_validity(tok)
        note = "; ".join(x for x in (LIT_NOTE, why) if x)
        esc_rows.append([r["byte"], r["hex"], fl, tok, tok, v1, v11, note])
write_tsv(OUT / "escapes.tsv",
          ["byte", "hex", "flavor", "emitted_basic", "emitted_literal",
           "valid_v100", "valid_v110", "note"], esc_rows)

# -------------------------------------------------------------------- keys.tsv
BARE_OK = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
key_rows = []
key_sweeps = {}
for fl in FLAVORS:
    key_sweeps[fl] = read_tsv(RAW / f"keys_sweep_{fl}.tsv")
for fl in FLAVORS:
    for r in key_sweeps[fl]:
        case, hexid, tok = r["case"], r["hex"], r["key_token"]
        if case.startswith("mc:"):
            slug = case[3:]
            # decode display token back to the written key text
            key_disp = tok
            if key_disp.startswith('"') and key_disp.endswith('"') and len(key_disp) >= 2:
                v1, v11, why = escape_validity(key_disp)
                note = "quoted key (basic-string rules, SPEC_BASELINE §2); " + why if why else \
                       "quoted key (basic-string rules, SPEC_BASELINE §2)"
            else:
                bare_ok = all(c in BARE_OK for c in key_disp) and len(key_disp) > 0
                v1 = v11 = "VALID" if bare_ok else "INVALID"
                why = "" if bare_ok else "bare key outside A-Za-z0-9_- (SPEC_BASELINE §2 unquoted-key ABNF)"
                note = ("bare key; " + why) if why else "bare key"
        else:
            if tok.startswith('"'):
                v1, v11, why = escape_validity(tok)
                note = ("quoted key (basic-string rules, SPEC_BASELINE §2); " + why) if why else \
                       "quoted key (basic-string rules, SPEC_BASELINE §2)"
            else:
                bare_ok = len(tok) == 1 and tok in BARE_OK
                v1 = v11 = "VALID" if bare_ok else "INVALID"
                why = "" if bare_ok else "bare key outside A-Za-z0-9_- (SPEC_BASELINE §2 unquoted-key ABNF)"
                note = ("bare key; " + why) if why else "bare key"
        note = "; ".join(x for x in (note, LIT_NOTE) if x)
        key_rows.append([case, hexid, fl, tok, tok, v1, v11, note])
write_tsv(OUT / "keys.tsv",
          ["byte", "hex", "flavor", "emitted_key", "emitted_literal",
           "valid_v100", "valid_v110", "note"], key_rows)

# ---------------------------------------------------------------- roundtrip.tsv
oracle = {}
oracle_path = RAW / "tomllib_oracle.tsv"
if oracle_path.exists():
    for r in read_tsv(oracle_path):
        oracle[r["relpath"]] = (r["tomllib"], r["msg"])

V110_WEIGHTLESS = "tomllib is v1.0.0-only: RAISE expected for v1.1.0-only syntax, no v1.1.0 verdict weight"

rt_rows = []
for fl, ctx, prefix in (("v100", "string", "esc"), ("v110", "string", "esc")):
    for r in esc_sweeps[fl]:
        fname = f"{prefix}_{fl}/b{r['hex']}.toml"
        tol, msg = oracle.get(fname, ("MISSING", ""))
        note = V110_WEIGHTLESS if fl == "v110" else ""
        if tol == "RAISE" and fl == "v100" and ("\\e" in r["emitted_token"] or "\\x" in r["emitted_token"] or "\\'" in r["emitted_token"]):
            note = "tomllib RAISE confirms v1.0.0 reserved-escape verdict"
        rt_rows.append([f"b{r['hex']}", r["hex"], ctx, fl, fname,
                        "  v=" + r["emitted_token"], r["lib_read"],
                        tol + (f" ({msg})" if msg else ""),
                        f"value_bytes_preserved={r['byte_preserved']}", note])
for fl in FLAVORS:
    for r in key_sweeps[fl]:
        case = r["case"]
        if case.startswith("mc:"):
            slug = case[3:]
            hexid = r["hex"]
            fname = f"keys_{fl}/mc_{slug}.toml"
            ctx = "key_multi"
        else:
            hexid = r["hex"]
            fname = f"keys_{fl}/b{hexid}.toml"
            ctx = "key"
        tol, msg = oracle.get(fname, ("MISSING", ""))
        note = V110_WEIGHTLESS if fl == "v110" else ""
        if r["lib_read"] != "OK":
            note = "; ".join(x for x in (note, "library re-parse fails: output cannot be consumed by its own reader") if x)
        elif r["key_bytes_preserved"] == "false":
            note = "; ".join(x for x in (note, f"decoded key bytes {r['decoded_key_hex']} != input {hexid}") if x)
        rt_rows.append([case, hexid, ctx, fl, fname,
                        "  " + r["key_token"] + "=7", r["lib_read"],
                        tol + (f" ({msg})" if msg else ""),
                        f"key_bytes_preserved={r['key_bytes_preserved']}", note])
write_tsv(OUT / "roundtrip.tsv",
          ["case", "hex", "context", "flavor", "emitted_file", "emitted_doc",
           "lib_read", "tomllib_v100_oracle", "bytes_preserved", "note"], rt_rows)

# ------------------------------------------------------------ preservation.tsv
pres_rows = []
for fl in FLAVORS:
    for r in esc_sweeps[fl]:
        b, hexid = r["byte"], r["hex"]
        inp = hexid
        dec = r["decoded_hex"]
        libread = r["lib_read"]
        if libread != "OK":
            cat, note = "unknown", f"library re-parse failed: {libread}"
        elif r["byte_preserved"] == "true":
            cat, note = "byte_preserving", ""
        elif dec == "EF BF BD":
            cat, note = "lossy", "input byte re-decoded as U+FFFD replacement (Nim fastRuneAt maps lone UTF-8 lead bytes 0xC0-0xFD — 2- to 6-byte leads — to replRune U+FFFD; writer.nim:137 iterates runes())"
        else:
            try:
                scalar = bytes.fromhex(dec).decode("utf-8")
                cp = f"U+{ord(scalar):04X}"
            except Exception:
                cp = "?"
            cat, note = "value_preserving_only", f"raw byte interpreted as code point {cp}; decoded to its UTF-8 ({dec}) — bytes differ"
        pres_rows.append([b, hexid, fl, inp, dec, cat, note])
write_tsv(OUT / "preservation.tsv",
          ["byte", "hex", "flavor", "input_hex", "decoded_hex", "category", "note"],
          pres_rows)

# ------------------------------------------------------------------- summary
def count(rows, col, val):
    return sum(1 for r in rows if r[col] == val)

esc_inv_both = sum(1 for r in esc_rows if r[5] == "INVALID" and r[6] == "INVALID")
key_inv_both = sum(1 for r in key_rows if r[5] == "INVALID" and r[6] == "INVALID")
lossy = count(pres_rows, 5, "lossy")
print(f"escapes.tsv rows      : {len(esc_rows)} (invalid-in-both: {esc_inv_both})")
print(f"keys.tsv rows         : {len(key_rows)} (invalid-in-both: {key_inv_both})")
print(f"roundtrip.tsv rows    : {len(rt_rows)}")
print(f"preservation.tsv rows : {len(pres_rows)} (lossy: {lossy})")
