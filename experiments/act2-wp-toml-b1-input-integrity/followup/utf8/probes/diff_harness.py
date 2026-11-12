#!/usr/bin/env python3
"""Differential-verification harness: subject DFA (mirrored from parsed table)
vs CPython's codecs UTF-8 decoder, over exactly the same enumeration ranges the
Nim probe (dfa_probe.nim) covered with the real compiled implementation.

Verdict sources:
  V1 nim_batch : bitmap from subject's validateUTF8   (r123_batch.bin, ...)
  V2 nim_obj   : bitmap from subject's UTF8Validator push/valid/clear
  V3 py_mirror : DFA re-run in Python from table.json (parsed subject source)
  V4 codecs    : CPython bytes.decode('utf-8') strict
Checks: V1 == V2 == V3 == V4 for every sequence in R1-R5; plus confirmatory
R6 (full legal codepoint space) and R7 (explicit boundary/invalid sets).
"""
import json
import os
import sys
import time
from multiprocessing import Pool

RAW = "./experiments/act2-wp-toml-b1-input-integrity/followup/utf8/raw"
OUT = "/tmp/utf8diff/out"
TABLE = "/tmp/utf8diff/table.json"

T = json.load(open(TABLE))
CLS = T["byte_class"]
TR = T["transitions_row_major"]
assert len(CLS) == 256 and len(TR) % 16 == 0

R123_N = 256 + 65536 + 16777216          # 16,843,008
R4_N = 5 * 16777216                      # 83,886,080
R5_LEADS = [b for b in range(256) if not (0xF0 <= b <= 0xF4)]  # 251 leads
R5_PER = 776
R5_N = len(R5_LEADS) * R5_PER            # 194,776

def mirror_ok(seq):
    """Exact Python mirror of validateUTF8: state=0; state=table[256+state*16+table[b]]; accept iff state==0."""
    st = 0
    for b in seq:
        st = TR[16 * st + CLS[b]]
    return st == 0

def codec_ok(seq):
    try:
        seq.decode("utf-8")
        return 1
    except UnicodeDecodeError:
        return 0

