## ci_engine.nim — Unified CI Engine for Axiom
## Replaces: bootstrap_circleci.sh, setup_axiom_users.sh, setup_vendor_tree_sitter.sh,
##           run_nimcheck.sh, run_nimcheck_all.sh
##
## Subcommands:
##   bootstrap  — CircleCI infrastructure initialization
##   provision  — OS user isolation + cgroups + bubblewrap verification
##   vendor     — tree-sitter C source vendoring
##   prune      — Dead module pruning (delegates to prune_dead_modules.nim)
##   verify     — nim check + build matrix verification

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, osproc, strtabs, strutils, strformat, parseopt, json, streams, algorithm]

# ═══════════════════════════════════════════════════════════════════════════════
# §0: Compile-Time Toolchain Lock
# ═══════════════════════════════════════════════════════════════════════════════

static:
  when NimMajor != 2 or NimMinor != 2:
    {.error: "Axiom CI Engine requires Nim v2.2.x".}

# ═══════════════════════════════════════════════════════════════════════════════
# §1: Absolute Binary Paths (compile-time fixed, no PATH lookup)
# ═══════════════════════════════════════════════════════════════════════════════

const
  BinUserAdd* = "/usr/sbin/useradd"
  BinChown* = "/bin/chown"
  BinChmod* = "/bin/chmod"
  BinId* = "/usr/bin/id"
  BinBwrap* = "/usr/bin/bwrap"
  # Compile-time dynamic binary resolution (POSIX command -v)
  # Note: gorge() Z3 PATH Quirk only affects `nim check`, not `nim c`. Safe here.
  BinNim* = gorge("command -v nim").strip()
  BinGit* = gorge("command -v git").strip()

# ═══════════════════════════════════════════════════════════════════════════════
# §2: Type-Safe Command System (variant object)
# ═══════════════════════════════════════════════════════════════════════════════

type
  SysCmd = enum
    scUserAdd = "useradd"
    scCgroupWrite = "cgroupwrite"
    scChown = "chown"
    scChmod = "chmod"

  CmdContext = object
    case cmd: SysCmd
    of scUserAdd:
      username: string
      isSystem: bool
    of scCgroupWrite:
      cgroupPath: string
      cgroupValue: string
    of scChown:
      ownerGroup: string
      chownTarget: string
    of scChmod:
      mode: string
      chmodTarget: string

# ═══════════════════════════════════════════════════════════════════════════════
# §3: Hermetic Environment
# ═══════════════════════════════════════════════════════════════════════════════

proc getHermeticEnv(): StringTableRef =
  result = newStringTable(modeCaseInsensitive)
  result["PATH"] = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  result["LANG"] = "C.UTF-8"
  result["LC_ALL"] = "C.UTF-8"
  result["SOURCE_DATE_EPOCH"] = "0"
  result["FORCE_DETERMINISTIC"] = "1"
  result["NIM_CACHE_DIR"] = "build/nimcache/ci_engine"

# ═══════════════════════════════════════════════════════════════════════════════
# §4: Container Detection
# ═══════════════════════════════════════════════════════════════════════════════

proc isContainer(): bool =
  result = fileExists("/.dockerenv") or
           (fileExists("/proc/1/cgroup") and readFile("/proc/1/cgroup").contains("docker"))

# ═══════════════════════════════════════════════════════════════════════════════
# §5: Type-Safe Execute
# ═══════════════════════════════════════════════════════════════════════════════

proc execute(ctx: CmdContext): (string, int) =
  let hermeticEnv = getHermeticEnv()
  case ctx.cmd
  of scUserAdd:
    let args = if ctx.isSystem: @["-r", "-m", "-s", "/usr/sbin/nologin", ctx.username]
               else: @["-m", ctx.username]
    let cmdLine = BinUserAdd & " " & args.join(" ")
    return execCmdEx(cmdLine, env=hermeticEnv, options={poStdErrToStdOut})
  of scCgroupWrite:
    if isContainer():
      return (&"[SKIP] Container environment: {ctx.cgroupPath}", 0)
    try:
      writeFile(ctx.cgroupPath, ctx.cgroupValue)
      return ("Success", 0)
    except IOError as e:
      return (e.msg, 1)
  of scChown:
    let cmdLine = BinChown & " " & ctx.ownerGroup & " " & ctx.chownTarget
    return execCmdEx(cmdLine, env=hermeticEnv, options={poStdErrToStdOut})
  of scChmod:
    let cmdLine = BinChmod & " " & ctx.mode & " " & ctx.chmodTarget
    return execCmdEx(cmdLine, env=hermeticEnv, options={poStdErrToStdOut})

