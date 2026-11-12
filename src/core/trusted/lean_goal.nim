import core/trusted/layer_declaration
axiomLayer "trusted.core.lean-goal"

{.push raises: [].}
## LeanGoal — sectioned Lean 4 module renderer.
##
## Pure-functional: every function is `func` with `{.raises: [].}`.
##
## Import hygiene invariant (fixes the duplicate-import syntax bug):
## `import` commands are emitted in EXACTLY ONE place — the header section,
## renderHeaderImports. Every other section (namespace, theorem declaration,
## proof, end) is import-free by construction, so a generated module can
## never contain an `import` after the first `def`/`theorem` — which Lean
## rejects with "invalid import command, must be used in the beginning of
## the file".

import std/algorithm
import std/strutils

const
  leanInitImport* = "Init"
  leanBvDecideImport* = "Std.Tactic.BVDecide"
  leanNamespaceName* = "Axiom"

type
  LeanGoal* = object
    obligationId*: string         ## C4 obligation identity; "" = legacy naming mode
    theoremName*: string          ## base name of the generated theorem
    assumptions*: seq[string]     ## hypothesis binders, each "name : type"
    proposition*: string          ## target proposition (Lean term)
    proofScript*: string          ## proof body, verbatim (typically starts with "by")
    requiredImports*: seq[string] ## module names WITHOUT the "import " prefix

func makeLeanGoal*(theoremName: string;
                   proposition: string;
                   proofScript: string = "by sorry";
                   assumptions: seq[string] = @[];
                   requiredImports: seq[string] = @[];
                   obligationId: string = ""): LeanGoal {.raises: [].} =
  ## Construct a LeanGoal. An empty obligationId selects legacy theorem
  ## naming (`theorem <theoremName>`); a non-empty id selects obligation
  ## naming (`theorem obligation_<obligationId>`).
  LeanGoal(
    obligationId: obligationId,
    theoremName: theoremName,
    assumptions: assumptions,
    proposition: proposition,
    proofScript: proofScript,
    requiredImports: requiredImports,
  )

func goalTheoremName*(goal: LeanGoal): string {.raises: [].} =
  ## Resolve the emitted theorem name: `obligation_<obligationId>` when an
  ## obligation id is bound, else the plain `theoremName`.
  if goal.obligationId.len > 0:
    "obligation_" & goal.obligationId
  else:
    goal.theoremName

# ---------------------------------------------------------------------------
# Section renderers — one function per section. Only the header section
# (renderHeaderImports) may emit `import` commands.
# ---------------------------------------------------------------------------

func renderHeaderImports*(requiredImports: seq[string]): string {.raises: [].} =
  ## Emit the ONLY import section of a generated Lean module.
  ## Order: `import Init`, then `import Std.Tactic.BVDecide` when required,
  ## then the remaining imports — deduplicated and sorted for determinism.
  var extra: seq[string] = @[]
  for imp in requiredImports:
    if imp.len == 0: continue
    if imp == leanInitImport or imp == leanBvDecideImport: continue
    if imp in extra: continue
    extra.add(imp)
  extra.sort()
  result = "import " & leanInitImport & "\n"
  if leanBvDecideImport in requiredImports:
    result.add("import " & leanBvDecideImport & "\n")
  for imp in extra:
    result.add("import " & imp & "\n")
  result.add("\n")

func renderNamespaceOpen*(): string {.raises: [].} =
  "namespace " & leanNamespaceName & "\n"

func renderNamespaceClose*(): string {.raises: [].} =
  "end " & leanNamespaceName & "\n"

func renderTheorem*(goal: LeanGoal): string {.raises: [].} =
  ## Emit the theorem declaration: `theorem <name> (h1 : T1) ... : Prop :=`.
  ## NEVER emits imports — import hygiene is owned exclusively by
  ## renderHeaderImports.
  result = "theorem " & goalTheoremName(goal)
  for a in goal.assumptions:
    result.add(" (" & a & ")")
  result.add(" : " & goal.proposition & " :=\n")

func renderProof*(goal: LeanGoal): string {.raises: [].} =
  ## Emit the proof body verbatim (caller-supplied indentation; typically
  ## starts with `by`). NEVER emits imports.
  goal.proofScript

func renderEnd*(goal: LeanGoal): string {.raises: [].} =
  ## Emit the closing `#print axioms <name>` command — TARGETED at the
  ## generated declaration, never the bare `#print axioms`.
  "#print axioms " & goalTheoremName(goal) & "\n"

func renderLeanModule*(goal: LeanGoal): string {.raises: [].} =
  ## Compose a complete Lean 4 module from the goal sections, in fixed
  ## order: header imports → namespace open → theorem declaration → proof →
  ## targeted `#print axioms` → namespace close. Imports appear ONLY in the
  ## header section.
  result = renderHeaderImports(goal.requiredImports)
  result.add(renderNamespaceOpen())
  result.add(renderTheorem(goal))
  result.add(renderProof(goal))
  if not result.endsWith("\n"):
    result.add("\n")
  result.add(renderEnd(goal))
  result.add(renderNamespaceClose())

{.pop.}