def seq_for(kind, i):
    if kind == "r123":
        if i < 256:
            return bytes([i])
        if i < 65792:
            j = i - 256
            return bytes([j >> 8, j & 0xFF])
        j = i - 65792
        return bytes([(j >> 16) & 0xFF, (j >> 8) & 0xFF, j & 0xFF])
    if kind == "r4":
        return bytes([0xF0 + (i >> 24), (i >> 16) & 0xFF, (i >> 8) & 0xFF, i & 0xFF])
    if kind == "r5":
        lead = R5_LEADS[i // R5_PER]
        k = i % R5_PER
        if k < 256:
            return bytes([lead, k, 0x80, 0x80])
        if k < 512:
            return bytes([lead, 0x80, k - 256, 0xBF])
        if k < 768:
            return bytes([lead, 0xBF, 0x80, k - 512])
        m = k - 768
        return bytes([lead,
                      0x80 if (m & 4) else 0xBF,
                      0x80 if (m & 2) else 0xBF,
                      0x80 if (m & 1) else 0xBF])
    raise KeyError(kind)

def worker(job):
    kind, lo, hi = job
    dfa = bytearray()
    cod = bytearray()
    mism = []
    for i in range(lo, hi):
        s = seq_for(kind, i)
        d = 1 if mirror_ok(s) else 0
        c = codec_ok(s)
        dfa.append(d)
        cod.append(c)
        if d != c and len(mism) < 2000:
            mism.append((i, s.hex(), d, c))
    return kind, lo, bytes(dfa), bytes(cod), mism

def expand_bits(data, expect_len):
    """MSB-first bitmap -> bytes of 0/1 verdicts."""
    assert len(data) * 8 == expect_len, (len(data), expect_len)
    tab = [bytes(((b >> (7 - i)) & 1) for i in range(8)) for b in range(256)]
    return b"".join(map(tab.__getitem__, data))

def run_range(kind, n, pool, nim_batch, nim_obj, label):
    t0 = time.time()
    nproc_tasks = [(kind, lo, min(lo + 262144, n)) for lo in range(0, n, 262144)]
    dfa = bytearray(n)
    cod = bytearray(n)
    allm = []
    for k2, lo, d, c, m in pool.map(worker, nproc_tasks, chunksize=1):
        dfa[lo:lo + len(d)] = d
        cod[lo:lo + len(c)] = c
        allm.extend(m)
    dfa = bytes(dfa)
    cod = bytes(cod)
    nb = expand_bits(nim_batch, n)
    no = expand_bits(nim_obj, n)
    # chunked 3-way comparison (V1,V2,V3) + codecs (V4)
    CH = 4096
    diffs = {"nb_v3": 0, "no_v3": 0, "v3_v4": 0, "v1_v4": 0, "v2_v4": 0}
    diff_idx = []
    for off in range(0, n, CH):
        hi = min(off + CH, n)
        a, b, c2, d2 = nb[off:hi], no[off:hi], dfa[off:hi], cod[off:hi]
        eq_ab = a == b
        eq_ac = a == c2
        eq_cd = c2 == d2
        if eq_ab and eq_ac and eq_cd:
            continue
        for j in range(off, hi):
            x, y, z, w = nb[j], no[j], dfa[j], cod[j]
            if x != y or x != z or z != w:
                diffs["nb_v3"] += (x != z)
                diffs["no_v3"] += (x != y)
                diffs["v3_v4"] += (z != w)
                diffs["v1_v4"] += (x != w)
                diffs["v2_v4"] += (y != w)
                if len(diff_idx) < 5000:
                    diff_idx.append(j)
    res = {
        "range": label,
        "sequences": n,
        "dfa_accept_mirror_v3": sum(dfa),
        "codecs_accept_v4": sum(cod),
        "nim_batch_accept_v1": sum(nb),
        "nim_obj_accept_v2": sum(no),
        "diffs": diffs,
        "diff_examples": [
            {"index": j, "hex": seq_for(kind, j).hex(),
             "nim_batch_v1": nb[j], "nim_obj_v2": no[j],
             "py_mirror_v3": dfa[j], "codecs_v4": cod[j]}
            for j in diff_idx[:50]
        ],
        "worker_mismatch_records": allm[:5000],
        "worker_mismatch_count_reported": len(allm),
        "elapsed_s": round(time.time() - t0, 1),
    }
    with open(f"{RAW}/disagreements_{label}.csv", "w") as f:
        f.write("index,hex,nim_batch_v1,nim_obj_v2,py_mirror_v3,codecs_v4\n")
        for j in diff_idx:
            f.write(f"{j},{seq_for(kind, j).hex()},{nb[j]},{no[j]},{dfa[j]},{cod[j]}\n")
    return res, dfa, cod

def sanity_vectors():
    vecs = [
        (b"a", True), (b"\xc3\xa9", True), (b"\xf0\x9f\x98\x80", True),
        (b"\xf0\xa0\x80\x80", True), (b"\xed\x9f\xbf", True),
        (b"\x80", False), (b"\xc0\x80", False), (b"\xed\xa0\x80", False),
        (b"\xf4\x90\x80\x80", False), (b"\xf0\x80\x80\x80", False),
        (b"\xf5\x80\x80\x80", False), (b"\xc2", False),
    ]
    lines = ["vector,hex,py_mirror_v3,codecs_v4,expected_codec"]
    ok = True
    for s, exp in vecs:
        d, c = mirror_ok(s), codec_ok(s)
        ok &= (c == (1 if exp else 0)) and (d == c)
        lines.append(f"{s.decode('latin1')!r},{s.hex()},{d},{c},{int(exp)}")
    with open(f"{RAW}/known_vector_results.txt", "w") as f:
        f.write("\n".join(lines) + "\n")
    assert ok, "sanity vectors failed"
    print("sanity vectors: OK")

def main():
    os.makedirs(RAW, exist_ok=True)
    sanity_vectors()
    pool = Pool(processes=16)
    results = []

    # confirmatory R6: full legal codepoint space (canonical encodings)
    t0 = time.time()
    bad = []
    n6 = 0
    for cp in range(0x110000):
        if 0xD800 <= cp <= 0xDFFF:
            continue
        s = chr(cp).encode("utf-8")
        d = mirror_ok(s)
        n6 += 1
        if not d:
            bad.append(hex(cp))
    assert not bad, bad[:10]
    print(f"R6 codepoint space: {n6} scalars, all accepted by mirror DFA "
          f"({time.time()-t0:.1f}s)")

    # confirmatory R7: explicit invalid boundary sets (must all be rejected by both)
    t0 = time.time()
    invalid_sets = []
    for b2 in range(0xA0, 0xC0):          # surrogates U+D800..U+DFFF
        for b3 in range(0x80, 0xC0):
            invalid_sets.append(bytes([0xED, b2, b3]))
    for lead in (0xC0, 0xC1):             # 2-byte overlongs
        for b2 in range(0x80, 0xC0):
            invalid_sets.append(bytes([lead, b2]))
    for b2 in range(0x80, 0xA0):          # 3-byte overlongs (E0 80-9F xx)
        for b3 in range(0x80, 0xC0):
            invalid_sets.append(bytes([0xE0, b2, b3]))
    for b2 in range(0x80, 0x90):          # 4-byte overlongs (F0 80-8F xx xx)
        for b3 in range(0x80, 0xC0):
            for b4 in range(0x80, 0xC0):
                invalid_sets.append(bytes([0xF0, b2, b3, b4]))
    for b2 in range(0x90, 0xC0):          # > U+10FFFF (F4 90-BF xx xx)
        for b3 in range(0x80, 0xC0):
            for b4 in range(0x80, 0xC0):
                invalid_sets.append(bytes([0xF4, b2, b3, b4]))
    for lead in range(0xF5, 0x100):       # impossible leads F5..FF
        for b2 in range(0x80, 0xC0):
            invalid_sets.append(bytes([lead, b2]))
    bad = [s.hex() for s in invalid_sets if mirror_ok(s) or codec_ok(s)]
    assert not bad, bad[:10]
    print(f"R7 boundary/invalid sets: {len(invalid_sets)} sequences, all rejected by "
          f"mirror DFA and codecs ({time.time()-t0:.1f}s)")
    with open(f"{RAW}/boundary_sets_summary.txt", "w") as f:
        f.write(f"R6 legal codepoint space: {n6} scalars (U+0000..U+10FFFF minus "
                f"surrogates), canonical UTF-8 encodings, all accepted by mirror DFA.\n")
        f.write(f"R7 explicit invalid sets: {len(invalid_sets)} sequences (surrogate forms, "
                f"2/3/4-byte overlongs, >U+10FFFF forms, F5-FF leads), all rejected by "
                f"mirror DFA and by codecs.\n")

    nb = open(f"{OUT}/r123_batch.bin", "rb").read()
    no = open(f"{OUT}/r123_obj.bin", "rb").read()
    r, _, _ = run_range("r123", R123_N, pool, nb, no, "r123_len1to3")
    results.append(r)
    print(f"R1-R3 done: {json.dumps(r['diffs'])} "
          f"(dfa_acc={r['dfa_accept_mirror_v3']}, codecs_acc={r['codecs_accept_v4']}, "
          f"{r['elapsed_s']}s)")

    nb = open(f"{OUT}/r4f0f4_batch.bin", "rb").read()
    no = open(f"{OUT}/r4f0f4_obj.bin", "rb").read()
    r, _, _ = run_range("r4", R4_N, pool, nb, no, "r4_f0f4_leads")
    results.append(r)
    print(f"R4 done: {json.dumps(r['diffs'])} "
          f"(dfa_acc={r['dfa_accept_mirror_v3']}, codecs_acc={r['codecs_accept_v4']}, "
          f"{r['elapsed_s']}s)")

    nb = open(f"{OUT}/r5wrong_batch.bin", "rb").read()
    no = open(f"{OUT}/r5wrong_obj.bin", "rb").read()
    r, _, _ = run_range("r5", R5_N, pool, nb, no, "r5_wrong_leads")
    results.append(r)
    print(f"R5 done: {json.dumps(r['diffs'])} "
          f"(dfa_acc={r['dfa_accept_mirror_v3']}, codecs_acc={r['codecs_accept_v4']}, "
          f"{r['elapsed_s']}s)")

    with open(f"{RAW}/differential_summary.json", "w") as f:
        json.dump(results, f, indent=1)
    print("wrote differential_summary.json")

if __name__ == "__main__":
    main()