# ═══════════════════════════════════════════════════════════════════════════════
# §6: Helper Utilities
# ═══════════════════════════════════════════════════════════════════════════════

proc runCmdWithCode(cmd: string; args: seq[string] = @[];
                    env: StringTableRef = nil; stdin: string = ""): (string, int) =
  ## Execute a command and capture the actual exit code via startProcess.
  let hermeticEnv = if env != nil: env else: getHermeticEnv()
  try:
    let process = startProcess(cmd, args=args, env=hermeticEnv,
                               options={poStdErrToStdOut, poParentStreams})
    if stdin.len > 0:
      var inputStream = process.inputStream()
      inputStream.write(stdin)
      inputStream.close()
    let exitCode = process.waitForExit()
    let output = process.outputStream().readAll()
    result = (output, exitCode)
  except OSError as e:
    result = (e.msg, -1)

proc logInfo(msg: string) =
  echo &"[INFO] {msg}"

proc logSkip(msg: string) =
  echo &"[SKIP] {msg}"

proc logCreate(msg: string) =
  echo &"[CREATE] {msg}"

proc logOk(msg: string) =
  echo &"[OK] {msg}"

proc logError(msg: string) =
  echo &"[ERROR] {msg}"

proc logWarn(msg: string) =
  echo &"[WARN] {msg}"

proc logAction(msg: string) =
  echo &"[ACTION] {msg}"

# ═══════════════════════════════════════════════════════════════════════════════
# §7: bootstrap — CircleCI Infrastructure Initialization
#           Port of tools/bootstrap_circleci.sh (117 lines)
# ═══════════════════════════════════════════════════════════════════════════════

