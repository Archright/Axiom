#!/usr/bin/env bash
# replay_rt.sh - P0-D2-RT roundtrip-identity replay (D2: encoder != decoder for
# TOML 1.1 \xHH escapes) against nim-toml-serialization pinned at
# 4aa8e2223649fc0837c490a4acfca7b8b1e756f9 (verification subject = this exact
# commit; the script fails closed if the clone HEAD differs or the working
# tree is not clean).
#
# Re-runs the 3-way experiment (baseline / defect \xHH / unicode \uXXXX):
# 1. materializes the pinned subject (git-archive export; clone untouched) and
#    the pinned dependency tree into /tmp/p0d2_rt_env,
# 2. verifies per-file identity (probes/p0d2_rt_deps.SHA256SUMS) and input
#    identity (inputs/rt_sha256sums.txt),
# 3. rebuilds probes/p0d2_rt_probe.nim (Nim 2.2.10, neutral cwd) and
#    probes/p0d2_canon.nim (imports Axiom3's SSOT canonical_projection),
# 4. runs the three cases -> $RUN_DIR/{baseline,defect,unicode}.{out,err,exit},
# 5. writes $RUN_DIR/rt_evidence.json (deterministic generator; only
#    collection.generatedAt and runtimeMeta.runId vary between runs - both are
#    in the normative volatile-key list of
#    src/core/utils/canonical_projection.nim / docs/spec/productization_contract.md §6),
# 6. canonicalizes via the SSOT implementation -> $RUN_DIR/rt_canonical.json
#    and $RUN_DIR/rt_canonical.sha256 (canonicalProjectionHash).
#
# Determinism contract (P0-4 correction): the product contract requires
# projection-hash equality (canonicalProjectionHashEqual,
# docs/spec/productization_contract.md:63; §6 :194 "semantic equality 정의 —
# raw artifact byte equality 아님"), NOT full-envelope byte equality. Two runs
# on the same pinned inputs therefore claim byte identity ONLY for the pinned
# paths ({baseline,defect,unicode}.{out,err,exit}, build.log,
# rt_canonical.json, rt_canonical.sha256); rt_evidence.json may differ in the
# contract volatile keys only (src/core/utils/canonical_projection.nim:18-31 —
# here collection.generatedAt and runtimeMeta.runId), and
# canonicalProjectionHash must be EQUAL despite those differences. Step 8
# enforces exactly this split when a sibling run dir exists.
# Binaries live under /tmp only; the subject repo is never mutated.
set -euo pipefail

EXP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AXIOM3_DIR="$(cd "$EXP_DIR/../../.." && pwd)"
RUN_DIR="${RUN_DIR:-$EXP_DIR/raw_rt}"
ENV_DIR="${ENV_DIR:-/tmp/p0d2_rt_env}"
CLEAN="${P0D2_RT_CLEAN:-0}"
SUBJECT_CLONE="${SUBJECT_CLONE:-<workspace>/nim-toml-serialization}"
SUBJECT_SHA="4aa8e2223649fc0837c490a4acfca7b8b1e756f9"
NIM="${NIM:-$HOME/.choosenim/toolchains/nim-2.2.10/bin/nim}"
CHECKSUMS_PKG="${CHECKSUMS_PKG:-$HOME/.nimble/pkgs2/checksums-0.2.2-6357ab195ec23e0e0a54d4d8b5e0212456bf899e}"

# Dependency pins (same recorded build pin set as the p0d2 consumer-contrast
# slice; the subject repo has no lockfile, so pins are committed here and
# file-verified by probes/p0d2_rt_deps.SHA256SUMS on every replay).
STEW_PIN="83eb1157963b7f49351dbdd858355fa990bbe23c"
SERIALIZATION_PIN="4092500cea76154576539371709ae801afbd2a9d"
FASTSTREAMS_PIN="50889cd16ec8771106cdd0eeea460039e8571e06"
RESULTS_PIN="df8113dda4c2d74d460a8fa98252b0b771bf1f27"

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- 0. fail-closed environment identity -------------------------------------
ACTUAL_SHA="$(git -C "$SUBJECT_CLONE" rev-parse HEAD)"
[ "$ACTUAL_SHA" = "$SUBJECT_SHA" ] || fail "subject clone HEAD $ACTUAL_SHA != pinned $SUBJECT_SHA"
[ -z "$(git -C "$SUBJECT_CLONE" status --porcelain)" ] || fail "subject clone working tree is not clean"
[ -x "$NIM" ] || fail "nim not found: $NIM"
[ -d "$CHECKSUMS_PKG" ] || fail "checksums nimble pkg not found: $CHECKSUMS_PKG (needed by core/crypto/hash_kernel)"
[ -f "$EXP_DIR/probes/p0d2_rt_deps.SHA256SUMS" ] || fail "missing probes/p0d2_rt_deps.SHA256SUMS"

