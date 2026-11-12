#!/usr/bin/env bash
# replay_agent.sh — p0d2g 에이전트 수직 슬라이스 수용(acceptance) 재생 하니스.
#
# pristine 주체 materialization → 결함 런 + 콜드 재실행을 재수행하고 조건
# C1·C2·C3·C4·C5를 판정해 ACCEPTANCE verdict를 낸다. 모든 산출물은
# $EXP/runs_r/ 아래에 기록된다(gitignored — 기록된 원본 runs/는 덮지 않는다).
#
# 전제: nim-toml-serialization @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9
# (pristine — 변이 패치 없음. 채택 명세 S2는 오버레이 바인딩
# `config/spec/toml_d2_agent_spec.json`이 캐리어를 신디사이즈한다),
# lexer.nim sha256 == 19d69eed…33f4d. cwd=$ROOT 고정은
# replay_harness_config_quirks.md Q1(config.nims 상속), 클린 트리 전제는
# Q2(드리프트 게이트)의 요구다.
#
# 종료 코드: 0=PASS, 1=FAIL(조건 미충족), 3=INCOMPLETE(전제조건·재생 불가).
#
# 참고: ROOT는 `.axiom_root` 앵커 상승 탐색으로 확정한다(단계 수 하드코딩은
# 재배치 시 루트를 벗어난다).
set -euo pipefail

EXP="$(cd "$(dirname "$0")" && pwd)"

# ── ROOT: .axiom_root 앵커 상승 탐색 ──
ROOT=""
_d="$EXP"
for _ in 1 2 3 4 5 6 7 8; do
  if [ -f "$_d/.axiom_root" ]; then ROOT="$_d"; break; fi
  _d="$(dirname "$_d")"
done
if [ -z "$ROOT" ]; then
  echo "[replay_agent] Axiom3 루트(.axiom_root)를 $EXP 상위에서 찾지 못했다."
  echo "ACCEPTANCE: INCOMPLETE (repo root not resolvable from script location)"
  exit 3
fi
AX="$ROOT/bin/ax"
if [ ! -x "$AX" ]; then
  echo "[replay_agent] bin/ax 가 없다. 루트에서 재빌드할 것: cd \"$ROOT\" && make build"
  echo "ACCEPTANCE: INCOMPLETE (bin/ax missing — run: make build)"
  exit 3
fi

SOURCE_CLONE="<workspace>/nim-toml-serialization"
PIN="4aa8e2223649fc0837c490a4acfca7b8b1e756f9"
LEXER_SHA="19d69eed84f74c51fa1784b2e71a4525abc8d2b8aa854c567565d2d603133f4d"
# Phase E 기록 콜드 digest (state_e1 == state_e3) — FORMAL_EXPERIMENT.md Result 4.
# 주의: 이 값은 기록 시점의 bin/ax 빌드·툴체인에 민감하다. 런 간 동등성이
# 유지된 채 이 상수와 어긋나면 비결정이 아니라 바이너리 빌드 드리프트(재빌드한
# bin/ax가 기록 바이너리와 다름)를 뜻한다 — 판정은 C3 근거문에 명시된다.
RECORDED_DIGEST="3516fcfcb4d891f99caed95d55405e29a8032371b5ba73028dee03e598cced6a"
DEFECT_TARGET="toml_serialization/lexer.nim::scanString"
DEFECT_FN="scanString"
CONTROL_FN="d2CommentGateReject"

RUNS="$EXP/runs_r"
SUBJECT="$EXP/env_r/subject"

# ── Step 0: fail-closed 전제조건 ──
pre_fail() { echo "[replay_agent] 전제조건 실패: $1"; echo "ACCEPTANCE: INCOMPLETE ($1)"; exit 3; }

[ -d "$SOURCE_CLONE/.git" ] || pre_fail "source clone missing: $SOURCE_CLONE"
src_head="$(git -C "$SOURCE_CLONE" rev-parse HEAD)"
[ "$src_head" = "$PIN" ] || pre_fail "source clone HEAD $src_head != pin $PIN"
[ -z "$(git -C "$SOURCE_CLONE" status --porcelain)" ] || pre_fail "source clone porcelain not empty"