proc bootstrap() =
  const
    Repo = "Archright/Axiom"
    OrgSlug = "gh/archright"
    Contexts = ["axiom-ci", "axiom-leanstral"]

  echo "╔══════════════════════════════════════════════╗"
  echo "║  Axiom CircleCI Bootstrap                   ║"
  echo "╚══════════════════════════════════════════════╝"
  echo ""

  # ── Pre-checks: required CLI tools ──────────────────────────────────────
  let requiredTools = ["gh", "circleci", "jq"]
  for tool in requiredTools:
    if findExe(tool).len == 0:
      logError(&"Required CLI not installed: {tool}")
      echo &"  Install: brew install {tool} (or your package manager)"
      quit(1)

  # ── Pre-checks: required environment variables ──────────────────────────
  let ghcrToken = getEnv("GHCR_TOKEN", "")
  if ghcrToken.len == 0:
    logError("GHCR_TOKEN environment variable not set.")
    echo "  export GHCR_TOKEN=\"ghp_...\"  (GitHub PAT, write:packages scope)"
    quit(1)

  let mistralApiKey = getEnv("MISTRAL_API_KEY", "")
  if mistralApiKey.len == 0:
    logError("MISTRAL_API_KEY environment variable not set.")
    echo "  export MISTRAL_API_KEY=\"...\""
    quit(1)

  logOk("Pre-checks passed (gh, circleci, jq, env vars)")

  # Build hermetic env with home bin dirs for gh/circleci/jq
  let env = getHermeticEnv()
  let homeDir = getEnv("HOME", "/home/" & getEnv("USER", "nobody"))
  env["PATH"] = homeDir & "/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

  # ── Step 1: Organization ID acquisition ─────────────────────────────────
  echo ""
  echo "── Step 1: Organization ID acquisition ──"
  let (orgInfo, orgExit) = runCmdWithCode("circleci",
    args = @["organization", "info", "--org-slug", OrgSlug, "--json"], env=env)
  if orgExit != 0:
    logError(&"Organization '{OrgSlug}' not found.")
    echo "  Verify circleci CLI auth: circleci setup"
    quit(1)
  # Parse JSON for .id
  let orgJson = parseJson(orgInfo)
  let orgId = orgJson["id"].getStr("")
  if orgId.len == 0:
    logError(&"Organization '{OrgSlug}' not found (empty id).")
    quit(1)
  logOk(&"Organization ID: {orgId}")

  # ── Step 2: CircleCI project follow ─────────────────────────────────────
  echo ""
  echo "── Step 2: CircleCI project follow ──"
  let (followOut, followExit) = runCmdWithCode("circleci",
    args = @["project", "follow", "--org-slug", OrgSlug, &"github.com/{Repo}"], env=env)
  if followExit == 0:
    logOk(&"Project followed: {Repo}")
  else:
    logInfo("Project already followed or error (ignoring, continuing)")

  # ── Step 3: Context creation (idempotent) ───────────────────────────────
  echo ""
  echo "── Step 3: Context creation ──"
  for ctx in Contexts:
    let (_, ctxExit) = runCmdWithCode("circleci",
      args = @["context", "create", "--org-id", orgId, ctx], env=env)
    if ctxExit == 0:
      logOk(&"Context created: {ctx}")
    else:
      logInfo(&"Context '{ctx}' already exists (skip)")

  # ── Step 4: Secret injection ────────────────────────────────────────────
  echo ""
  echo "── Step 4: Secret injection ──"
  # GHCR_TOKEN → axiom-ci context
  let (_, s1Exit) = runCmdWithCode("circleci",
    args = @["context", "store-secret", "--org-id", orgId, "axiom-ci", "GHCR_TOKEN"],
    env=env, stdin=ghcrToken)
  if s1Exit == 0:
    logOk("GHCR_TOKEN → axiom-ci")
  else:
    logWarn("GHCR_TOKEN injection failed (may already exist)")

  # MISTRAL_API_KEY → axiom-leanstral context
  let (_, s2Exit) = runCmdWithCode("circleci",
    args = @["context", "store-secret", "--org-id", orgId, "axiom-leanstral", "MISTRAL_API_KEY"],
    env=env, stdin=mistralApiKey)
  if s2Exit == 0:
    logOk("MISTRAL_API_KEY → axiom-leanstral")
  else:
    logWarn("MISTRAL_API_KEY injection failed (may already exist)")

  # ── Step 5: GHCR image build trigger ────────────────────────────────────
  echo ""
  echo "── Step 5: GHCR image build trigger ──"
  let (_, triggerExit) = runCmdWithCode("circleci",
    args = @["pipeline", "trigger", "--org-slug", OrgSlug,
           "--branch", "main", "--parameter", "build-image=true",
           &"github.com/{Repo}"], env=env)
  if triggerExit == 0:
    logOk("Image build pipeline triggered")
  else:
    logWarn("Pipeline trigger failed — trigger manually in CircleCI dashboard")
    echo "  Parameter: build-image=true"

  # ── Complete ────────────────────────────────────────────────────────────
  echo ""
  echo "╔══════════════════════════════════════════════╗"
  echo "║  Bootstrap Complete                          ║"
  echo "╠══════════════════════════════════════════════╣"
  echo "║  Next steps:                                 ║"
  echo "║  1. Verify image build in CircleCI dashboard ║"
  echo "║  2. git push origin main → CI workflow check  ║"
  echo "╚══════════════════════════════════════════════╝"

# ═══════════════════════════════════════════════════════════════════════════════
# §8: provision — OS User Isolation + Cgroups + Bubblewrap Verification
#           Port of tools/setup_axiom_users.sh (127 lines)
# ═══════════════════════════════════════════════════════════════════════════════

