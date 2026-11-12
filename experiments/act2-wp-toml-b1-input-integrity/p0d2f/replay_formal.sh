#!/usr/bin/env bash
# replay_formal.sh — p0d2f D2 formal slice 수용(acceptance) 재생 하니스.
#
# 슬라이스의 6런(defect/control × cold1/cold2/path)을 재실행하고 조건
# C1·C1a·C2·C3·C4·C5를 판정해 ACCEPTANCE verdict를 낸다. 모든 산출물은
# $EXP/runs_r/ 아래에 기록된다(gitignored).
#
# 전제: nim-toml-serialization @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9,
# 변이 variant.patch 적용 후 d2kernels.nim sha256 == d15f8a98…b26875.
# cwd=$ROOT 고정은 replay_harness_config_quirks.md Q1(config.nims 상속),
# 클린 트리 전제는 Q2(드리프트 게이트)의 요구다.
#
# 종료 코드: 0=PASS, 1=FAIL(조건 미충족), 3=INCOMPLETE(전제조건·재생 불가).
#
# 참고: 본 스크립트는 루트에서 3단계 아래(experiments/act2-wp-toml-b1-input-integrity/
# p0d2f)이므로 ROOT는 고정 단계 수 대신 `.axiom_root` 앵커 상승 탐색으로
# 확정한다(단계 수 하드코딩은 재배치 시 루트를 벗어난다).
set -euo pipefail

EXP="$(cd "$(dirname "$0")" && pwd)"

# ── ROOT: .axiom_root 앵커 상승 탐색 (Axiom3 루트 검증 포함) ──
ROOT=""
_d="$EXP"
for _ in 1 2 3 4 5 6 7 8; do
  if [ -f "$_d/.axiom_root" ]; then ROOT="$_d"; break; fi
  _d="$(dirname "$_d")"
done
if [ -z "$ROOT" ] || [ ! -x "$ROOT/bin/ax" ]; then
  echo "[replay_formal] Axiom3 루트(.axiom_root)를 $EXP 상위에서 찾지 못했다."
  echo "ACCEPTANCE: INCOMPLETE (repo root not resolvable from script location)"
  exit 3
fi
AX="$ROOT/bin/ax"
if [ ! -x "$AX" ]; then
  echo "[replay_formal] bin/ax 가 없다. 루트에서 재빌드할 것: cd \"$ROOT\" && make build"
  echo "ACCEPTANCE: INCOMPLETE (bin/ax missing — run: make build)"
  exit 3
fi

SOURCE_CLONE="<workspace>/nim-toml-serialization"
PIN="4aa8e2223649fc0837c490a4acfca7b8b1e756f9"
VARIANT_SHA="d15f8a98bf2c32dcfa58a20fed6a3ed5f0f3dd65d4173e6e429c51aa76b26875"
DEFECT_FN="d2HexEscapeAppendLen"
CONTROL_FN="d2Utf8AppendLen"
# P6b 단계에서 sed로 채워지는 핀 대상 digest (미충분 시 C3는 런 간 동등성만 비교)
EXPECTED_DEFECT_DIGEST="55ac23c419fe2155bb4232511580eaf6f11c0e8d90f1353d2f6d066d5872e65c"
EXPECTED_CONTROL_DIGEST="8549934738719edb3b5e55e03cfa489a8b006f5de742e60fb17e23226bab92fd"

RUNS="$EXP/runs_r"
SUBJECT_R1="$EXP/env_r/subject"
SUBJECT_R2="$EXP/env_r2/subject"

# ── Step 0: fail-closed 전제조건 ──
pre_fail() { echo "[replay_formal] 전제조건 실패: $1"; echo "ACCEPTANCE: INCOMPLETE ($1)"; exit 3; }

[ -d "$SOURCE_CLONE/.git" ] || pre_fail "source clone missing: $SOURCE_CLONE"
src_head="$(git -C "$SOURCE_CLONE" rev-parse HEAD)"
[ "$src_head" = "$PIN" ] || pre_fail "source clone HEAD $src_head != pin $PIN"
[ -z "$(git -C "$SOURCE_CLONE" status --porcelain)" ] || pre_fail "source clone porcelain not empty"

