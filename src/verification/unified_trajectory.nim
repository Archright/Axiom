## Unified Trajectory Logger — SSOT for all ax prove pipeline events.
##
## Problem: Two separate logging systems exist:
##   - logThoughtTrajectory → logs/thought_trajectory.jsonl (dynamic proof search only)
##   - appendThoughtTrajectory → logs/audit/stream.jsonl (Lean replay only)
## Neither covers the full 11-stage pipeline.
##
## Solution: Single logStage() function that ALL pipeline stages call.
## Output: logs/ax_prove_trajectory.jsonl (unified event stream)
##
## References:
##   - Lean 4 trace[traceCls] pattern (Context7): structured, deterministic ordering
##   - AGENTS.md §0.5b: Quirk Documentation Mandate

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/json
import std/times
import std/os
import std/strutils
import core/utils/io_utils
# axiomIoBoundary
import verification/unified_trajectory_types
import core/axiom_pragmas

export unified_trajectory_types

proc logStage*(
  phase: StageKind;
  nodeId: string;
  detail: string;
 elapsedMs: int = 0;
  status: StageStatus = ssStarted;
  extra: JsonNode = nil
) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## SSOT: 모든 파이프라인 단계가 이 하나의 함수를 호출.
  ## logs/ax_prove_trajectory.jsonl에 통합 기록.
  ##
  ## Design: now().utc()는 Nim stdlib times.nim:1399의
  ## proc utc*(dt: DateTime): DateTime을 사용.
  ## 코드베이스 10+ 파일에서 동일 패턴 사용 중.
  var entry = %*{
    "ts": now().utc().format("yyyy-MM-dd'T'HH:mm:ss.fff'Z'"),
    "phase": $phase,
    "nodeId": nodeId,
    "detail": detail,
    "elapsedMs": elapsedMs,
    "status": $status
  }
  if extra != nil:
    entry["extra"] = extra
  try:
    # WP2-a: trajectory routes to stateRoot when set (subject immutability).
    let trajDir = block:
      let v = getEnv("AXIOM_STATE_DIR", "").strip()
      if v.len > 0: joinPath(v, "logs") else: "logs"
    createDir(trajDir)
    ## intentional-discard: append-only trajectory log; failure is non-blocking (best-effort)
    discard appendFileLineOpt(joinPath(trajDir, "ax_prove_trajectory.jsonl"), @[$entry])
  except CatchableError:
    discard  # 로깅 실패가 파이프라인을 중단하지 않음  # axiom:best-effort(ioboundary catch)
{.pop.}