proc provision() =
  echo "=== Axiom Gate Signing — Phase 1 Setup ==="
  echo ""

  # ─── 1. axiom-sandbox user (L1: proof-generation sandbox) ───────────────
  echo ""
  echo "── Step 1: axiom-sandbox user ──"
  let (_, u1Exit) = execute(CmdContext(
    cmd: scUserAdd, username: "axiom-sandbox", isSystem: true))
  case u1Exit
  of 0: logCreate("user 'axiom-sandbox' (system, nologin)")
  of 9: logSkip("user 'axiom-sandbox' already exists")
  else: logError("Failed to create user 'axiom-sandbox'")

  # ─── 2. axiom-gate user (L2: signing daemon) ───────────────────────────
  echo ""
  echo "── Step 2: axiom-gate user ──"
  let (_, u2Exit) = execute(CmdContext(
    cmd: scUserAdd, username: "axiom-gate", isSystem: true))
  case u2Exit
  of 0: logCreate("user 'axiom-gate' (system, nologin)")
  of 9: logSkip("user 'axiom-gate' already exists")
  else: logError("Failed to create user 'axiom-gate'")

  # ─── 3. SSH Ed25519 key generation (axiom-gate) ────────────────────────
  echo ""
  echo "── Step 3: SSH Ed25519 signing key ──"
  let gateHome = "/home/axiom-gate"
  let axiomDir = gateHome & "/.axiom"
  let keyPath = axiomDir & "/id_ed25519"

  if fileExists(keyPath):
    logSkip(&"signing key already exists at {keyPath}")
  else:
    logCreate("SSH Ed25519 signing key for axiom-gate")
    let (mkdirOut, mkdirExit) = runCmdWithCode("mkdir", args = @["-p", axiomDir])
    if mkdirExit != 0 and not dirExists(axiomDir):
      logError(&"Failed to create {axiomDir}: {mkdirOut}")

    let keygenEnv = getHermeticEnv()
    keygenEnv["HOME"] = gateHome
    let (keygenOut, keygenExit) = runCmdWithCode("ssh-keygen",
      args = @["-t", "ed25519", "-f", keyPath, "-C", "axiom-gate-daemon", "-N", ""],
      env=keygenEnv)
    if keygenExit == 0:
      # Set permissions
      discard runCmdWithCode("chmod", args = @["600", keyPath])
      discard runCmdWithCode("chmod", args = @["644", keyPath & ".pub"])
      # Read and display public key
      if fileExists(keyPath & ".pub"):
        let pubKey = readFile(keyPath & ".pub").strip()
        logInfo(&"Public key: {pubKey}")
        logAction("Add this public key to GitHub: Settings > SSH Keys")
    else:
      logError(&"ssh-keygen failed: {keygenOut}")

  # ─── 4. cgroups v2 setup (L1 resource limits) ─────────────────────────
  echo ""
  echo "── Step 4: cgroups v2 resource limits ──"
  let cgroupPath = "/sys/fs/cgroup/axiom-sandbox"

  if dirExists(cgroupPath):
    logSkip("cgroup 'axiom-sandbox' already exists")
  else:
    logCreate("cgroup 'axiom-sandbox' with resource limits")
    # Create cgroup directory
    let (cgMkdirOut, cgMkdirExit) = runCmdWithCode("mkdir", args = @["-p", cgroupPath])
    if cgMkdirExit == 0 or dirExists(cgroupPath):
      # CPU: 50% (50000 microseconds per 100000 period)
      let (_, cpuExit) = execute(CmdContext(
        cmd: scCgroupWrite, cgroupPath: cgroupPath & "/cpu.max",
        cgroupValue: "50000 100000"))
      # Memory: 512MB
      let (_, memExit) = execute(CmdContext(
        cmd: scCgroupWrite, cgroupPath: cgroupPath & "/memory.max",
        cgroupValue: "536870912"))
      if cpuExit == 0 and memExit == 0:
        logOk("CPU limit: 50%, Memory limit: 512MB")
      else:
        logWarn("cgroup write failed (expected in container)")
    else:
      logError(&"Failed to create cgroup directory: {cgMkdirOut}")

  # ─── 5. bubblewrap verification (DO NOT install) ───────────────────────
  echo ""
  echo "── Step 5: bubblewrap verification ──"
  if fileExists(BinBwrap):
    logOk("bubblewrap found at " & BinBwrap)
    # Runtime sandbox test
    let (_, bwrapExit) = runCmdWithCode(BinBwrap,
      args = @["--dev-bind", "/", "/", "true"])
    if bwrapExit == 0:
      logOk("bubblewrap sandbox test passed")
    else:
      logWarn("bubblewrap test failed (unprivileged container — graceful degradation)")
  else:
    logWarn("bubblewrap not found at " & BinBwrap)
    logInfo("Install bubblewrap for sandbox support")

  # ─── 6. Unix domain socket directory ───────────────────────────────────
  echo ""
  echo "── Step 6: Unix domain socket directory ──"
  let sockDir = "/run/axiom-gate-daemon"

  if dirExists(sockDir):
    logSkip("socket directory already exists")
  else:
    logCreate(&"socket directory {sockDir}")
    let (_, mkdirExit) = runCmdWithCode("mkdir", args = @["-p", sockDir])
    if mkdirExit == 0 or dirExists(sockDir):
      let (_, chownExit) = execute(CmdContext(
        cmd: scChown, ownerGroup: "axiom-gate:axiom-gate", chownTarget: sockDir))
      let (_, chmodExit) = execute(CmdContext(
        cmd: scChmod, mode: "770", chmodTarget: sockDir))
      if chownExit == 0 and chmodExit == 0:
        logOk(&"socket directory {sockDir} ready (owner=axiom-gate, mode=770)")
      else:
        logWarn("chown/chmod on socket dir may require sudo")
    else:
      logError(&"Failed to create socket directory (may require sudo)")

  # ─── 7. Add agent user to axiom-gate group ─────────────────────────────
  echo ""
  echo "── Step 7: Agent user → axiom-gate group ──"
  let currentUser = getEnv("SUDO_USER", getEnv("USER", "nobody"))
  let (groupsOut, _) = runCmdWithCode(BinId, args = @["-nG", currentUser])
  if groupsOut.strip().contains("axiom-gate"):
    logSkip(&"user '{currentUser}' already in group 'axiom-gate'")
  else:
    logAction(&"user '{currentUser}' → group 'axiom-gate' (requires sudo)")
    logInfo("  Run: sudo usermod -aG axiom-gate " & currentUser)
    logInfo("  Then logout and login again for group change to take effect")

  # ─── 8. ptrace scope check (Yama LSM) ─────────────────────────────────
  echo ""
  echo "── Step 8: ptrace scope check ──"
  let ptracePath = "/proc/sys/kernel/yama/ptrace_scope"
  if fileExists(ptracePath):
    let ptraceScope = readFile(ptracePath).strip()
    if ptraceScope in ["1", "2", "3"]:
      logOk(&"ptrace_scope already restricted ({ptraceScope})")
    else:
      logAction("ptrace_scope = 1 (restricted ptrace)")
      logInfo("  Requires: sudo sh -c 'echo 1 > /proc/sys/kernel/yama/ptrace_scope'")
      logInfo("  Persist:  sudo sh -c 'echo kernel.yama.ptrace_scope = 1 > /etc/sysctl.d/10-ptrace.conf'")
  else:
    logSkip("Yama LSM not available on this system")

  # ─── 9. Toolchain lock file check ──────────────────────────────────────
  echo ""
  echo "── Step 9: Toolchain lock file ──"
  let toolchainLock = "axiom-toolchain.lock"
  if fileExists(toolchainLock):
    logOk(&"Toolchain lock file exists: {toolchainLock}")
    for line in readFile(toolchainLock).strip().splitLines():
      echo &"     {line}"
  else:
    logWarn(&"Toolchain lock file not found: {toolchainLock}")
    logAction("Run Phase 13 (musl build) to generate it.")

  echo ""
  echo "=== Phase 1 Setup Complete ==="
  echo "Next steps:"
  echo "  1. Add axiom-gate SSH public key to GitHub"
  echo "  2. Logout and login for group changes"
  echo "  3. Run Phase 13 to build musl static binaries"
  echo "  4. Proceed to Wave 1 (Phase 2, 3, 13)"