if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
  echo "[replay_formal] Axiom3 트리가 클린하지 않다 — 재생 드리프트 게이트가 실패한다 (quirks Q2):"
  git -C "$ROOT" status --porcelain
  echo "ACCEPTANCE: INCOMPLETE (tree not clean — replay drift gate will fail)"
  exit 3
fi
command -v z3 >/dev/null 2>&1 || pre_fail "z3 not on PATH"
command -v nim >/dev/null 2>&1 || pre_fail "nim not on PATH"

mkdir -p "$RUNS"
{
  echo "z3: $(z3 --version)"
  echo "nim: $(nim --version | head -1)"
  echo "ax: $(sha256sum "$AX" | cut -c1-16)"
} > "$RUNS/toolchain.txt"

# ── Step 1: 주체 materialization (clone → pin checkout → variant.patch) ──
materialize() { # <env_dir>
  local env="$1" got
  rm -rf "$env"
  mkdir -p "$env"
  git clone --quiet "$SOURCE_CLONE" "$env/subject"
  git -C "$env/subject" checkout -q "$PIN"
  git -C "$env/subject" apply "$EXP/variant.patch"
  got="$(sha256sum "$env/subject/d2kernels.nim" | cut -d' ' -f1)"
  if [ "$got" != "$VARIANT_SHA" ]; then
    pre_fail "d2kernels.nim sha256 $got != expected $VARIANT_SHA"
  fi
}
materialize "$EXP/env_r"
materialize "$EXP/env_r2"

# ── Step 2: 런 실행 (exit 코드는 관측값 — set -e 예외 구간) ──
run_ax() { # <name> <state_dir(abs)> <vault_dir(abs)> <subject_root> <target_func>
  local name="$1" state="$2" vault="$3" subject="$4" fn="$5"
  mkdir -p "$state/data" "$vault" "$RUNS"
  cp "$ROOT/data/verification_scope.lock" "$state/data/verification_scope.lock"
  set +e
  ( cd "$ROOT" && \
    AXIOM_STATE_DIR="$state" \
    AXIOM_PROVE_VAULT_DIR="$vault" \
    "$AX" prove --project "$subject" --target "d2kernels.nim::$fn" \
  ) > "$RUNS/$name.out" 2> "$RUNS/$name.err"
  echo "$?" > "$RUNS/$name.exit"
  set -e
}

run_ax defect_cold1  "$EXP/state_r1" "$EXP/vault_r_defect_cold1"  "$SUBJECT_R1" "$DEFECT_FN"
run_ax control_cold1 "$EXP/state_r2" "$EXP/vault_r_control_cold1" "$SUBJECT_R1" "$CONTROL_FN"
run_ax defect_cold2  "$EXP/state_r3" "$EXP/vault_r_defect_cold2"  "$SUBJECT_R1" "$DEFECT_FN"
run_ax control_cold2 "$EXP/state_r4" "$EXP/vault_r_control_cold2" "$SUBJECT_R1" "$CONTROL_FN"
run_ax defect_path   "$EXP/state_r5" "$EXP/vault_r_defect_path"   "$SUBJECT_R2" "$DEFECT_FN"
run_ax control_path  "$EXP/state_r6" "$EXP/vault_r_control_path"  "$SUBJECT_R2" "$CONTROL_FN"

# ── 관측 헬퍼 ──
exit_of() { cat "$RUNS/$1.exit"; }
traj_of() { local s="$1" f="$2"; for c in ax_prove_trajectory.jsonl ax_proof_state.json; do [ -f "$EXP/$s/logs/$c" ] && grep -Eq "$f" "$EXP/$s/logs/$c" && { echo "$EXP/$s/logs/$c"; return 0; }; done; return 1; }
digest_of() { # <state_dir> → canonicalRunDigest (없으면 빈 문자열)
  sed -nE 's/.*"canonicalRunDigest": *"([a-f0-9]{64})".*/\1/p' "$EXP/$1/logs/ax_proof_state.json" 2>/dev/null | head -1 || true
}
manifest_has_red_row() { # <manifest> <fn> — functionName 행 이후 certRed 확인 (공백 유무 무관)
  grep -A 3 -E "\"functionName\": *\"$2\"" "$1" 2>/dev/null | grep -Eq '"status": *"certRed"'
}
control_cert_of() { # <vault_dir> → 인증서 JSON 경로(manifest 제외), 없으면 빈 문자열
  find "$1" -maxdepth 1 -name '*.json' ! -name 'manifest.json' 2>/dev/null | head -1 || true
}