fetch_dep() { # <repo> <sha> <name> [owner]
  local repo="$1" sha="$2" name="$3" owner="${4:-status-im}" tmp
  if [ -d "$ENV_DIR/deps/$name" ] && [ -n "$(ls -A "$ENV_DIR/deps/$name" 2>/dev/null)" ]; then
    return 0
  fi
  mkdir -p "$ENV_DIR/deps/$name"
  tmp="$(mktemp -d)"
  curl -sfL "https://codeload.github.com/$owner/$repo/tar.gz/$sha" -o "$tmp/$repo.tgz"
  tar xzf "$tmp/$repo.tgz" -C "$tmp"
  mv "$tmp/${repo}-${sha}"/* "$ENV_DIR/deps/$name/"
  rm -rf "$tmp"
  echo "fetched $owner/$repo @ ${sha:0:12} -> deps/$name"
}

if [ "$CLEAN" = "1" ]; then rm -rf "$ENV_DIR"; fi
mkdir -p "$ENV_DIR/deps" "$ENV_DIR/bin" "$ENV_DIR/build" "$ENV_DIR/inputs" "$RUN_DIR"

# --- 1. subject pin materialization (read-only export) -----------------------
if [ ! -f "$ENV_DIR/deps/toml_serialization/toml_serialization/lexer.nim" ]; then
  mkdir -p "$ENV_DIR/deps/toml_serialization"
  git -C "$SUBJECT_CLONE" archive "$SUBJECT_SHA" | tar -x -C "$ENV_DIR/deps/toml_serialization"
  echo "exported toml_serialization @ ${SUBJECT_SHA:0:12} from $SUBJECT_CLONE"
fi
fetch_dep nim-stew          "$STEW_PIN"         stew
fetch_dep nim-serialization "$SERIALIZATION_PIN" serialization
fetch_dep nim-faststreams   "$FASTSTREAMS_PIN"  faststreams
fetch_dep nim-results       "$RESULTS_PIN"      results arnetheduck

# --- 2. identity checks -------------------------------------------------------
( cd "$ENV_DIR" && sha256sum -c "$EXP_DIR/probes/p0d2_rt_deps.SHA256SUMS" --quiet ) \
  || fail "dependency identity check failed"
cp "$EXP_DIR"/inputs/rt_baseline.toml "$EXP_DIR"/inputs/rt_defect.toml "$EXP_DIR"/inputs/rt_unicode.toml "$ENV_DIR/inputs/"
( cd "$EXP_DIR/inputs" && sha256sum -c rt_sha256sums.txt --quiet ) || fail "input identity check failed"

# --- 3. build probe (neutral cwd; project configs skipped) --------------------
cp "$EXP_DIR/probes/p0d2_rt_probe.nim" "$ENV_DIR/probe.nim"
rm -rf "$ENV_DIR/build/nimcache_rt" "$ENV_DIR/bin/p0d2_rt_probe"
{
  echo "nim: $("$NIM" --version | head -1)"
  echo "subject: $SUBJECT_SHA"
  echo "ulimit -s: $(ulimit -s)"
} > "$RUN_DIR/build.log"
( cd "$ENV_DIR" && "$NIM" c --warnings:off --hints:off --mm:orc \
  --skipUserCfg --skipParentCfg --skipProjCfg \
  --nimcache:"$ENV_DIR/build/nimcache_rt" \
  --path:"$ENV_DIR/deps/serialization" \
  --path:"$ENV_DIR/deps/toml_serialization" \
  --path:"$ENV_DIR/deps/stew" \
  --path:"$ENV_DIR/deps/faststreams" \
  --path:"$ENV_DIR/deps/results" \
  --out:"$ENV_DIR/bin/p0d2_rt_probe" \
  "$ENV_DIR/probe.nim" ) >> "$RUN_DIR/build.log" 2>&1

# --- 4. build canonicalizer (Axiom3 SSOT canonical_projection) -----------------
cp "$EXP_DIR/probes/p0d2_canon.nim" "$ENV_DIR/canon.nim"
rm -rf "$ENV_DIR/build/nimcache_canon" "$ENV_DIR/bin/p0d2_canon"
( cd "$ENV_DIR" && "$NIM" c --warnings:off --hints:off --mm:orc \
  --skipUserCfg --skipParentCfg --skipProjCfg \
  --nimcache:"$ENV_DIR/build/nimcache_canon" \
  --path:"$AXIOM3_DIR/src" \
  --path:"$CHECKSUMS_PKG" \
  --out:"$ENV_DIR/bin/p0d2_canon" \
  "$ENV_DIR/canon.nim" ) >> "$RUN_DIR/build.log" 2>&1

# --- 5. the three cases --------------------------------------------------------
for c in baseline defect unicode; do
  set +e
  ( cd "$ENV_DIR" && "$ENV_DIR/bin/p0d2_rt_probe" "$c" "inputs/rt_$c.toml" ) \
    > "$RUN_DIR/$c.out" 2> "$RUN_DIR/$c.err"
  echo "$?" > "$RUN_DIR/$c.exit"
  set -e
done

# --- 6. evidence artifact (deterministic; volatile: generatedAt, runId) --------
GEN_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RUN_ID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
PLATFORM="$(uname -s -r -m)"
python3 - "$EXP_DIR" "$ENV_DIR" "$RUN_DIR" "$SUBJECT_SHA" "$GEN_AT" "$RUN_ID" "$PLATFORM" <<'PY'
import hashlib, json, os, sys

exp_dir, env_dir, run_dir, subject_sha, gen_at, run_id, platform = sys.argv[1:8]

def sha256_file(p):
    with open(p, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()

def read(p):
    with open(p, "r", encoding="utf-8") as f:
        return f.read()

# fail-closed: every case must have succeeded and reproduced the pinned bytes.
# Assertions are layout-independent (field-value hex, identity booleans, and
# the decisive escape bytes 5C 78 45 39 = "\xE9" inside the encoder output);
# the encoder's key layout/order is recorded, never assumed.
EXPECT = {
    "baseline": ["decode_outcome: SUCCESS",
                 "decoded_value_bytes_hex: 68 65 6C 6C 6F 20 77 6F 72 6C 64",
                 "authored_decode_matches_intent_value: true",
                 "roundtrip_identity_holds: true",
                 "ref_utf8_U00E9_hex: C3 A9"],
    "defect":   ["decode_outcome: SUCCESS",
                 "decoded_value_bytes_hex: 63 61 66 E9",
                 "decoded_value_utf8: INVALID-UTF8(first-bad-offset=3)",
                 "decoded_ctrl_bytes_hex: 80",
                 "authored_decode_matches_intent_value: false",
                 "roundtrip_identity_holds: false",
                 "encoder_output_bytes_hex: ",
                 "ref_utf8_U00E9_hex: C3 A9"],
    "unicode":  ["decode_outcome: SUCCESS",
                 "decoded_value_bytes_hex: 63 61 66 C3 A9",
                 "decoded_value_utf8: well-formed-UTF8",
                 "decoded_ctrl_bytes_hex: C2 80",
                 "authored_decode_matches_intent_value: true",
                 "roundtrip_identity_holds: false",
                 "encoder_output_bytes_hex: ",
                 "ref_utf8_U00E9_hex: C3 A9"],
}
# the defect/unicode encoder must emit the \xE9 escape sequence (bytes
# 5C 78 45 39) for U+00E9 - the encoder half of the contradiction
ENCODER_SUBSTR = {
    "baseline": None,
    "defect": "5C 78 45 39",
    "unicode": "5C 78 45 39",
}
runs = {}
for case in ["baseline", "defect", "unicode"]:
    exit_code = int(read(os.path.join(run_dir, case + ".exit")).strip())
    out_path = os.path.join(run_dir, case + ".out")
    out_text = read(out_path)
    missing = [m for m in EXPECT[case] if m not in out_text]
    assert exit_code == 0, f"{case}: exit={exit_code}"
    assert not missing, f"{case}: expected lines missing from probe output: {missing}"
    if ENCODER_SUBSTR[case] is not None:
        assert ENCODER_SUBSTR[case] in out_text, \
            f"{case}: encoder output lacks {ENCODER_SUBSTR[case]} (\\xHH emission)"
    runs[case] = {
        "exitCode": exit_code,
        "stdoutDigest": "sha256:" + sha256_file(out_path),
        "stderrDigest": "sha256:" + sha256_file(os.path.join(run_dir, case + ".err")),
        "stdout": out_text,
    }

def in_sha(name):
    return "sha256:" + sha256_file(os.path.join(exp_dir, "inputs", name))

def dep_sha(rel):
    return "sha256:" + sha256_file(os.path.join(env_dir, "deps", "toml_serialization", rel))

SCOPE = ("toml-flavor=Toml;version=1.1.0;"
         "runtimeFlags=Toml_v110_Flags{TomlInlineTableNewline,TomlInlineTableTrailingComma,"
         "TomlHexEscape,TomlHourMinute,TomlStrictComma};options=default(init, no overrides);"
         "callForm=Toml.decode(text,T)/Toml.encode(value) (nim-serialization generic; "
         "TomlWriter.init and TomlReader.init both union flags+flavorRuntimeFlags: "
         "writer.nim:30-40, reader.nim:53-66)")
REPO = "nim-toml-serialization"
def subj(case, digest):
    return f"{REPO}@{subject_sha}/probe=p0d2_rt_probe/input=rt_{case}.toml:{digest}"

sub_b = subj("baseline", in_sha("rt_baseline.toml").split(":")[1])
sub_d = subj("defect", in_sha("rt_defect.toml").split(":")[1])
sub_u = subj("unicode", in_sha("rt_unicode.toml").split(":")[1])

build_log_digest = "sha256:" + sha256_file(os.path.join(run_dir, "build.log"))

evidence = {
    "schema": "ax.p0d2.rt-evidence/v1",
    "invariantId": "roundtrip.identity",
    "key": "roundtrip.identity",
    "scope": SCOPE,
    "subject": sub_d,
    "verdict": "UNKNOWN",
    "classification": {
        "label": "제한된 실험 증거 (limited experimental evidence)",
        "관측": (
            "고정 입력(inputs/rt_baseline.toml, rt_defect.toml, rt_unicode.toml; "
            "sha256 고정)에서 문자열 왕복 불변식(roundtrip.identity) 위반이 "
            "재현됨 - defect 입력에서 decode(encode(intent)) != intent "
            "(raw byte E9 != UTF-8 C3 A9), raw_rt/run{1,2}에 바이트 수준 재현."
        ),
        "판정": (
            "UNKNOWN - 제품 계약의 모순 규칙(docs/spec/productization_contract.md:168"
            ": same key AND same scope AND same subject AND 상충 value -> UNKNOWN)에 "
            "따른 판정."
        ),
        "상태·tier 쌍": {
            "status": "certRed",
            "verificationTier": "vtNone",
            "tierLabel": "none",
            "비고": (
                "certRed + vtNone을 계약 어휘에 따라 투영한 제한적 실험 결과 - "
                "계약 산출 어휘 그대로: certRed는 SAT/반례 전용 "
                "(src/core/types/verification_tier.nim:98), 반례에 solver 증거가 "
                "없으면 tier = tierFromResults(false,false) = vtNone "
                "(verification_tier.nim:32-40,139-141; DECISION-0630 - tier는 저장 "
                "증거의 순수 함수), status/verificationTier는 저장 증거에서 투영된다 "
                "(src/verification/cert_writer.nim:303,362)."
            ),
        },
        "범위 제한": (
            "deriveClaim을 통한 claim authority(src/core/trusted/claim_authority.nim:17-20"
            " - claim은 캡처된 solver 증거로부터만 파생; certificate/status는 절대 "
            "deriveClaim 입력이 아님), identityDigest, trustCommitId 결속 "
            "(docs/spec/productization_contract.md:304-305)을 갖춘 정식 계약 적합 "
            "인서트가 아님. D2의 반례는 solverSat -> derivePipelineClaim 경로가 "
            "아니라 Nim 왕복 probe의 고정 입력 관측에서 왔다. 따라서 상태·tier 쌍은 "
            "계약 어휘의 투영이며, 이 슬라이스의 어떤 산출물도 계약이 발행하는 "
            "형식 인서트로 표시·소비되어서는 안 된다. tierCounts는 단일 모순 "
            "artifact에 존재하지 않는다(§7b 미적용)."
        ),
    },
    "contractOutput": {
        "관측 결과": (
            "D2 reproduced at nim-toml-serialization@4aa8e22: the encoder "
            "(writer.nim:131-163 writeValue, TomlHexEscape active by default via "
            "writer.nim:30-40) emits U+00E9 as the codepoint escape \\xE9 "
            "(encoder_output bytes 22 63 61 66 5C 78 45 39 22); the decoder "
            "(lexer.nim:416-430 scanHexEscape, res.add char(code) at lexer.nim:429) "
            "decodes the authored \\xE9 to the RAW BYTE E9 "
            "(decoded_value = 63 61 66 E9, invalid UTF-8) instead of U+00E9's UTF-8 "
            "encoding C3 A9. decode(encode(intent)) != intent on this path "
            "(roundtrip_identity_holds: false) - roundtrip.identity violated. "
            "The \\u00E9 form decodes correctly to 63 61 66 C3 A9 via scanUnicode "
            "(lexer.nim:399-415): the correct decoder path exists in the same lexer, "
            "but the default encoder never emits it for U+0080..U+00FF."
        ),
        "판정": "UNKNOWN",
        "사유": (
            "Expected-vs-observed conflict: under key=roundtrip.identity, the same "
            "scope (Toml flavor 'Toml', v1.1.0, runtime flags Toml_v110_Flags incl. "
            "TomlHexEscape, default options, call form Toml.decode/Toml.encode) and "
            "the same subject (pinned commit + probe + defect input), the contract "
            "expects decode(encode(intent)) == intent (TOML v1.1.0 defines \\xHH as "
            "U+00HH; strings are sequences of Unicode characters), while the pinned "
            "build observably yields decode(encode(intent)) != intent with the raw "
            "byte E9 in place of C3 A9. Per docs/spec/productization_contract.md:168 "
            "(same key AND same scope AND same subject AND conflicting value -> "
            "UNKNOWN), the verdict function returns UNKNOWN. This UNKNOWN is the "
            "contract's verdict FOR an observed contradiction, not 'insufficient "
            "evidence': the contradiction itself is fully observed, byte-exactly, "
            "and reproducibly (see commands + output digests)."
        ),
        "증거": {
            "inputs": {
                "baseline": {"sha256": in_sha("rt_baseline.toml"),
                              "bytesHex": None},
                "defect": {"sha256": in_sha("rt_defect.toml"), "bytesHex": None},
                "unicode": {"sha256": in_sha("rt_unicode.toml"), "bytesHex": None},
            },
            "decisiveBytes": {
                "defect_decoded_value_hex": "63 61 66 E9 (raw byte 0xE9; INVALID UTF-8)",
                "unicode_decoded_value_hex": "63 61 66 C3 A9 (U+00E9 correct UTF-8 via scanUnicode)",
                "encoder_output_bytes_hex_defect": runs["defect"]["stdout"].split("encoder_output_bytes_hex: ")[1].split("\n")[0],
                "encoder_output_bytes_hex_unicode": runs["unicode"]["stdout"].split("encoder_output_bytes_hex: ")[1].split("\n")[0],
                "roundtrip_value_bytes_hex_defect": runs["defect"]["stdout"].split("roundtrip_value_bytes_hex: ")[1].split("\n")[0],
                "roundtrip_value_bytes_hex_unicode": runs["unicode"]["stdout"].split("roundtrip_value_bytes_hex: ")[1].split("\n")[0],
                "ref_utf8_U00E9_hex": "C3 A9 (independent std/unicode oracle)",
                "ref_utf8_U0080_hex": "C2 80",
                "defect_ctrl_decoded_hex": "80 (raw byte 0x80; unicode-path control: C2 80)",
            },
            "reproductionConditions": {
                "command": "bash experiments/act2-wp-toml-b1-input-integrity/p0d2/replay_rt.sh",
                "runs": runs,
                "rawArtifacts": "p0d2/raw_rt/ (rt_ prefixed run dirs)",
            },
        },
    },
    "assuranceTier": {
        "tier": "vtNone",
        "label": "none",
        "enum": "VerificationTier (src/core/types/verification_tier.nim: vtNone/vtZ3Only/vtLeanOnly/vtDual/vtKInduction/vtUfAbstract)",
        "grounding": (
            "tierFromEvidence(CertificateEvidence(z3Passed=false, leanVerified=false)) "
            "= vtNone per verification_tier.nim:139-141 (tierFromEvidence -> "
            "tierFromResults) and the exhaustive truth table at verification_tier.nim:32-40 "
            "(DECISION-0630: tier is a PURE function of stored evidence; status may "
            "never exceed evidence). This refutation carries NO Z3 unsat and NO Lean "
            "kernel artifact - its evidentiary procedure is a deterministic local "
            "byte-level replay (commands + exit codes + SHA-256 output digests, "
            "pinned commit + toolchain). A concrete counterexample refutes; it does "
            "not verify, so no solver tier is claimed."
        ),
    },
    "observations": [
        {"key": "roundtrip.identity", "scope": SCOPE, "subject": sub_d,
         "value": "expected: decode(encode(intent)) == intent; '\\xE9' denotes U+00E9 and must decode to the UTF-8 sequence C3 A9 (TOML v1.1.0; README.md:64-69 implements v1.1.0, README.md:78-80 enables \\xHH by default)"},
        {"key": "roundtrip.identity", "scope": SCOPE, "subject": sub_d,
         "value": "observed: decode('caf\\xE9') = 63 61 66 E9 (raw byte, invalid UTF-8) != 63 61 66 C3 A9; decode(encode(intent)) != intent (encoder emits \\xE9, lexer scanHexEscape inserts the raw byte)"},
        {"key": "roundtrip.identity", "scope": SCOPE, "subject": sub_b,
         "value": "observed: escape-free ASCII input roundtrips identically (baseline sanity gate; decode_outcome SUCCESS, roundtrip_identity_holds: true)"},
        {"key": "roundtrip.identity", "scope": SCOPE, "subject": sub_u,
         "value": "observed: decode('caf\\u00E9') = 63 61 66 C3 A9 (correct UTF-8 via scanUnicode, lexer.nim:399-415) and ctrl '\\u0080' -> C2 80; the decoder path is correct - the violation on this subject is the encoder's re-encoding of the same values to \\xHH (roundtrip_identity_holds: false)"},
        {"key": "roundtrip.identity", "scope": SCOPE, "subject": sub_b,
         "value": "expected: decode(encode(intent)) == intent; escape-free ASCII input must roundtrip identically (same rule applied to the baseline subject so its expected/observed pair is complete)"},
        {"key": "roundtrip.identity", "scope": SCOPE, "subject": sub_u,
         "value": "expected: decode(encode(intent)) == intent; '\\u00E9' denotes U+00E9 and must decode to the UTF-8 sequence C3 A9 (TOML v1.1.0), so the observed \\xHH re-encoding conflicts under the same rule (same rule applied to the unicode subject so its expected/observed pair is complete)"},
    ],
    "contradictionRule": "same key AND same scope AND same subject AND conflicting value -> UNKNOWN (docs/spec/productization_contract.md:168); rows 1-2 above are the conflicting pair (rows 5-6 replicate the expected row under the baseline/unicode subjects so each case's expected/observed pair is complete; observed rows 3-4 do not conflict with their expected rows on their own subject)",
    "commands": [
        {"cmd": "bash experiments/act2-wp-toml-b1-input-integrity/p0d2/replay_rt.sh",
         "exitCode": 0, "outputDigest": build_log_digest,
         "outputArtifacts": ["baseline.out", "defect.out", "unicode.out",
                              "baseline.err", "defect.err", "unicode.err",
                              "baseline.exit", "defect.exit", "unicode.exit",
                              "build.log"]},
        {"cmd": "cd $P0D2_RT_ENV && nim c --warnings:off --hints:off --mm:orc --skipUserCfg --skipParentCfg --skipProjCfg --nimcache:$P0D2_RT_ENV/build/nimcache_rt --path:$P0D2_RT_ENV/deps/serialization --path:$P0D2_RT_ENV/deps/toml_serialization --path:$P0D2_RT_ENV/deps/stew --path:$P0D2_RT_ENV/deps/faststreams --path:$P0D2_RT_ENV/deps/results --out:$P0D2_RT_ENV/bin/p0d2_rt_probe $P0D2_RT_ENV/probe.nim",
         "exitCode": 0, "outputDigest": build_log_digest},
        {"cmd": "cd $P0D2_RT_ENV && nim c --warnings:off --hints:off --mm:orc --skipUserCfg --skipParentCfg --skipProjCfg --nimcache:$P0D2_RT_ENV/build/nimcache_canon --path:<Axiom3>/src --path:<nimble-pkgs2>/checksums-0.2.2-6357ab195ec23e0e0a54d4d8b5e0212456bf899e --out:$P0D2_RT_ENV/bin/p0d2_canon $P0D2_RT_ENV/canon.nim",
         "exitCode": 0, "outputDigest": build_log_digest},
        {"cmd": "cd $P0D2_RT_ENV && $P0D2_RT_ENV/bin/p0d2_rt_probe baseline inputs/rt_baseline.toml",
         "exitCode": runs["baseline"]["exitCode"], "outputDigest": runs["baseline"]["stdoutDigest"]},
        {"cmd": "cd $P0D2_RT_ENV && $P0D2_RT_ENV/bin/p0d2_rt_probe defect inputs/rt_defect.toml",
         "exitCode": runs["defect"]["exitCode"], "outputDigest": runs["defect"]["stdoutDigest"]},
        {"cmd": "cd $P0D2_RT_ENV && $P0D2_RT_ENV/bin/p0d2_rt_probe unicode inputs/rt_unicode.toml",
         "exitCode": runs["unicode"]["exitCode"], "outputDigest": runs["unicode"]["stdoutDigest"]},
    ],
    "canonicalization": {
        "tool": "p0d2_canon (probes/p0d2_canon.nim)",
        "ssot": "src/core/utils/canonical_projection.nim canonicalProjectionHash (single implementation; volatile-key list per docs/spec/productization_contract.md §6)",
        "cmd": "$P0D2_RT_ENV/bin/p0d2_canon <RUN_DIR>/rt_evidence.json <RUN_DIR>/rt_canonical.json -> rt_canonical.sha256",
        "note": "the canon transform is not a commands[] row: its output digest is a function of this evidence file itself (self-reference); identity is attested by rt_canonical.sha256 beside this file and by the two-run comparison in RT_EXPERIMENT.md",
    },
    "sources": [
        {"file": "toml_serialization/writer.nim", "lines": "30-40", "symbol": "TomlWriter.init",
         "sha256": dep_sha("toml_serialization/writer.nim"), "repoRef": subject_sha},
        {"file": "toml_serialization/writer.nim", "lines": "131-163", "symbol": "writeValue(TomlWriter, string)",
         "sha256": dep_sha("toml_serialization/writer.nim"), "repoRef": subject_sha},
        {"file": "toml_serialization/lexer.nim", "lines": "399-415", "symbol": "scanUnicode",
         "sha256": dep_sha("toml_serialization/lexer.nim"), "repoRef": subject_sha},
        {"file": "toml_serialization/lexer.nim", "lines": "416-430", "symbol": "scanHexEscape",
         "sha256": dep_sha("toml_serialization/lexer.nim"), "repoRef": subject_sha},
        {"file": "toml_serialization/reader.nim", "lines": "53-66", "symbol": "TomlReader.init",
         "sha256": dep_sha("toml_serialization/reader.nim"), "repoRef": subject_sha},
        {"file": "toml_serialization/format.nim", "lines": "24-36", "symbol": "Toml_v110_Flags/flavorRuntimeFlags",
         "sha256": dep_sha("toml_serialization/format.nim"), "repoRef": subject_sha},
        {"file": "toml_serialization.nim", "lines": "22-24", "symbol": "Toml.setReader/Toml.setWriter",
         "sha256": dep_sha("toml_serialization.nim"), "repoRef": subject_sha},
        {"file": "tests/test_decoder.nim", "lines": "156", "symbol": "Toml.decode(rawToml, Example)",
         "sha256": dep_sha("tests/test_decoder.nim"), "repoRef": subject_sha},
        {"file": "tests/test_encoder.nim", "lines": "190", "symbol": "Toml.encode(v)",
         "sha256": dep_sha("tests/test_encoder.nim"), "repoRef": subject_sha},
    ],
    "environment": {
        "target": {
            "repo": "status-im/nim-toml-serialization",
            "commit": subject_sha,
            "introductionRange": "7352976..4aa8e22 (provenance note only; the verification subject is the single commit above)",
            "versionDeclared": "nimble 0.2.18; TOML flavor Toml = v1.1.0 (format.nim:37-38, README.md:64-69)",
            "materialization": "git -C <clone> archive <commit> | tar -x (clone untouched; git status --porcelain empty before and after)",
        },
        "nim": {"path": "$HOME/.choosenim/toolchains/nim-2.2.10/bin/nim", "versionLine": read(os.path.join(run_dir, "build.log")).splitlines()[0]},
        "dependencies": {
            "pins": {
                "nim-serialization": "4092500cea76154576539371709ae801afbd2a9d",
                "nim-faststreams": "50889cd16ec8771106cdd0eeea460039e8571e06",
                "nim-stew": "83eb1157963b7f49351dbdd858355fa990bbe23c",
                "nim-results": "df8113dda4c2d74d460a8fa98252b0b771bf1f27 (arnetheduck)",
            },
            "manifest": "probes/p0d2_rt_deps.SHA256SUMS (sha256 -c on every replay; subject repo has no nimble.lock)",
            "canonToolDeps": "Axiom3 src + nimble checksums-0.2.2-6357ab195ec23e0e0a54d4d8b5e0212456bf899e",
        },
        "buildFlags": "--warnings:off --hints:off --mm:orc --skipUserCfg --skipParentCfg --skipProjCfg --nimcache:$P0D2_RT_ENV/build/nimcache_rt --path:<5 pinned dep dirs> --out:$P0D2_RT_ENV/bin/p0d2_rt_probe (neutral cwd $P0D2_RT_ENV)",
        "toml": {
            "flavor": "Toml",
            "version": "1.1.0",
            "runtimeFlags": "Toml_v110_Flags = {TomlInlineTableNewline, TomlInlineTableTrailingComma, TomlHexEscape, TomlHourMinute, TomlStrictComma}",
            "options": "default (Format.init; no overrides; both reader and writer union flavorRuntimeFlags)",
            "callForm": {"decode": "Toml.decode(text: string, RtConf)", "encode": "Toml.encode(intent: RtConf): string"},
        },
        "platform": platform,
        "stackLimitKB": read(os.path.join(run_dir, "build.log")).split("ulimit -s: ")[1].strip(),
    },
    "collection": {
        "collector": "p0d2-rt-replay (replay_rt.sh)",
        "method": "deterministic-local-replay",
        "generatedAt": gen_at,
    },
    "runtimeMeta": {
        # machine/run-scoped values only - entirely excluded from the canonical
        # payload by the SSOT canonicalizer (runtimeMeta envelope + volatile keys)
        "runId": run_id,
    },
}

# fill input byte hex
for case in ["baseline", "defect", "unicode"]:
    with open(os.path.join(exp_dir, "inputs", f"rt_{case}.toml"), "rb") as f:
        raw = f.read()
    evidence["contractOutput"]["증거"]["inputs"][case]["bytesHex"] = " ".join(f"{b:02X}" for b in raw)

out_path = os.path.join(run_dir, "rt_evidence.json")
with open(out_path, "w", encoding="utf-8") as f:
    f.write(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
print("wrote", out_path)
PY

# --- 7. canonical projection via the Axiom3 SSOT implementation ----------------
"$ENV_DIR/bin/p0d2_canon" "$RUN_DIR/rt_evidence.json" "$RUN_DIR/rt_canonical.json" \
  > "$RUN_DIR/rt_canonical.sha256"

# --- 8. two-run determinism check (P0-4 correction) -----------------------------
# The contract requires projection-hash equality (canonicalProjectionHashEqual,
# docs/spec/productization_contract.md:63; §6 :194 "semantic equality 정의 —
# raw artifact byte equality 아님"), NOT full-envelope byte equality. Byte
# identity is claimed ONLY for the pinned paths below; rt_evidence.json may
# differ in the contract volatile keys only (the single normative exclusion
# list, src/core/utils/canonical_projection.nim:18-31 — here
# collection.generatedAt and runtimeMeta.runId; the runtimeMeta envelope is
# excluded whole at :45-46), and canonicalProjectionHash must be EQUAL despite
# those differences.
PINNED_PATHS="baseline.out baseline.err baseline.exit defect.out defect.err defect.exit unicode.out unicode.err unicode.exit build.log rt_canonical.json rt_canonical.sha256"
COMPARE_DIR="${P0D2_COMPARE_DIR:-}"
if [ -z "$COMPARE_DIR" ]; then
  case "$(basename "$RUN_DIR")" in
    run1) c="$(dirname "$RUN_DIR")/run2" ;;
    run2) c="$(dirname "$RUN_DIR")/run1" ;;
    *)    c="" ;;
  esac
  [ -n "$c" ] && [ -f "$c/rt_evidence.json" ] && COMPARE_DIR="$c"
fi
if [ -n "$COMPARE_DIR" ]; then
  det_fail=0
  for f in $PINNED_PATHS; do
    if ! cmp -s "$RUN_DIR/$f" "$COMPARE_DIR/$f"; then
      echo "BYTE-DIFF on pinned path: $f"
      det_fail=1
    fi
  done
  python3 - "$RUN_DIR/rt_evidence.json" "$COMPARE_DIR/rt_evidence.json" <<'PY' || det_fail=1
import json, sys
VOLATILE = [("collection", "generatedAt"), ("runtimeMeta", "runId")]
a = json.load(open(sys.argv[1], encoding="utf-8"))
b = json.load(open(sys.argv[2], encoding="utf-8"))
for sect, key in VOLATILE:
    va = a.get(sect, {}).pop(key, None)
    vb = b.get(sect, {}).pop(key, None)
    print(f"volatile {sect}.{key}: run={va} | prev={vb}")
rest_a = json.dumps(a, sort_keys=True, ensure_ascii=False)
rest_b = json.dumps(b, sort_keys=True, ensure_ascii=False)
if rest_a != rest_b:
    print("FAIL: rt_evidence.json differs OUTSIDE the volatile keys "
          "collection.generatedAt / runtimeMeta.runId", file=sys.stderr)
    sys.exit(1)
print("volatile-only diff OK")
PY
  h_cur="$(sed -n 's/^canonicalProjectionHash: //p' "$RUN_DIR/rt_canonical.sha256")"
  h_prev="$(sed -n 's/^canonicalProjectionHash: //p' "$COMPARE_DIR/rt_canonical.sha256")"
  if [ -z "$h_cur" ] || [ "$h_cur" != "$h_prev" ]; then
    echo "HASH-DIFF: canonicalProjectionHash $h_cur vs $h_prev"
    det_fail=1
  fi
  if [ "$det_fail" = 0 ]; then
    echo "determinism check PASS vs $(basename "$COMPARE_DIR"): 12 pinned paths byte-identical, volatile-only evidence diff, canonicalProjectionHash equal ($h_cur)"
  else
    fail "determinism check FAILED vs $(basename "$COMPARE_DIR")"
  fi
else
  echo "single-run mode: two-run comparison skipped (no sibling run dir; set P0D2_COMPARE_DIR to enable)"
fi

echo "replay_rt complete: $RUN_DIR"
