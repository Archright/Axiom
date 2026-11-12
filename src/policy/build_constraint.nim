import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Build Constraint Policy
##
## Defines the sole external executables that the Axiom build system is
## permitted to invoke. Any attempt to execute a binary outside this list is a
## hard policy violation.
##
## This module is consumed by:
##   - bin/hermetic-build (runtime audit of strace/seccomp logs)
##   - config.nims (compile-time policy assertion)
##   - src/gate/runners/build_system_purity_gate (gate enforcement)

import std/[os, sets, strutils]

const
  AllowedExternalBinaries* = [
    "nim",
    "nimble",
    "lean",
    "lake",
    "z3",
    "git",
    "ssh",
    "scp",
    "docker",    # only for the hermetic-build wrapper on the host
    "strace",    # only for hermetic-build internal tracing
  ]

  ForbiddenInterpreterPatterns* = [
    "python3",
    "python",
    "bash",
    "sh",
    "dash",
    "perl",
    "ruby",
    "node",
  ]

func allowedBinarySet*(): HashSet[string] {.raises: [].} =
  ## Runtime set of allowed external binary names.
  for name in AllowedExternalBinaries:
    result.incl(name)

func isAllowedBinary*(name: string): bool {.raises: [].} =
  ## Check whether a binary name is on the allow-list.
  let base = name.extractFilename()
  result = base in allowedBinarySet()

func isForbiddenInterpreter*(name: string): bool {.raises: [].} =
  ## Check whether a binary name matches a forbidden interpreter.
  let base = name.extractFilename().toLowerAscii()
  for pat in ForbiddenInterpreterPatterns:
    if base == pat or base.endsWith("/" & pat):
      return true
  return false

func auditExecTrace*(traceLines: openArray[string]): seq[string] {.raises: [].} =
  ## Audit strace execve output and return violations.
  ## Expected trace line format (strace -e execve -f):
  ##   [pid] execve("/path/to/bin", ["arg0", ...], env[]) = N
  result = @[]
  for line in traceLines:
    let execIdx = line.find("execve(")
    if execIdx < 0:
      continue
    let pathStart = line.find("\"", execIdx)
    if pathStart < 0:
      continue
    let pathEnd = line.find("\"", pathStart + 1)
    if pathEnd < 0:
      continue
    let binaryPath = line[pathStart + 1 ..< pathEnd]
    let binaryName = binaryPath.extractFilename()

    if isForbiddenInterpreter(binaryPath):
      result.add("FORBIDDEN INTERPRETER: " & binaryPath)
    elif not isAllowedBinary(binaryName):
      result.add("DISALLOWED BINARY: " & binaryPath)

{.pop.}