if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
  echo "[replay_agent] Axiom3 트리가 클린하지 않다 — 재생 드리프트 게이트가 실패한다 (quirks Q2):"
  git -C "$ROOT" status --porcelain
  echo "ACCEPTANCE: INCOMPLETE (tree not clean — replay drift gate will fail)"
  exit 3
fi
command -v z3 >/dev/null 2>&1 || pre_fail "z3 not on PATH"
command -v nim >/dev/null 2>&1 || pre_fail "nim not on PATH"
[ -f "$ROOT/data/verification_scope.lock" ] || pre_fail "scope lock missing: $ROOT/data/verification_scope.lock"

mkdir -p "$RUNS"
{
  echo "z3: $(z3 --version)"
  echo "nim: $(nim --version | head -1)"
  echo "ax: $(sha256sum "$AX" | cut -c1-16)"
} > "$RUNS/toolchain.txt"

# ── Step 1: pristine 주체 materialization (clone → pin checkout → lexer sha 검증) ──
materialize() {
  local got
  rm -rf "$EXP/env_r"
  mkdir -p "$EXP/env_r"
  git clone --quiet "$SOURCE_CLONE" "$SUBJECT"
  git -C "$SUBJECT" checkout -q "$PIN"
  [ "$(git -C "$SUBJECT" rev-parse HEAD)" = "$PIN" ] || pre_fail "materialized subject HEAD != pin $PIN"
  [ -z "$(git -C "$SUBJECT" status --porcelain)" ] || pre_fail "materialized subject porcelain not empty"
  got="$(sha256sum "$SUBJECT/toml_serialization/lexer.nim" | cut -d' ' -f1)"
  [ "$got" = "$LEXER_SHA" ] || pre_fail "lexer.nim sha256 $got != expected $LEXER_SHA"
}
materialize

# ── Step 2: 런 실행 (exit 코드는 관측값 — set -e 예외 구간) ──
run_ax() { # <name> <state_dir(abs)> <vault_dir(abs)>
  local name="$1" state="$2" vault="$3"
  mkdir -p "$state/data" "$vault" "$RUNS"
  cp "$ROOT/data/verification_scope.lock" "$state/data/verification_scope.lock"
  set +e
  ( cd "$ROOT" && \
    AXIOM_STATE_DIR="$state" \
    AXIOM_PROVE_VAULT_DIR="$vault" \
    "$AX" prove --project "$SUBJECT" --target "$DEFECT_TARGET" \
  ) > "$RUNS/$name.out" 2> "$RUNS/$name.err"
  echo "$?" > "$RUNS/$name.exit"
  set -e
}
run_ax defect      "$EXP/state_r1" "$EXP/vault_r1"
run_ax defect_cold "$EXP/state_r2" "$EXP/vault_r2"

# ── 관측 헬퍼 ──
exit_of() { cat "$RUNS/$1.exit"; }
digest_of() { # <state_dir> → canonicalRunDigest (없으면 빈 문자열)
  sed -nE 's/.*"canonicalRunDigest": *"([a-f0-9]{64})".*/\1/p' "$EXP/$1/logs/ax_proof_state.json" 2>/dev/null | head -1 || true
}
# trajectory skReport unitEvidenceRefs — "<module>::<fn>":{"claimId":…,"claimOutcome":"…"}
traj_outcome() { # <state_dir> <module::fn> <outcome>
  grep -Eq "\"$2\": *\\{[^}]*\"claimOutcome\": *\"$3\"" "$EXP/$1/logs/ax_prove_trajectory.jsonl" 2>/dev/null
}
manifest_row() { # <manifest> <fn> <status> — functionName 행 이후 status 확인
  grep -A 3 -E "\"functionName\": *\"$2\"" "$1" 2>/dev/null | grep -Eq "\"status\": *\"$3\""
}

D1="$(digest_of state_r1)"; D2="$(digest_of state_r2)"
M1="$EXP/vault_r1/manifest.json"

# ── Step 3: 조건 판정 ──

# C1: 결함 반증 — exit 1 ∧ trajectory scanString clDisproved ∧ manifest certRed 행
c1=OBS; c1ev=""
[ "$(exit_of defect)" = "1" ] || { c1=NOT; c1ev="exit=$(exit_of defect) != 1"; }
if [ "$c1" = "OBS" ]; then
  if traj_outcome state_r1 "toml_serialization/lexer.nim::$DEFECT_FN" clDisproved; then
    c1ev="trajectory: $DEFECT_FN clDisproved (state_r1)"
  else
    c1=NOT; c1ev="trajectory: no $DEFECT_FN clDisproved in state_r1"
  fi
