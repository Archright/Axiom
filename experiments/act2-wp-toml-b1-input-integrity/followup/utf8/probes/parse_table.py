#!/usr/bin/env python3
"""Task 1: programmatically parse the DFA table out of the subject's
utf8_validate.nim — no hand transcription.

Parses the `utf8Table = [...]` literal, strips # comments, handles
`0'u8` suffixes and 0x hex literals, and verifies structural invariants.
Writes table.json to the deliverable dir.
"""
import json
import re
import sys

SUBJECT = "<workspace>/nim-toml-serialization"
SRC = SUBJECT + "/toml_serialization/private/utf8_validate.nim"
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/utf8diff/table.json"

text = open(SRC, encoding="utf-8").read()

# Pull the const block values + names exactly as written.
m_acc = re.search(r"UTF8_ACCEPT\*\s*=\s*(\d+)", text)
m_rej = re.search(r"UTF8_REJECT\*\s*=\s*(\d+)", text)
m_tbl = re.search(r"utf8Table\s*=\s*\[(.*?)\n\]", text, re.S)
assert m_acc and m_rej and m_tbl, "could not locate consts/table in source"

body = m_tbl.group(1)
body_nc = re.sub(r"#.*", "", body)          # strip trailing comments
toks = [t.strip() for t in body_nc.split(",") if t.strip()]
vals = []
for t in toks:
    if t.endswith("'u8"):
        t = t[:-3]
    vals.append(int(t, 0))                  # int(_, 0) handles 0x.. and dec

accept, reject = int(m_acc.group(1)), int(m_rej.group(1))
assert accept == 0 and reject == 1, (accept, reject)

n = len(vals)
assert n % 16 == 0, f"table length {n} not a multiple of 16"
n_states_total = n // 16                    # incl. the 16-row class block
classes = vals[:256]
trans = vals[256:]
n_states = len(trans) // 16

# Structural invariants of the documented layout:
#  - every byte maps to a class < 16 (else the 256 + state*16 + x index
#    could leave the transition sub-table)
max_cls = max(classes)
assert max_cls < 16, f"byte class {max_cls} >= 16 would overflow a state row"

#  - every reachable state index must stay inside the transition sub-table
state_vals = set(trans)
assert all(16 * s + max_cls < len(trans) for s in state_vals), \
    "some transition value indexes past the end of the table"

used_states = sorted(state_vals)
print(f"table length          : {n}")
print(f"byte-class entries    : 256")
print(f"transition entries    : {len(trans)} = {n_states} states x 16 classes")
print(f"states (values used)  : {used_states}")
print(f"accept / reject       : {accept} / {reject}")
print(f"index formula         : state' = table[256 + state*16 + class(byte)]")
print(f"max class             : {max_cls}")

# Dead-cell audit: classes 12..15 are unused by the class table, so the
# transition cells for those classes can never be reached.
class_used = sorted(set(classes))
dead_cells = [(s, c) for s in used_states for c in range(16) if c not in class_used]
print(f"classes used          : {class_used}")
print(f"dead transition cells : {len(dead_cells)} (classes never produced)")

out = {
    "source_file": "toml_serialization/private/utf8_validate.nim",
    "subject_commit": "4aa8e2223649fc0837c490a4acfca7b8b1e756f9",
    "table_length": n,
    "byte_class_entries": 256,
    "transition_entries": len(trans),
    "num_dfa_states": n_states,
    "states_used": used_states,
    "accept_state": accept,
    "reject_state": reject,
    "index_formula": "state' = table[256 + state*16 + class]; class = table[byte]",
    "byte_class": classes,
    "transitions_row_major": trans,
    "dead_transition_cells": dead_cells,
}
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(out, f, indent=1)
print(f"wrote {OUT}")