# ═══════════════════════════════════════════════════════════════════════════════
# §9: vendor — tree-sitter C Source Vendoring
#           Port of tools/setup_vendor_tree_sitter.sh (46 lines)
# ═══════════════════════════════════════════════════════════════════════════════

proc vendor() =
  let tsVersion = getEnv("TREE_SITTER_VERSION", "0.24.7")
  let tsNimVersion = getEnv("TREE_SITTER_NIM_VERSION", "main")

  let projectRoot = getCurrentDir()
  let tsVendor = projectRoot / "vendor" / "tree-sitter"
  let tsNimVendor = projectRoot / "vendor" / "tree-sitter-nim"

  echo &"=== Vendoring tree-sitter {tsVersion} ==="

  let env = getHermeticEnv()

  # ── tree-sitter runtime ─────────────────────────────────────────────────
  createDir(tsVendor / "lib" / "include" / "tree_sitter")
  createDir(tsVendor / "lib" / "src")

  # Download api.h
  logInfo("Downloading tree-sitter api.h...")
  let apiUrl = &"https://raw.githubusercontent.com/tree-sitter/tree-sitter/v{tsVersion}/lib/include/tree_sitter/api.h"
  let (_, curl1Exit) = runCmdWithCode("curl",
    args = @["-sL", apiUrl, "-o", tsVendor / "lib" / "include" / "tree_sitter" / "api.h"],
    env=env)
  if curl1Exit != 0:
    logError("Failed to download api.h")
    quit(1)

  # Download amalgamated lib.c
  logInfo("Downloading tree-sitter lib.c...")
  let libUrl = &"https://raw.githubusercontent.com/tree-sitter/tree-sitter/v{tsVersion}/lib/src/lib.c"
  let (_, curl2Exit) = runCmdWithCode("curl",
    args = @["-sL", libUrl, "-o", tsVendor / "lib" / "src" / "lib.c"],
    env=env)
  if curl2Exit != 0:
    logError("Failed to download lib.c")
    quit(1)

  logOk(&"tree-sitter runtime → {tsVendor}")

  # ── tree-sitter-nim grammar ─────────────────────────────────────────────
  createDir(tsNimVendor / "src")

  # Download parser.c (try v-prefixed tag first, fall back to main)
  logInfo("Downloading tree-sitter-nim parser.c...")
  let parserUrlTag = &"https://raw.githubusercontent.com/nickel-lang/tree-sitter-nim/v{tsNimVersion}/src/parser.c"
  let (_, curl3Exit) = runCmdWithCode("curl",
    args = @["-sL", "-f", parserUrlTag, "-o", tsNimVendor / "src" / "parser.c"],
    env=env)
  if curl3Exit != 0:
    # Fallback: no v-prefix
    let parserUrlPlain = &"https://raw.githubusercontent.com/nickel-lang/tree-sitter-nim/{tsNimVersion}/src/parser.c"
    let (_, curl3bExit) = runCmdWithCode("curl",
      args = @["-sL", parserUrlPlain, "-o", tsNimVendor / "src" / "parser.c"],
      env=env)
    if curl3bExit != 0:
      logError("Failed to download parser.c (both v-prefixed and plain URLs failed)")
      quit(1)

  logOk(&"tree-sitter-nim grammar → {tsNimVendor}")

  echo ""
  echo "=== Done. Vendored tree-sitter sources ready. ==="

