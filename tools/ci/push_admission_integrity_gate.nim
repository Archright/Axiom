## push_admission_integrity_gate.nim — Declared == Executed set equality
## for the push-admissibility thin target (DEBT#534 + DEBT#535).
##
## DEBT#534: the push-admissibility recipe ended with
## `PASS: $(PUSH_ADMISSIBILITY_GATES) green (snapshot)` while the recipe body
## never invoked check-merge-admission-cert-mirror — the only occurrence of
## that name in a full run was the summary line itself. A declared-but-unrun
## gate appeared in a PASS string: the summary certified a set the run did
## not evaluate.
## DEBT#535: check-push-admissibility-integrity only asserted membership of
## the declared names in GATES_FAST ∪ GATES_STATIC ∪ GATES_FULL (+4
## push-only names) and was invoked from nowhere — so the drift above was
## undetectable by construction.
##
## Invariant enforced here (both directions, as SETS):
##   Declared  = PUSH_ADMISSIBILITY_GATES (make-expanded, passed via
##               --declared by the Makefile target — never text-parsed)
##   Executed  = the gate invocations of the push-admissibility recipe,
##               declared ON the invocation lines themselves as trailing
##               `# @pushGate <gate-name>` comments.
## The marker lives on the line that invokes the gate, so removing or adding
## an invocation removes or adds its marker with it: the recipe is the single
## source of the executed set. The summary line of push-admissibility prints
## the executed set EMITTED by this gate (`--executed-summary`), never the
## declaration — so a declared-but-unrun gate can no longer appear in a PASS
## string even if this integrity check is bypassed.
##
## Additional structural checks (fail-closed):
##   - every gate-class `$(MAKE) --no-print-directory <t>` sub-make in the
##     recipe must carry a @pushGate marker equal to <t> (a sub-make
##     self-identifies its target; a mismatching marker is drift);
##   - unmarked gate-class sub-makes FAIL ("unaccounted" execution);
##   - the recipe must invoke check-push-admissibility-integrity itself —
##     the audited path runs its own auditor; deleting the auditor from the
##     recipe is detected by every later invocation of this gate, including
##     the summary emission;
##   - duplicate markers FAIL (strict set semantics);
##   - (integrity mode) every declared name must be in the gate universe
##     GATES_FAST ∪ GATES_STATIC ∪ GATES_FULL + the push-only names — the
##     membership check DEBT#535 found toothless, kept as a secondary
##     assertion behind the primary set-equality check.
##
## Residual limitation (documented, not hidden): the marker ties a RECIPE
## LINE to a declared gate name. It cannot prove the marked line's command
## semantically IS that gate — for sub-make invocations the target name is
## cross-checked syntactically, for direct-binary invocations (check-debt's
## heredoc, the direct bin/ calls) the marker is the tie. Deliberately
## mislabeling a non-gate line is still possible and remains a review-level
## concern, same class as any hand-written annotation.
##
## Usage:
##   Integrity (make check-push-admissibility-integrity):
##     bin/push_admission_integrity_gate \
##       --declared "$(PUSH_ADMISSIBILITY_GATES)" \
##       [--universe "$(GATES_FAST) $(GATES_STATIC) $(GATES_FULL) <push-only...>"] \
##       [--makefile <path>]
##   Emission (push-admissibility summary line):
##     bin/push_admission_integrity_gate --executed-summary [--makefile <path>]
##
## Exit codes: 0 = PASS, 1 = FAIL (drift or fail-closed), 2 = usage error.

import std/[os, strutils, sequtils, sets, algorithm]

const
  MarkerPrefix = "# @pushGate "
  SubmakePrefix = "$(MAKE) --no-print-directory "
  AuditedTarget = "push-admissibility"
  AuditorTarget = "check-push-admissibility-integrity"
  ## Non-gate sub-makes the audited recipe legitimately performs: the debt
  ## evaluator staging helper (VS-PUSH-1 snapshot closure) and this auditor
  ## itself (wired as the recipe's first step).
  ImplementationSubmakes = ["push-admissibility-debt-prereqs", AuditorTarget]

