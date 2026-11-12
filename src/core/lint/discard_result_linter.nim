# axiom:theater-prevention(DEBT# theater signature #2: swallowed failure via discard)
## AST-based linter: detects `discard` of Result[T, E] return values.
## Exempts procs annotated with {.discardable.} — those are intentionally
## fire-and-forget by design, so discarding their Result is not theater.
## Also exempts discard statements carrying the {.bestEffort.} pragma,
## which serves as the compile-time equivalent of the `# axiom:best-effort(...)`
## comment annotation used by the static scanner (check_nim_theater.nim S4).
##
## Usage: wrap proc/func blocks with `checkDiscardResult:` macro.
## Integration: imported into io_executor.nim and any module that calls
## Result-returning procs where discard might occur.
##
## To exempt a specific discard site at compile-time:
##   discard { .bestEffort("cleanup-path"). } someProc()
## Or annotate the returning proc with {.discardable.} if fire-and-forget is
## the intentional API contract.

import core/trusted/layer_declaration
axiomLayer "domain"
import std/macros
import std/strutils

# Local copy of results.isResultType — this module is globally injected via
# switch("import", ...), so importing core/types/results would create a
# bidirectional cycle (results → layer_declaration → injected linter) that
# breaks compile-time symbol resolution. The guard is 10 lines of pure
# NimNode logic shared with results.nim's `??` macro.
func isResultType(typeNode: NimNode): bool =
  if typeNode.kind == nnkBracketExpr:
    let head = typeNode[0]
    if head.kind == nnkIdent:
      head.eqIdent("Result")
    elif head.kind == nnkSym:
      $head == "Result"
    else:
      let reprStr = head.repr
      reprStr.endsWith("Result") and
        (reprStr.len == "Result".len or reprStr[^7] == '.')
  else: false
{.used.}

# ---------------------------------------------------------------------------
# Two-pass strategy: std/macros cannot resolve symbols to pragmas directly,
# so we (1) collect discardable proc names from definitions, then
# (2) skip flagging discard of calls matching those names.
# ---------------------------------------------------------------------------

proc collectDiscardableNames(node: NimNode; acc: var seq[string]) =
  ## Recursively walk the AST and collect names of proc/func definitions
  ## that carry the {.discardable.} pragma. Works entirely with NimNode.
  if node.kind in {nnkProcDef, nnkFuncDef}:
    # First child is the name identifier
    if node.len > 0 and node[0].kind in {nnkIdent, nnkSym}:
      let name = $node[0]
      # Check pragma list for {.discardable.}
      for i in 0 ..< node.len:
        let child = node[i]
        if child.kind == nnkPragma:
          for j in 0 ..< child.len:
            if child[j].kind in {nnkIdent, nnkSym} and $child[j] == "discardable":
              acc.add(name)
              break
  for i in 0 ..< node.len:
    collectDiscardableNames(node[i], acc)

proc extractCallTargetName(call: NimNode): string =
  ## Extract the proc name from a call/expression node.
  ## Handles bare identifiers, dot-expressions (mod.proc), and calls.
  case call.kind
  of nnkDotExpr:
    # mod.proc — take the rightmost part
    result = $call[^1]
  of nnkIdent, nnkSym:
    result = $call
  of nnkCall, nnkCallStrLit:
    # First element is the target proc
    result = extractCallTargetName(call[0])
  else:
    result = ""

proc scanForDiscardResultViolations(n: NimNode; discardableProcs: openArray[string]) =
  ## Flags `discard <expr>` where `<expr>` has a Result-returning type,
  ## UNLESS the expression is a call to a proc marked {.discardable.}
  ## OR the discard carries a {.bestEffort.} pragma (compile-time exempt).
  ##
  ## Theater prevention: catches swallowed-failure pattern (#2) while
  ## respecting intentional fire-and-forget APIs via two exemption paths:
  ##   1. Proc-level: {.discardable.} on the called proc definition
  ##   2. Site-level: {.bestEffort("reason").} on the discard call site
  ##
  ## NOTE: This macro runs in WARNING mode (not error mode) to avoid
  ## breaking the build when globally activated. The 97 existing best-effort
  ## I/O sites are documented in data/discarded_result_sites.txt and should
  ## carry `# axiom:best-effort(...)` comments. Hard-fail can be enabled by
  ## changing `warning()` to `error()` below after remediation.
  if n.kind == nnkDiscardStmt and n.len >= 1:
    let expr = n[0]
    # Bare `discard` (no argument) — never a Result discard.
    if expr.kind == nnkEmpty: return
    # Check for {.bestEffort.} pragma directly on the discard statement.
    # The AST structure is: nnkDiscardStmt → nnkPragmaExpr(pragmas, expr)
    # or: nnkDiscardStmt → nnkCall/mod.proc(...)
    if expr.kind == nnkPragmaExpr and expr.len >= 2:
      # Check if any pragma is "bestEffort"
      let pragmas = expr[0]
      if pragmas.kind == nnkPragma:
        for p in pragmas:
          if p.kind in {nnkIdent, nnkSym} and $p == "bestEffort":
            return  # Explicitly exempted at this call site
    # Skip calls to {.discardable.} procs — intentionally fire-and-forget.
    let targetName = extractCallTargetName(expr)
    if targetName.len > 0:
      for dp in discardableProcs:
        if targetName == dp: return
    try:
      if isResultType(expr.getTypeInst()):
        warning("DEBT PREVENTION [S4-critical-write]: discard of Result-returning call at " & expr.lineInfo &
                ". Use `??` or handle the Result explicitly. " &
                "(If this discard is intentional best-effort I/O, add either:\n" &
                "  - {.bestEffort(\"reason\").} pragma on the call, or\n" &
                "  - `# axiom:best-effort(reason)` comment on the same line\n" &
                "(If the proc is intentionally fire-and-forget, annotate it with {.discardable.}). " &
                "See src/core/lint/discard_result_linter.nim)", expr)
    except CatchableError as e:
      warning("discard_result_linter: type check failed at " & expr.lineInfo & " — " & e.msg)
  for i in 0 ..< n.len:
    scanForDiscardResultViolations(n[i], discardableProcs)

macro checkDiscardResult*(body: typed): untyped =
  ## Compile-time linter: flags `discard` of a call/expression whose type is
  ## `Result[...]`. String-literal discards are naturally whitelisted because
  ## their type is `string`, not a Result.
  ##
  ## Two-pass detection:
  ##   Pass 1 — scan body for proc/func defs with {.discardable.} pragma
  ##   Pass 2 — flag discard(Result) unless caller is in the discardable set
  ##
  ## NOTE: wrap only `proc`/`func` definitions (or blocks of them). Placing
  ## `type`/`var`/`concept` definitions inside this macro corrupts re-typecheck
  ## of the returned typed tree.
  var discardableProcs: seq[string] = @[]
  collectDiscardableNames(body, discardableProcs)
  scanForDiscardResultViolations(body, discardableProcs)
  result = body