# ═══════════════════════════════════════════════════════════════════════════════
# §10: prune — Dead Module Pruning (delegates to prune_dead_modules.nim)
# ═══════════════════════════════════════════════════════════════════════════════

proc prune() =
  echo "=== Dead Module Pruning (dry-run) ==="

  let projectRoot = getCurrentDir()
  let pruneScript = projectRoot / "tools" / "ci" / "prune_dead_modules.nim"

  if not fileExists(pruneScript):
    logError(&"prune_dead_modules.nim not found at {pruneScript}")
    quit(1)

  logInfo(&"Running: {BinNim} c -r {pruneScript} --dry-run")
  let env = getHermeticEnv()
  let (output, exitCode) = runCmdWithCode(BinNim,
    args = @["c", "-r", "--hints:off", pruneScript, "--dry-run"],
    env=env)

  if output.len > 0:
    echo output

  if exitCode == 0:
    logOk("Prune completed successfully")
  else:
    logError(&"Prune failed with exit code {exitCode}")
    quit(exitCode)

# ═══════════════════════════════════════════════════════════════════════════════
# §11: verify — Build Matrix Verification
#           Port of experimental/scripts/run_nimcheck.sh + run_nimcheck_all.sh
# ═══════════════════════════════════════════════════════════════════════════════