type
  IntegrityFail* = object of CatchableError

  RecipeFacts* = object
    ## Machine-derived facts of one push-admissibility recipe.
    executedOrder*: seq[string]     ## @pushGate names, recipe order, unique
    gateSubmakes*: int              ## gate-class $(MAKE) invocations seen
    implSubmakes*: int              ## implementation-surface invocations seen
    auditorWired*: bool             ## recipe invokes check-push-admissibility-integrity

proc fail*(msg: string): ref IntegrityFail =
  result = newException(IntegrityFail, msg)

proc takeToken(s: string): tuple[token, rest: string] =
  ## First whitespace-delimited token of `s` plus the remainder.
  var j = 0
  while j < s.len and s[j] notin {' ', '\t', '\r', '\n'}:
    inc j
  (s[0 ..< j], s[j .. ^1])

proc namesWithPrefix(line, prefix: string): seq[string] =
  ## Every `<name>` of each occurrence of `prefix<name>` in `line`.
  var rest = line
  while true:
    let i = rest.find(prefix)
    if i < 0:
      break
    let after = i + prefix.len
    if after >= rest.len:
      raise fail("malformed marker: '" & prefix & "' at end of line with no name")
    rest = rest[after .. ^1]
    let (tok, tail) = takeToken(rest)
    if tok.len == 0:
      raise fail("malformed marker: '" & prefix & "' followed by whitespace only")
    result.add(tok)
    rest = tail

proc markersIn*(line: string): seq[string] =
  namesWithPrefix(line, MarkerPrefix)

proc submakesIn*(line: string): seq[string] =
  namesWithPrefix(line, SubmakePrefix)

proc logicalRecipeLines*(makefilePath: string): seq[string] =
  ## The push-admissibility recipe as logical lines (backslash continuations
  ## kept together), in file order. Fail-closed: a missing file, a missing
  ## target, or an empty recipe are integrity failures, never empty results.
  if not fileExists(makefilePath):
    raise fail("makefile not found: " & makefilePath)
  let head = AuditedTarget & ":"
  var started = false
  var phys: seq[string] = @[]
  for ln in readFile(makefilePath).splitLines():
    if not started:
      if ln.startsWith(head) and
          (ln.len == head.len or ln[head.len] in {' ', '\t', '#'}):
        started = true
    elif ln.len > 0 and ln[0] == '\t':
      phys.add(ln)
    else:
      # GNU make semantics (measured): blank lines and column-0 comment
      # lines do NOT terminate a recipe — they are stripped/ignored; only a
      # content-bearing non-tab line ends it.
      var content = ln
      let h = content.find('#')
      if h >= 0:
        content = content[0 ..< h]
      if content.strip().len == 0:
        continue
      break
  if not started:
    raise fail("target '" & head & "' not found in " & makefilePath)
  if phys.len == 0:
    raise fail("recipe of push-admissibility is empty in " & makefilePath)
  var acc = ""
  for p in phys:
    acc = if acc.len == 0: p else: acc & "\n" & p
    if p.endsWith("\\"):
      continue
    result.add(acc)
    acc = ""
  if acc.len > 0:
    raise fail("push-admissibility recipe ends inside an open continuation")

proc recipeFacts*(makefilePath: string): RecipeFacts =
  ## Derive the executed set and sub-make accounting from the recipe text.
  let lines = logicalRecipeLines(makefilePath)
  var seen: HashSet[string]
  for L in lines:
    let ms = markersIn(L)
    if ms.len > 1:
      raise fail("multiple @pushGate markers on one logical recipe line: " &
        ms.join(", "))
    for s in submakesIn(L):
      if s in ImplementationSubmakes:
        inc result.implSubmakes
        if s == AuditorTarget:
          result.auditorWired = true
        continue
      inc result.gateSubmakes
      if ms.len == 0:
        raise fail("unaccounted sub-make '" & s & "' in the " & AuditedTarget &
          " recipe — every gate-class sub-make line needs a '" &
          MarkerPrefix & "<name>' marker")
      if ms[0] != s:
        raise fail("@pushGate marker '" & ms[0] &
          "' does not match its sub-make target '" & s & "'")
    for m in ms:
      if m in seen:
        raise fail("duplicate @pushGate marker '" & m & "'")
      seen.incl(m)
      result.executedOrder.add(m)
  if not result.auditorWired:
    raise fail(AuditorTarget & " is not invoked by the " & AuditedTarget &
      " recipe — the auditor must be wired into the path it audits (DEBT#535)")
  if result.executedOrder.len == 0:
    raise fail("no '" & MarkerPrefix & "<name>' markers found in the " &
      AuditedTarget & " recipe")

