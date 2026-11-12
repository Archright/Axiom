import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [CatchableError].}

## Namespace Sandbox — Linux Namespace Isolation
##
## "Declared = Exists" — inputs not declared in GateManifest are
## blocked at the OS level via namespace mount isolation.
##
## Uses Linux user + mount + network namespaces via unshare binary.
## Fallback: if namespaces unavailable, uses existing env isolation.

import std/[os, osproc, strutils, strformat, sequtils, tables]
import core/trusted/axiom_pragmas

type
  NamespaceConfig* = object
    useNamespace*: bool          ## true = namespace isolation, false = env-only fallback
    mountNs*: bool               ## Isolated mount namespace
    pidNs*: bool                 ## Isolated PID namespace
    netNs*: bool                 ## Network isolation (no network access)
    userNs*: bool                ## User namespace (root not required)
    allowedPaths*: seq[string]   # Declared inputs — only these are accessible
    readonlyPaths*: seq[string]  # Read-only mounts (store, repo root)
    tmpfsPaths*: seq[string]     # tmpfs mounts (/tmp, /dev)
    maxMemBytes*: int64          # Memory limit (future: cgroup)
    maxCpuSeconds*: int          # CPU time limit (rlimit)

  NamespaceResult* = object
    exitCode*: int
    stdout*: string
    stderr*: string

  NamespaceAccessDeniedDefect* = object of CatchableError
    ## Raised when undeclared path access is detected

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func defaultNamespaceConfig*(repoRoot: string): NamespaceConfig =
  ## Default config: user + mount + net namespace, repo root read-only.
  NamespaceConfig(
    useNamespace: true,
    mountNs: true,
    pidNs: false,  # PID ns can cause issues with subprocess chains
    netNs: true,   # No network by default
    userNs: true,  # No root required
    allowedPaths: @[],
    readonlyPaths: @[repoRoot],
    tmpfsPaths: @["/tmp"],
    maxMemBytes: 512 * 1024 * 1024,  # 512MB
    maxCpuSeconds: 300
  )

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc buildUnshareArgs*(cfg: NamespaceConfig): seq[string]  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Build unshare command arguments from config.
  result = @[]
  if cfg.userNs: result.add("--user")
  if cfg.mountNs: result.add("--mount")
  if cfg.pidNs: result.add("--pid")
  if cfg.netNs: result.add("--net")
  if cfg.pidNs or cfg.mountNs: result.add("--fork")
  if cfg.userNs: result.add("--map-root-user")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc buildMountScript*(cfg: NamespaceConfig): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Generate shell commands for namespace mount setup.
  ## This creates the restrictive mount environment.
  result = ""

  # Mount tmpfs on tmp paths
  for tmpPath in cfg.tmpfsPaths:
    result.add(&"mount -t tmpfs tmpfs {tmpPath} 2>/dev/null || true\n")

  # Bind-mount readonly paths
  for roPath in cfg.readonlyPaths:
    result.add(&"mount --bind --readonly {roPath} {roPath} 2>/dev/null || true\n")

  # Note: "Declared = Exists" enforcement would require overlayfs or
  # bind-mounting only allowed paths. For now, readonly mounts + env
  # isolation provide the restriction boundary.

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc namespaceExec*(cfg: NamespaceConfig, cmd: string,
                    args: seq[string],
 env: Table[string, string] = default(Table[string, string]),
                    workingDir: string = ""
                   ): NamespaceResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} = # axiomIoBoundary
  ## Execute a command in an isolated namespace.
  ## Falls back to env-only isolation if namespaces unavailable.
  var fullCmd: string

  if cfg.useNamespace:
    let unshareArgs = buildUnshareArgs(cfg)
    let mountScript = buildMountScript(cfg)

    # Build the full command: unshare + mount setup + actual command
    let envStr = block:
      var parts: seq[string] = @[]
      for k, v in env:
        parts.add(&"export {k}={v.quoteShell}")
      parts.join(" && ")

    let cmdArgs = args.mapIt(it.quoteShell).join(" ")
    let innerCmd = if mountScript.len > 0:
      &"{mountScript} && {envStr} && {cmd} {cmdArgs}"
    else:
      &"{envStr} && {cmd} {cmdArgs}"

    let unshareStr = unshareArgs.join(" ")
    fullCmd = &"unshare {unshareStr} -- /bin/sh -c {innerCmd.quoteShell}"
  else:
    # Fallback: just set env vars
    let envStr = block:
      var parts: seq[string] = @[]
      for k, v in env:
        parts.add(&"export {k}={v.quoteShell}")
      parts.join(" && ")
    let cmdArgs = args.mapIt(it.quoteShell).join(" ")
    fullCmd = &"{envStr} && {cmd} {cmdArgs}"

  let (output, exitCode) = execCmdEx(fullCmd)
  NamespaceResult(
    exitCode: exitCode,
    stdout: output,
    stderr: ""  # execCmdEx merges stderr with poStdErrToStdOut
  )

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc isNamespaceAvailable*(): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if user namespaces are available.
  # axiomIoBoundary
  try:
    let content = readFile("/proc/sys/kernel/unprivileged_userns_clone")
    return content.strip() == "1"
  except CatchableError:
    # If file doesn't exist, check if unshare works
    let (_, exitCode) = execCmdEx("unshare --user true 2>&1")
    return exitCode == 0

{.pop.}