proc verify() =
  echo "=== Build Matrix Verification ==="
  echo ""

  let projectRoot = getCurrentDir()
  let env = getHermeticEnv()
  var failures = 0
  var total = 0

  # ── Key source files (top 30 largest, from run_nimcheck.sh) ─────────────
  let keyFiles = [
    "src/core/axiom_api.nim",
    "src/core/boundary_extractor.nim",
    "src/verification/lean_lsp.nim",
    "src/core/topology_engine.nim",
    "src/verification/pipeline_lean_spec_inference.nim",
    "src/core/gateway.nim",
    "src/cli/certificate_cli.nim",
    "src/cli/commands/observability.nim",
    "src/core/spec_generator.nim",
    "src/verification/pipeline_negative_scan.nim",
    "src/core/verified_axioms_catalog.nim",
    "src/core/smt_to_lean_codegen.nim",
    "src/cli/wf_state.nim",
    "src/cli/topology_cli.nim",
    "src/ui/ax_tui_reporter.nim",
    "src/cli/verify_workflow_cli.nim",
    "src/gate/architecture_policy.nim",
    "src/mcp/axiom_mcp.nim",
    "src/translator/universal_mapper.nim",
    "src/core/orchestrator.nim",
    "src/cli/commands/recertify_lean.nim",
    "src/cli/report_cli.nim",
    "src/core/session_parser.nim",
    "src/cli/asi_cli.nim",
    "src/core/the_judge_query.nim",
    "src/verification/pipeline_core_runner.nim",
    "src/verification/proof_synthesis_engine.nim",
    "src/core/global_symbol_graph_builder.nim",
    "src/gate/architecture_ast_extractor.nim",
    "src/verification/translation_validator.nim",
  ]

  echo "── Phase 1: Key file verification (top 30) ──"
  for f in keyFiles:
    let fullPath = projectRoot / f
    if not fileExists(fullPath):
      logWarn(&"File not found, skipping: {f}")
      continue
    inc total
    let (output, exitCode) = runCmdWithCode(BinNim,
      args = @["check", "--hints:off", fullPath], env=env)
    if exitCode == 0:
      logOk(&"nim check OK: {f}")
    else:
      logError(&"nim check FAILED: {f} (exit={exitCode})")
      # Show first 20 lines of error output
      let errLines = output.splitLines()
      for line in errLines[0 .. min(19, errLines.len - 1)]:
        echo &"    | {line}"
      inc failures

  # ── Phase 2: Full scan (all .nim in src/) ───────────────────────────────
  echo ""
  echo "── Phase 2: Full src/ directory scan ──"
  var srcFiles: seq[string] = @[]
  for kind, path in walkDir(projectRoot / "src", relative=false):
    if kind == pcFile and path.endsWith(".nim"):
      srcFiles.add(path)
  srcFiles.sort()

  for f in srcFiles:
    inc total
    let relPath = f.replace(projectRoot & "/", "")
    let (output, exitCode) = runCmdWithCode(BinNim,
      args = @["check", "--hints:off", f], env=env)
    if exitCode == 0:
      logOk(&"nim check OK: {relPath}")
    else:
      logError(&"nim check FAILED: {relPath} (exit={exitCode})")
      let errLines = output.splitLines()
      for line in errLines[0 .. min(9, errLines.len - 1)]:
        echo &"    | {line}"
      inc failures

  # ── Phase 3: ci_engine self-check ───────────────────────────────────────
  echo ""
  echo "── Phase 3: ci_engine self-check ──"
  inc total
  let (_, selfExit) = runCmdWithCode(BinNim,
    args = @["check", "--hints:off", projectRoot / "tools" / "ci" / "ci_engine.nim"],
    env=env)
  if selfExit == 0:
    logOk("nim check OK: tools/ci/ci_engine.nim")
  else:
    logError("nim check FAILED: tools/ci/ci_engine.nim")
    inc failures

  # ── Summary ─────────────────────────────────────────────────────────────
  echo ""
  echo &"═══ Verification Complete ═══"
  echo &"  Total files checked: {total}"
  echo &"  Passed: {total - failures}"
  echo &"  Failed: {failures}"
  if failures > 0:
    logError(&"{failures} file(s) failed nim check")
    quit(1)
  else:
    logOk("All files passed nim check")

# ═══════════════════════════════════════════════════════════════════════════════
# §12: Main — Subcommand Dispatcher
# ═══════════════════════════════════════════════════════════════════════════════

proc main() =
  let args = commandLineParams()
  if args.len == 0:
    echo "Usage: ci_engine <bootstrap|provision|vendor|prune|verify>"
    echo ""
    echo "Subcommands:"
    echo "  bootstrap  CircleCI infrastructure initialization"
    echo "  provision  OS user isolation + cgroups + bubblewrap verification"
    echo "  vendor     tree-sitter C source vendoring"
    echo "  prune      Dead module pruning (dry-run)"
    echo "  verify     Build matrix verification"
    quit(1)

  case args[0]
  of "bootstrap": bootstrap()
  of "provision": provision()
  of "vendor": vendor()
  of "prune": prune()
  of "verify": verify()
  else:
    echo &"Unknown subcommand: {args[0]}"
    quit(1)

when isMainModule:
  main()