D1="$(digest_of state_r1)"; D2="$(digest_of state_r3)"; DP="$(digest_of state_r5)"
C1D="$(digest_of state_r2)"; C2D="$(digest_of state_r4)"; CP="$(digest_of state_r6)"

# ── Step 3: 조건 판정 ──

# C1: 결함 반증 — exit 1 ∧ trajectory FAILED ∧ vault manifest certRed
c1=OBS; c1ev=""
[ "$(exit_of defect_cold1)" = "1" ] || { c1=NOT; c1ev="exit=$(exit_of defect_cold1) != 1"; }
if [ "$c1" = "OBS" ]; then
  t1="$(traj_of state_r1 'd2HexEscapeAppendLen.*([Ff]ailed|FAILED)')" || { c1=NOT; c1ev="trajectory: no d2HexEscapeAppendLen failed entry in state_r1"; }
  [ -n "$t1" ] && c1ev="trajectory: $t1"
fi
if [ "$c1" = "OBS" ]; then
  m1="$EXP/vault_r_defect_cold1/manifest.json"
  if manifest_has_red_row "$m1" "$DEFECT_FN"; then c1ev="$c1ev; manifest: $m1 certRed row"
  else c1=NOT; c1ev="manifest: no certRed row for $DEFECT_FN in $m1"; fi
fi

# C1a: 재생 합의 — BUG_FOUND (미관측이고 C1은 관측이면 전체 INCOMPLETE 루트)
c1a=NOT; c1aev="no BUG_FOUND in runs_r/defect_cold1.err (replay agreement absent)"
if grep -q 'BUG_FOUND' "$RUNS/defect_cold1.err" 2>/dev/null; then
  c1a=OBS; c1aev="BUG_FOUND in runs_r/defect_cold1.err"
elif grep -q 'BUG_FOUND' "$EXP/state_r1/logs/ax_prove_trajectory.jsonl" 2>/dev/null; then
  c1a=OBS; c1aev="BUG_FOUND in state_r1 trajectory"
elif grep -q 'rvUnavailable' "$RUNS/defect_cold1.err" 2>/dev/null; then
  c1aev="replay unavailable: $(grep -m1 -o 'rvUnavailable:[^;]*' "$RUNS/defect_cold1.err" || echo 'rvUnavailable')"
fi

# C2: 대조 검증 — exit 0 ∧ 인증서 status ∧ functionName
c2=NOT; c2ev=""
cert1="$(control_cert_of "$EXP/vault_r_control_cold1")"
if [ "$(exit_of control_cold1)" = "0" ] && [ -n "$cert1" ] \
   && grep -Eq '"functionName": *"d2Utf8AppendLen"' "$cert1" \
   && grep -Eq '"status": *"cert(LeanVerified|Z3Candidate)"' "$cert1"; then
  c2=OBS; c2ev="exit=0; cert: $cert1 ($(grep -m1 -oE '"status": *"[A-Za-z]*"' "$cert1"))"
else
  c2ev="exit=$(exit_of control_cold1); cert=$cert1"
fi

# C3: cold 결정론 — 런 간 digest 동등성 (+ 핀 digest가 채워졌으면 고정값 비교)
c3=NOT; c3ev=""
if [ -n "$D1" ] && [ "$D1" = "$D2" ] && [ -n "$C1D" ] && [ "$C1D" = "$C2D" ]; then
  c3=OBS
  c3ev="defect $D1 == $D2; control $C1D == $C2D"
  if [ "$EXPECTED_DEFECT_DIGEST" != "__DEFECT_DIGEST__" ] && [ "$D1" != "$EXPECTED_DEFECT_DIGEST" ]; then
    c3=NOT; c3ev="defect digest $D1 != pinned $EXPECTED_DEFECT_DIGEST"
  fi
  if [ "$EXPECTED_CONTROL_DIGEST" != "__CONTROL_DIGEST__" ] && [ "$C1D" != "$EXPECTED_CONTROL_DIGEST" ]; then
    c3=NOT; c3ev="control digest $C1D != pinned $EXPECTED_CONTROL_DIGEST"
  fi
  [ "$EXPECTED_DEFECT_DIGEST" = "__DEFECT_DIGEST__" ] && c3ev="$c3ev; note: __DEFECT_DIGEST__ placeholder unfilled — run-to-run equality only"