fi
if [ "$c1" = "OBS" ]; then
  if manifest_row "$M1" "$DEFECT_FN" certRed; then
    c1ev="$c1ev; manifest: $M1 certRed row"
  else
    c1=NOT; c1ev="manifest: no certRed row for $DEFECT_FN in $M1"
  fi
fi

# C2: 대조 증명 — 같은 런 안에서 census 선정 대조 커널 clProved + certZ3Candidate
c2=OBS; c2ev=""
if traj_outcome state_r1 "toml_serialization/lexer.nim::$CONTROL_FN" clProved; then
  c2ev="trajectory: $CONTROL_FN clProved (state_r1 — same run)"
else
  c2=NOT; c2ev="trajectory: no $CONTROL_FN clProved in state_r1"
fi
if [ "$c2" = "OBS" ]; then
  if manifest_row "$M1" "$CONTROL_FN" certZ3Candidate; then
    c2ev="$c2ev; manifest: $M1 certZ3Candidate row"
  else
    c2=NOT; c2ev="manifest: no certZ3Candidate row for $CONTROL_FN in $M1"
  fi
fi

# C3: 콜드 결정론 — 런 간 digest 동등성 ∧ 기록 digest 고정 비교
c3=NOT; c3ev=""
if [ -n "$D1" ] && [ "$D1" = "$D2" ]; then
  if [ "$D1" = "$RECORDED_DIGEST" ]; then
    c3=OBS; c3ev="defect $D1 == defect_cold $D2 == recorded $RECORDED_DIGEST"
  else
    c3ev="run-to-run equal ($D1) but != recorded $RECORDED_DIGEST — binary-build sensitivity: rebuilt bin/ax or toolchain drift, not run nondeterminism"
  fi
else
  c3ev="digest mismatch/absent: defect($D1) cold($D2)"
fi

# C4: 재생 합의 — BUG_FOUND / scanString ce-replay (P4-bool 갭이 열려 있으면 미관측이 예상)
c4=NOT; c4ev="no BUG_FOUND in runs_r/defect.err nor state_r1 trajectory, no [$DEFECT_FN] ce-replay (P4 bool-binding pipeline gap — see PIPELINE_GAP_P4_BOOL_BINDING.md)"
if grep -q 'BUG_FOUND' "$RUNS/defect.err" 2>/dev/null \
   || grep -q 'BUG_FOUND' "$EXP/state_r1/logs/ax_prove_trajectory.jsonl" 2>/dev/null; then
  c4=OBS; c4ev="BUG_FOUND observed"
elif grep -Eq "\[ce-replay\] *$DEFECT_FN" "$RUNS/defect.err" 2>/dev/null; then
  c4=OBS; c4ev="ce-replay observed for $DEFECT_FN (BUG_FOUND absent)"
fi

# C5: 증거 완전성 — 채택·발견·바인딩·증거 파일 + 툴체인 기록
c5=OBS; c5ev=""; miss=""
[ -s "$EXP/AGENT_SPEC.md" ] || miss="$miss AGENT_SPEC.md"
[ -s "$EXP/discovery/agentA_raw.md" ] || miss="$miss discovery/agentA_raw.md"
[ -s "$EXP/discovery/agentB_raw.md" ] || miss="$miss discovery/agentB_raw.md"
[ -s "$ROOT/config/spec/toml_d2_agent_spec.json" ] || miss="$miss overlay(toml_d2_agent_spec.json)"
[ -s "$ROOT/docs/spec/toml_d2_agent_binding_contract.md" ] || miss="$miss contract(toml_d2_agent_binding_contract.md)"
[ -s "$EXP/evidence/defect/e_replay_harness_c0.nim" ] || miss="$miss evidence/defect/e_replay_harness_c0.nim"
manifest_row "$M1" "$DEFECT_FN" certRed || miss="$miss manifest:$DEFECT_FN certRed"
manifest_row "$M1" "$CONTROL_FN" certZ3Candidate || miss="$miss manifest:$CONTROL_FN certZ3Candidate"
grep -q 'z3:' "$RUNS/toolchain.txt" && grep -q 'nim:' "$RUNS/toolchain.txt" && grep -q 'ax:' "$RUNS/toolchain.txt" || miss="$miss toolchain.txt"
if [ -n "$miss" ]; then
  c5=NOT; c5ev="missing:$miss"
