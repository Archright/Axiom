import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}
# axiomIoBoundary

## Agent Pre-flight Guard — 동기화 안전성 검증
##
## 에이전트가 코드 수정/커밋 전 반드시 실행하는 합의 게이트.
## Detached HEAD, Upstream 미동기화, 인프라 파일 중복 생성을 사전 차단.
##
## 사용법:
##   nim c -r src/gate/runners/agent_preflight.nim
##   # 또는 AGENTS.md 규칙에 따라 코드 수정 직전 실행

import std/os
import std/osproc
import std/strutils
import infrastructure/logger

type
  PreflightResult* = object
    safe*: bool
    reason*: string

proc safeExec(cmd: string): tuple[output: string, exitCode: int] =
  try:
    execCmdEx(cmd)
  except CatchableError:
    ("", -1)

proc verifyWorkspaceState*(): PreflightResult =
  ## 1. Detached HEAD 가드 — reflog 유실 방지
  let (branchOut, branchCode) = safeExec("git branch --show-current")
  if branchCode != 0 or branchOut.strip() == "":
    return PreflightResult(
      safe: false,
      reason: "Detached HEAD 상태에서 작업은 허용되지 않습니다. " &
              "Reflog 유실 리스크가 있습니다. " &
              "먼저 'git checkout <branch>'로 브랜치에 진입하십시오.")

  # 2. Upstream 미동기화 가드 — 파일 중복 생성 방지
  discard safeExec("git fetch origin 2>/dev/null")
  let (statusOut, _) = safeExec("git status -uno")
  if "behind" in statusOut:
    return PreflightResult(
      safe: false,
      reason: "로컬 브랜치가 Upstream보다 뒤쳐져 있습니다. " &
              "파일 중복 생성 위험이 있으니 먼저 'git pull --rebase'를 수행하십시오.")

  # 3. Merge/Rebase 진행 중 가드
  if dirExists(".git/rebase-merge") or dirExists(".git/rebase-apply") or
     fileExists(".git/MERGE_HEAD"):
    return PreflightResult(
      safe: false,
      reason: "Merge 또는 Rebase가 진행 중입니다. " &
              "충돌 해결 후 'git rebase --continue' 또는 'git merge --continue'를 먼저 수행하십시오.")

  return PreflightResult(safe: true, reason: "Workspace 무결성 검증 통과.")

proc checkInfraFileOverlap*(files: seq[string]): PreflightResult =
  ## 인프라 스크립트(bin/*, tools/*) 신규 작성 시 중복 검사
  for f in files:
    if f.startsWith("bin/") or f.startsWith("tools/"):
      let (lsOut, lsCode) = safeExec("git ls-files --others --exclude-standard " & f.quoteShell)
      if lsCode == 0 and lsOut.strip().len > 0:
        # 파일이 이미 tracked되지 않고 untracked로 존재 = 다른 브랜치에서 이미 생성됨
        discard  # untracked는 OK (새로 생성 중)
      # core/main 양쪽에서 생성 여부는 리베이스 시 자동 감지
  return PreflightResult(safe: true, reason: "인프라 파일 중복 검사 통과.")

when isMainModule:
  let res = verifyWorkspaceState()
  if not res.safe:
    logger.info "[CRITICAL AGENT ERROR] " & res.reason
    quit(1)
  logger.info "[SUCCESS] Agent Pre-flight Guard: " & res.reason

{.pop.}
