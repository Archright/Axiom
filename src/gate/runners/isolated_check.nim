import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}
# axiomIoBoundary

## Ephemeral Worktree Guard — 불변적 격리 검증
##
## 메인 Working Tree를 1비트도 변경하지 않고 격리된 git worktree에서
## nim check를 수행하는 품질 게이트 패턴.
##
## 핵심 메커니즘:
##   1. `git stash create` — 미커밋 변경사항을 dangling commit으로 캡처 (WT 보존)
##   2. `git worktree add --detach` — 캡처된 commit을 임시 디렉토리에 체크아웃
##   3. `nim check` — 격리 환경에서 검증
##   4. `defer` — 예외 불문 deterministic cleanup
##
## 선행 코드: tools/debug/gate_replay.nim (per-commit worktree 패턴)
## 이번 구현: stash-based snapshot (현재 변경사항 포함)

import std/os
import std/osproc
import std/sequtils
import std/strutils
import std/times
import std/monotimes
import std/posix # for sleep()

type
  IsolatedCheckResult* = object
    ok*: bool
    output*: string
    elapsedMs*: int

proc safeExecCmd(cmd: string): tuple[output: string, exitCode: int] =
  ## execCmdEx wrapper that never raises — returns (-1) on OS/IO error.
  try:
    execCmdEx(cmd)
  except CatchableError:
    ("", -1)

proc runIsolatedNimCheck*(
  files: seq[string];
 targetCommit: string = "HEAD"
): IsolatedCheckResult =
  ## 메인 Working Tree를 1비트도 변경하지 않고 격리 검증 수행.
  ## git stash create로 미커밋 변경사항(Staged + Unstaged)까지 캡처하여
  ## worktree에 주입. nim.cfg/config.nims 인식을 위해 cd + 상대경로 사용.
  let start = getMonoTime()
  let pid = getCurrentProcessId()
  let tmpWorktree = getTempDir() / "axiom-isolated-gate-" & $pid & "-" & $getMonoTime().ticks

  # 1. 미커밋 변경사항 캡처 (working tree 보존)
  #    git stash create = dangling commit 생성, WT 롤백 없음
  var commitToVerify = targetCommit
  if targetCommit == "HEAD":
    let (stashOut, stashCode) = safeExecCmd("git stash create")
    let cleanSha = stashOut.strip()
    if stashCode == 0 and cleanSha.len > 0:
      commitToVerify = cleanSha

  # 2. 기존 잔여 worktree 정리
  if dirExists(tmpWorktree):
    discard safeExecCmd("git worktree remove --force " & tmpWorktree.quoteShell & " 2>/dev/null")
    discard safeExecCmd("git worktree prune 2>/dev/null")

  # 3. 격리 worktree 생성 (detach = 브랜치 참조 없음, dangling commit 사용 가능)
  let (_, addCode) = safeExecCmd(
    "git worktree add --force --detach " & tmpWorktree.quoteShell & " " & commitToVerify & " 2>&1")
  if addCode != 0:
    return IsolatedCheckResult(ok: false, output: "worktree creation failed", elapsedMs: 0)

  defer:
    # 결정론적 cleanup — 예외 불문 항상 실행 (Nim defer = finally)
    # 파일 시스템 락/프로세스 점유로 인한 일시적 삭제 실패에 대비한 재시도
    for attempt in 1 .. 3:
      discard safeExecCmd("git worktree remove --force " & tmpWorktree.quoteShell & " 2>/dev/null")
      discard safeExecCmd("git worktree prune 2>/dev/null")
      if not dirExists(tmpWorktree):
        break
      if attempt < 3:
        sleep(100 * attempt)  # 지수 백오프: 100ms, 200ms

  # 4. 격리 환경에서 nim check
  #    cd로 진입 → nim.cfg/config.nims 프로젝트 컨텍스트 인식 보장
  #    상대경로 사용 → 절대경로로 인한 캐시/설정 혼동 방지
  let filesQuoted = files.mapIt(it.quoteShell).join(" ")
  let (output, exitCode) = safeExecCmd(
    "cd " & tmpWorktree.quoteShell & " && nim check " & filesQuoted & " 2>&1")

  let elapsed = int((getMonoTime() - start).inMilliseconds)
  IsolatedCheckResult(ok: exitCode == 0, output: output, elapsedMs: elapsed)

{.pop.}
