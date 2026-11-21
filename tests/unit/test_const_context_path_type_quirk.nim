## test_const_context_path_type_quirk.nim
##
## Regression test for docs/spec/nim_const_context_path_type_quirk.md
## (DEBT#453/#454/#455): compile-time path values — currentSourcePath() and
## instantiationInfo(-1, true).filename — cannot cross the compiler-magic
## consumption boundaries (staticRead, `static string` parameters) or std/os
## path algebra wrapped in LogicalPath (distinct string). Nim 2.2.10 has no
## structural subtyping for distinct types, so every boundary is plain-string.
##
## Quirk-dissolution detection: if a future toolchain makes any
## `not compiles(...)` check fail, the compiler has started accepting
## distinct-typed path values at these boundaries — the deferral rationale of
## DEBT#453/#454/#455 is gone and the debts must be re-evaluated (wrap
## introduction). Conversely, a failing baseline check means the current
## accepted pattern (artifact_determinism.md §2.4) is broken.
##
## Run: make test-fast-one T=tests/unit/test_const_context_path_type_quirk.nim

import std/[unittest, macros, os, strutils]
import core/utils/path_identity

macro macroBodyFilename(): string =
  ## instantiationInfo inside a macro BODY: Nim 2.2.10 resolves neither the
  ## const-evaluated nor the VM-evaluated filename (both "???", line 0) —
  ## docs/spec/nim_const_context_path_type_quirk.md §6.
  const f = instantiationInfo(-1, true).filename
  result = newStrLitNode(f)

macro acceptStaticPath(path: static string): untyped =
  ## Minimal form of the template→macro handoff consumers
  ## (axiomLayerGuardAutoImpl / enforceFacadePatternImpl / ...).
  discard

template templateHandoffPath(): string =
  ## Minimal form of the template-side caller-path computation
  ## (template expansion site resolves the real file).
  instantiationInfo(-1, true).filename

suite "Nim const-context path type quirk (DEBT#453/#454/#455)":

  test "baseline: string path compiles through every magic boundary":
    check compiles(block:
      const s = currentSourcePath()
      discard staticRead(s))
    check compiles(acceptStaticPath(templateHandoffPath()))
    check compiles(parentDir(currentSourcePath()))

  test "const initializer: direct distinct conversion compiles (constraint lives at consumption boundaries)":
    check compiles(LogicalPath(currentSourcePath()))
    check compiles(toLogical(PhysicalPath(currentSourcePath()), "/x"))

  test "staticRead rejects LogicalPath (DEBT#454 const-hash chain)":
    check not compiles(block:
      const w = LogicalPath(currentSourcePath())
      discard staticRead(w))

  test "static string macro parameter rejects LogicalPath (DEBT#455 handoff)":
    check not compiles(acceptStaticPath(LogicalPath(templateHandoffPath())))

  test "std/os path algebra rejects LogicalPath (DEBT#453 root resolution)":
    check not compiles(parentDir(LogicalPath(currentSourcePath())))
    check not compiles(parentDir(toLogical(PhysicalPath(currentSourcePath()), "/x")))

  test "explicit string() unwrap is the only way a wrapped value crosses staticRead":
    check compiles(block:
      const w = LogicalPath(currentSourcePath())
      discard staticRead(string(w)))

  test "macro body instantiationInfo is '???' (handoff pattern exists for this reason)":
    check macroBodyFilename() == "???"

  test "template expansion site resolves the real caller file":
    let f = templateHandoffPath()
    check f.len > 0
    check f != "???"
    check f.endsWith("test_const_context_path_type_quirk.nim")