else
  c5ev="spec+discovery+overlay+contract+harness+manifest rows present; toolchain: $(tr '\n' '|' < "$RUNS/toolchain.txt")"
fi

# ── 판정 ──
echo "=== 조건 판정표 (p0d2g replay_agent) ==="
printf '%-4s %-6s %s\n' "COND" "STATE" "EVIDENCE"
printf '%-4s %-6s %s\n' "C1" "$c1" "${c1ev:-defect refutation: exit=1 ∧ trajectory clDisproved ∧ manifest certRed}"
printf '%-4s %-6s %s\n' "C2" "$c2" "${c2ev:-control proof: same-run d2CommentGateReject clProved ∧ certZ3Candidate}"
printf '%-4s %-6s %s\n' "C3" "$c3" "${c3ev:-cold determinism: digest run-to-run ∧ recorded equality}"
printf '%-4s %-6s %s\n' "C4" "$c4" "$c4ev"
printf '%-4s %-6s %s\n' "C5" "$c5" "$c5ev"
echo "digests: defect=$D1 defect_cold=$D2 recorded=$RECORDED_DIGEST"
echo "=== 4축 판정 (기록된 기계 관측 — 본 스크립트는 축 점수를 재도출하지 않는다) ==="
printf '%-10s %-9s %s\n' "축" "판정" "근거"
printf '%-10s %-9s %s\n' "발견" "PARTIAL" "진짜 후보 7+7(3수렴); 기정담(\\xHH 디코드 의미론) 양측 미발견 — 기록값"
printf '%-10s %-9s %s\n' "명세생성" "OBSERVED" "S2 fail-closed 수용: 의무 7, 캐리어 2/2 eligible"
printf '%-10s %-9s %s\n' "검증정확성" "OBSERVED" "차동 clDisproved+clProved 동일 런 + 콜드 결정론 MATCH"
# 증거신뢰성 축은 C4의 라이브 관측에서 파생 (2026-10-18 정합 수정: 기록 스냅샷 행이
# P4+하니스 수리 후 라이브 상태와 어긋나서 — 축 점수를 재도출하는 유일한 행이 됨).
# 발견 축은 여전히 기록값(스크립트는 발견 단계를 재실행하지 않는다).
ev_axis="$([ "$c4" = "OBS" ] && echo "OBSERVED" || echo "PARTIAL")"
ev_ev="$([ "$c4" = "OBS" ] && echo "원본 재생 합치·BUG_FOUND 관측(C4 OBS)" || echo "재생·BUG_FOUND 미관측 — 근원: PIPELINE_GAP_P4_BOOL_BINDING.md")"
printf '%-10s %-9s %s\n' "증거신뢰성" "$ev_axis" "$ev_ev"

verdict_fail() { echo "ACCEPTANCE: FAIL (missing: $*)"; exit 1; }

if [ "$c1" = "OBS" ] && [ "$c2" = "OBS" ] && [ "$c3" = "OBS" ] && [ "$c4" = "OBS" ] && [ "$c5" = "OBS" ]; then
  echo "ACCEPTANCE: PASS"
  exit 0
fi
if [ "$c1" = "OBS" ] && [ "$c2" = "OBS" ] && [ "$c3" = "OBS" ] && [ "$c5" = "OBS" ] && [ "$c4" = "NOT" ]; then
  echo "ACCEPTANCE: INCOMPLETE (replay/promotion unavailable — P4 bool-binding pipeline gap, see PIPELINE_GAP_P4_BOOL_BINDING.md)"
  exit 3
fi
missing=""
[ "$c1" != "OBS" ] && missing="$missing C1"
[ "$c2" != "OBS" ] && missing="$missing C2"
[ "$c3" != "OBS" ] && missing="$missing C3"
[ "$c4" != "OBS" ] && missing="$missing C4"
[ "$c5" != "OBS" ] && missing="$missing C5"
verdict_fail "$missing"
