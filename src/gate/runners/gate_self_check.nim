import core/trusted/layer_declaration


axiomLayer "gate"
{.push raises: [CatchableError].}

import ../utils/real_git
import core/axiom_pragmas
import core/gate/gate_vfs
import core/utils/repo_root
import std/os
import std/osproc
import std/strformat
import std/strutils
import std/times
import infrastructure/logging_facade
# axiomIoBoundary

let gitExe = findRealGit()

# Binary Freshness Guard — Layer 2 (L1 Meta Gate).
# Compile-time timestamp injected by Bash Shim via -d:AxiomCompileTime=$(date +%s).
# Changing -d value forces nimcache SHA1 recompilation → always fresh.
# Duplicated from gate_hook.nim to respect L1/L0 boundary (no L0 imports).
const AxiomCompileTime {.intdefine.}: int = 0
proc checkBinaryFreshness(repoRoot: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Verify no source file under src/gate/ was modified after this binary was compiled.
  ## Layer 2 defense: catches stale binary even if Bash Shim is bypassed (--no-verify).
  if AxiomCompileTime == 0:
    logWarn("gate_self_check", "[gate-self-check] WARN: AxiomCompileTime not injected (dev build?)")
    return
  let srcGate = repoRoot / "src" / "gate"
  if not dirExists(srcGate):
    return
  for path in walkDirRec(srcGate, yieldFilter = {pcFile}):
    if path.endsWith(".nim"):
      let mtime = getLastModificationTime(path).toUnix()
      if mtime > AxiomCompileTime:
        logInfo("gate_self_check", &"[gate-self-check] FATAL: {path} modified after binary compilation")
        logInfo("gate_self_check", &"  Binary compiled: {AxiomCompileTime}, File mtime: {mtime}")
        quit(1)
  logInfo("gate_self_check", &"[gate-self-check] Binary freshness: OK (compiled at {AxiomCompileTime})")
proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  let repoRoot = findRepoRoot()
  setCurrentDir(repoRoot)

  # Layer 2: Binary freshness verification (compile-time timestamp check)
  checkBinaryFreshness(repoRoot)

  var allOk = true

  # 1. Resolve hooks directory (respect core.hookspath)
  let (hookspathOut, _) = execCmdEx(gitExe & " config --local core.hookspath")
  let hooksDir = if hookspathOut.strip().len > 0: hookspathOut.strip() else: ".git/hooks"
  logInfo("gate_self_check", &"[gate-self-check] hooks dir: '{hooksDir}'")

  # 2. hook binary validity check
  let hooks = ["pre-commit", "pre-push"]
  for hook in hooks:
    let hookPath = &"{hooksDir}/{hook}"
    if not fileExists(hookPath):
      logError("gate_self_check", &"[gate-self-check] FAIL: {hookPath} missing")
      allOk = false
      continue
    let fileSize = getFileSize(hookPath)
    if fileSize < 100_000:
      logWarn("gate_self_check", &"[gate-self-check] WARN: {hookPath} is {fileSize} bytes (suspiciously small, may be a stub)")
    else:
      logInfo("gate_self_check", &"[gate-self-check] {hook}: OK ({fileSize} bytes)")

  if allOk:
    logInfo("gate_self_check", "[gate-self-check] PASS")
    quit(0)
  elif existsEnv("AXIOM_BOOTSTRAP_VERIFY"):
    # Bootstrap sandbox has no .git/hooks (blacklisted from copy) — hooks
    # absence is expected there; the real repo is verified post-commit.
    logWarn("gate_self_check", "[gate-self-check] PASS (bootstrap sandbox: hooks not present)")
    quit(0)
  else:
    logError("gate_self_check", "[gate-self-check] FAIL")
    quit(1)
# CONFLICT RESOLVED (2026-08-08): stale merge artifact removed — the rebase that
# added the VFS entry point converged cleanly; main() (CLI entry, isMainModule)
# and mainWithVfs() (VFS entry for pipeline orchestrator integration) are
# distinct, non-duplicated procs. Both are intentionally kept.
proc mainWithVfs(ctx: GateContext) =
  ## VFS entry point. Verifies gate infrastructure integrity via VFS.
  setCurrentDir(ctx.repoRoot)

  # Layer 2: Binary freshness verification (compile-time timestamp check)
  checkBinaryFreshness(ctx.repoRoot)

  var allOk = true

  # 1. Resolve hooks directory (respect core.hookspath) via VFS subprocess
  let hookspathResult = vfsExec(ctx, "git", @["config", "--local", "core.hookspath"])
  let hooksDir = if hookspathResult.output.strip().len > 0: hookspathResult.output.strip() else: ".git/hooks"
  logInfo("gate_self_check", &"[gate-self-check] hooks dir: '{hooksDir}'")

  # 2. hook binary validity check
  let hooks = ["pre-commit", "pre-push"]
  for hook in hooks:
    let hookPath = &"{hooksDir}/{hook}"
    if not vfsExists(ctx, hookPath):
      logError("gate_self_check", &"[gate-self-check] FAIL: {hookPath} missing")
      allOk = false
      continue
    # getFileSize requires real filesystem; VFS only stores content.
    # Use vfsRead length as proxy for content size.
    try:
      let content = vfsRead(ctx, hookPath)
      let fileSize = content.len
      if fileSize < 100_000:
        logWarn("gate_self_check", &"[gate-self-check] WARN: {hookPath} is {fileSize} bytes (suspiciously small, may be a stub)")
      else:
        logInfo("gate_self_check", &"[gate-self-check] {hook}: OK ({fileSize} bytes)")
    except KeyError:
      logWarn("gate_self_check", &"[gate-self-check] WARN: {hookPath} readable but no content in VFS")

  if allOk:
    logInfo("gate_self_check", "[gate-self-check] PASS")
    quit(0)
  elif existsEnv("AXIOM_BOOTSTRAP_VERIFY"):
    # Bootstrap sandbox has no .git/hooks (blacklisted from copy) — hooks
    # absence is expected there; the real repo is verified post-commit.
    logWarn("gate_self_check", "[gate-self-check] PASS (bootstrap sandbox: hooks not present)")
    quit(0)
  else:
    logError("gate_self_check", "[gate-self-check] FAIL")
    quit(1)

when isMainModule:
  main()

{.pop.}
