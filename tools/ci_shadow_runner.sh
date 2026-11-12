#!/usr/bin/env bash
# ci_shadow_runner.sh — CI ExecutionPlan Rollout Phase A (Shadow)
#
# Baseline frozen at eaed53d8a (docs/reports/experiment_acceleration_baseline_eaed53d8a.md).
# Contract: docs/spec/ci_execution_plan_rollout.md
#
# Shadow mode = 기존 full verification 유지 + Selection/ExecutionPlan 생성·저장 +
#   Project(Full, Selected) vs plan-driven 실행 결과의 등가 관측 (ci.yml 미수정).
# v1 관측 단위: 두 prove 로그의 per-symbol "status=ps*" 라인 비교 (휴리스틱 —
#   정밀 등가는 S4 projection golden 게이트가 담당).
#
# Usage:
#   tools/ci_shadow_runner.sh [--planning-only] <base> <head> <symbols-file> [outdir]
#   --planning-only : Shadow = planning/관측만 (Selection+Plan+parity digest 생성, 검증 실행 없음 —
#                     계약 §10.6. projection equivalence는 Full+Pruned 실행에서만 입증)
#   기본 : planning + Full + plan-driven 실행 + per-symbol 등가 관측
#   exit 0 = parity+equivalence 관측 성공 (shadow 신호 유지)
#   exit 2 = equivalence 불일치 (fail-closed — rollout 정지 신호)
#   exit 1 = 실행 오류
set -euo pipefail
PLANNING_ONLY=0
if [ "${1:-}" = "--planning-only" ]; then PLANNING_ONLY=1; shift; fi
BASE="${1:?base ref required}"
HEAD="${2:?head ref required}"
SYMS="${3:?symbols-file required}"
OUT="${4:-/tmp/ci_shadow}"
mkdir -p "$OUT"

REPO_ROOT="$(git rev-parse --show-toplevel)"
SR_BIN="${SR_BIN:-/tmp/ci_shadow/selection_report}"
if [ ! -f "$SR_BIN" ]; then
  echo "[shadow] compiling selection_report..."
  nim c --hints:off -o:"$SR_BIN" "$REPO_ROOT/tools/selection_report.nim" > /dev/null 2>&1
fi
AX="${AX:-$REPO_ROOT/bin/ax}"

# 1) Selection → ExecutionPlan + parity digests
echo "[shadow] selection (${BASE}..${HEAD})..."
"$SR_BIN" --base "$BASE" --head "$HEAD" --symbols-file "$SYMS" \
  --plan-out "$OUT/execution_plan.json" --output "$OUT/selection_report.json"
PLAN_STATUS=$(python3 -c "import json;print(json.load(open('$OUT/selection_report.json'))['selection']['status'])")
echo "[shadow] planStatus=$PLAN_STATUS"

# 1b) planning-only: 검증 실행 없이 Selection/Plan/parity digest 생성·저장만 (계약 §10.6)
if [ "$PLANNING_ONLY" = "1" ]; then
  echo "[shadow] planning-only — verification 실행 생략 (projection equivalence는 Full+Pruned 실행에서 입증)"
  exit 0
fi

# 2) Full verification (기존 CI 경로 유지)
echo "[shadow] full verification..."
"$AX" prove --smt-timeout 4000 > "$OUT/full.log" 2>&1 || true
FULL_NODES=$(grep -oE "verifying [0-9]+ nodes" "$OUT/full.log" | head -1 || echo "verifying 0 nodes")

# 3) Plan-driven verification (Selected 유닛만)
if [ "$PLAN_STATUS" = "VALID" ]; then
  echo "[shadow] plan-driven verification..."
  "$AX" prove --plan "$OUT/execution_plan.json" --smt-timeout 4000 > "$OUT/accel.log" 2>&1 || true
  ACCEL_NODES=$(grep -oE "verifying [0-9]+ nodes" "$OUT/accel.log" | head -1 || echo "verifying 0 nodes")
else
  echo "[shadow] FALLBACK_REQUIRED/ERROR — plan-run 생략 (FULL이 canonical 실행)"
  ACCEL_NODES="(fallback: FULL)"
fi

# 4) Parity digests + Project(Full,Selected) 등가 관측
python3 - "$OUT" "$PLAN_STATUS" << 'PYEOF'
import json, re, sys
out, status = sys.argv[1], sys.argv[2]
rep = json.load(open(f"{out}/selection_report.json"))
def extract(path):
    txt = open(path, errors="ignore").read()
    # per-symbol verdict heuristic: "<name> status=ps*"
    return dict((m, v) for m, v in
                re.findall(r"([A-Za-z0-9_]+) status=(ps[A-Za-z]+)", txt))
full = extract(f"{out}/full.log")
accel = extract(f"{out}/accel.log")
selected = [p["unitId"] for p in rep["selection"]["selected"]]
units = [s.split("::")[-1] for s in selected]
equiv = {u: (full.get(u) == accel.get(u)) for u in units if u in full or u in accel}
obs = {
  "parity": {
    "semanticInputIdentity": rep["semanticInputIdentity"],
    "selection": {"status": status, "derivationDigest": rep["selection"]["derivationDigest"]},
    "plan": rep["plan"],
  },
  "equivalence": equiv,
  "allEqual": all(equiv.values()) if equiv else None,
}
json.dump(obs, open(f"{out}/shadow_equivalence.json", "w"), indent=2)
print(f"[shadow] equivalence: {obs['equivalence']}")
PYEOF

echo "[shadow] full=$FULL_NODES accel=$ACCEL_NODES"
EQ=$(python3 -c "import json;o=json.load(open('$OUT/shadow_equivalence.json'));print('true' if o['allEqual'] else ('false' if o['allEqual'] is not None else 'na'))")
case "$EQ" in
  true)  echo "[shadow] PASS — Project(Full,Selected) == plan-run (관측 유지)"; exit 0;;
  false) echo "[shadow] FAIL — 등가 불일치. rollout 정지 (fail-closed)."; exit 2;;
  *)     echo "[shadow] NA — 비교 가능한 선택 유닛 없음 (Selected=0 등)"; exit 0;;
esac