proc compareSets*(declared, executed: seq[string]): seq[string] =
  ## Human-readable drift report; empty seq = the sets are equal.
  let declaredSet = declared.toHashSet()
  let executedSet = executed.toHashSet()
  let declaredNotExecuted = sorted(toSeq(declaredSet - executedSet))
  if declaredNotExecuted.len > 0:
    result.add("DECLARED-BUT-NOT-EXECUTED (declared in PUSH_ADMISSIBILITY_GATES " &
      "with no '" & MarkerPrefix & "' invocation in the recipe — the summary " &
      "would claim a gate this run never evaluates; DEBT#534 class): " &
      declaredNotExecuted.join(", "))
  let executedNotDeclared = sorted(toSeq(executedSet - declaredSet))
  if executedNotDeclared.len > 0:
    result.add("EXECUTED-BUT-NOT-DECLARED (recipe invokes gates absent from " &
      "PUSH_ADMISSIBILITY_GATES): " & executedNotDeclared.join(", "))

proc outsideUniverse*(declared, universe: seq[string]): seq[string] =
  sorted(toSeq(declared.toHashSet() - universe.toHashSet()))

proc runIntegrity(makefilePath, declaredArg, universeArg: string) =
  let facts = recipeFacts(makefilePath)
  let declared = declaredArg.splitWhitespace()
  if declared.len == 0:
    raise fail("--declared is empty (PUSH_ADMISSIBILITY_GATES expanded to nothing)")
  var problems = compareSets(declared, facts.executedOrder)
  var universeNote = "not requested"
  if universeArg.len > 0:
    let outside = outsideUniverse(declared, universeArg.splitWhitespace())
    if outside.len > 0:
      problems.add("OUTSIDE-GATE-UNIVERSE (declared, but not in GATES_FAST/" &
        "GATES_STATIC/GATES_FULL or the push-only surface set): " &
        outside.join(", "))
    universeNote = "OK"
  if problems.len > 0:
    raise fail(problems.join(" | "))
  echo "[push-admission-integrity] PASS: declared == executed (" & $declared.len &
    " = " & $facts.executedOrder.len & "); sub-make accounting: " &
    $facts.gateSubmakes & " gate + " & $facts.implSubmakes &
    " implementation; universe membership: " & universeNote

proc runEmission(makefilePath: string) =
  ## Print the executed set (recipe order) for the PASS summary line. Carries
  ## every structural check — an emission failure suppresses the summary
  ## (fail-closed), so the summary can never certify an unaudited recipe.
  let facts = recipeFacts(makefilePath)
  echo facts.executedOrder.join(" ")

proc usage(): string =
  "usage: push_admission_integrity_gate --declared \"<gate names>\" " &
    "[--universe \"<gate universe>\"] [--makefile <path>]" &
    "\n       push_admission_integrity_gate --executed-summary [--makefile <path>]"

proc main() =
  var
    declared = ""
    universe = ""
    makefile = "Makefile"
    emission = false
  var i = 1
  while i <= paramCount():
    let a = paramStr(i)
    case a
    of "--declared":
      if i == paramCount(): echo usage(); quit 2
      declared = paramStr(i + 1); inc i
    of "--universe":
      if i == paramCount(): echo usage(); quit 2
      universe = paramStr(i + 1); inc i
    of "--makefile":
      if i == paramCount(): echo usage(); quit 2
      makefile = paramStr(i + 1); inc i
    of "--executed-summary":
      emission = true
    else:
      echo "[push-admission-integrity] FAIL: unknown argument: " & a
      echo usage()
      quit 2
    inc i
  try:
    if emission:
      runEmission(makefile)
    elif declared.len == 0:
      echo "[push-admission-integrity] FAIL: integrity mode requires --declared"
      echo usage()
      quit 2
    else:
      runIntegrity(makefile, declared, universe)
  except IntegrityFail as e:
    echo "[push-admission-integrity] FAIL: " & e.msg
    quit 1

main()