else
  c3ev="digest mismatch/absent: defect($D1,$D2) control($C1D,$C2D)"
fi

# C4: 경로 독립 — env_r vs env_r2 digest 동등성 + 인증서 바이트 비교(있으면)
c4=NOT; c4ev=""
if [ -n "$DP" ] && [ "$DP" = "$D1" ] && [ -n "$CP" ] && [ "$CP" = "$C1D" ]; then
  c4=OBS; c4ev="defect_path $DP == defect_cold1 $D1; control_path $CP == control_cold1 $C1D"
  certp="$(control_cert_of "$EXP/vault_r_control_path")"
  if [ -n "$certp" ] && [ -n "$cert1" ]; then
    if cmp -s "$certp" "$cert1"; then c4ev="$c4ev; cert byte-identical"
    else c4=NOT; c4ev="cert differs: $certp vs $cert1"; fi
  fi
else
  c4ev="digest mismatch/absent: defect($D1,$DP) control($C1D,$CP)"
fi

# C5: 증거 완전성 — 인증서 필드 8종 + 툴체인 기록
c5=NOT; c5ev=""
if [ -n "$cert1" ]; then
  miss=""
  for k in modulePath functionName status verificationTier irHash inputHash identityDigest leanSource; do
    grep -q "\"$k\"" "$cert1" || miss="$miss $k"
  done
  if [ -z "$miss" ] && grep -q 'z3:' "$RUNS/toolchain.txt" && grep -q 'nim:' "$RUNS/toolchain.txt" && grep -q 'ax:' "$RUNS/toolchain.txt"; then
    c5=OBS; c5ev="cert fields complete; toolchain: $(tr '\n' '|' < "$RUNS/toolchain.txt")"
  else
    c5ev="cert missing:${miss:-none}; toolchain.txt: $RUNS/toolchain.txt"
  fi
else
  c5ev="no control cert to inspect"
fi

# ── 판정 ──
echo "=== 조건 판정표 (p0d2f replay_formal) ==="
printf '%-6s %-14s %s\n' "COND" "STATE" "EVIDENCE"
printf '%-6s %-14s %s\n' "C1" "$c1" "${c1ev:-defect refutation: exit=1 ∧ trajectory FAILED ∧ manifest certRed}"
printf '%-6s %-14s %s\n' "C1a" "$c1a" "$c1aev"
printf '%-6s %-14s %s\n' "C2" "$c2" "${c2ev:-control verified: exit=0 ∧ certLeanVerified/Z3 ∧ d2Utf8AppendLen}"
printf '%-6s %-14s %s\n' "C3" "$c3" "$c3ev"
printf '%-6s %-14s %s\n' "C4" "$c4" "$c4ev"
printf '%-6s %-14s %s\n' "C5" "$c5" "$c5ev"
echo "digests: defect_cold1=$D1 defect_cold2=$D2 defect_path=$DP"
echo "digests: control_cold1=$C1D control_cold2=$C2D control_path=$CP"

verdict_fail() { echo "ACCEPTANCE: FAIL (missing: $*)"; exit 1; }

if [ "$c1" = "OBS" ] && [ "$c2" = "OBS" ] && [ "$c3" = "OBS" ] && [ "$c4" = "OBS" ] && [ "$c5" = "OBS" ]; then
  if [ "$c1a" = "OBS" ]; then
    echo "ACCEPTANCE: PASS"
    exit 0
  fi
  echo "ACCEPTANCE: INCOMPLETE (replay unavailable, refutation observed)"
  exit 3
fi
missing=""
[ "$c1" != "OBS" ] && missing="$missing C1"
[ "$c2" != "OBS" ] && missing="$missing C2"
[ "$c3" != "OBS" ] && missing="$missing C3"
[ "$c4" != "OBS" ] && missing="$missing C4"
[ "$c5" != "OBS" ] && missing="$missing C5"
[ "$c1a" != "OBS" ] && missing="$missing C1a"
verdict_fail "$missing"
