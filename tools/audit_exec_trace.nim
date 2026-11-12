import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

## Audit strace execve trace against build_constraint policy.
##
## Usage:
##   audit_exec_trace <trace-file>
## Exit 0 if no violations, 1 otherwise.

import std/[os, strutils]
import policy/build_constraint

proc main() {.raises: [].} =
  let args = commandLineParams()
  if args.len < 1:
    stderr.writeLine("Usage: audit_exec_trace <trace-file>")
    quit(1)

  let path = args[0]
  if not fileExists(path):
    stderr.writeLine("[audit] Trace file not found: " & path)
    quit(0)

  var lines: seq[string] = @[]
  try:
    for line in lines(path):
      lines.add(line)
  except CatchableError:
    stderr.writeLine("[audit] Failed to read trace file: " & path)
    quit(1)

  let violations = auditExecTrace(lines)
  if violations.len > 0:
    stderr.writeLine("[audit] BUILD CONSTRAINT VIOLATIONS:")
    for v in violations:
      stderr.writeLine("  " & v)
    quit(1)

  stdout.writeLine("[audit] No build constraint violations.")
  quit(0)

when isMainModule:
  main()

{.pop.}
