import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import ../../core/trusted/axiom_pragmas
import core/types/pipeline_core_types
import core/utils/text_utils
import std/sequtils
import std/strutils
## Verification Engine String.
func verificationEngineString*(engine: VerificationEngine): string {.raises: [], axiom: ["(assert (and veZ3Smt2 veLean4Lsp veHybridRefinement))", "veZ3Smt2 ∧ veLean4Lsp ∧ veHybridRefinement"].} =
  case engine
  of veZ3Smt2:
    "z3-smt2"
  of veLean4Lsp:
    "lean4-lsp"
  of veHybridRefinement:
    "hybrid-refinement"

## Lean 4 reserved keywords that cannot be used as theorem/definition names.
const leanReservedKeywords* = ["def", "theorem", "lemma", "axiom", "inductive",
  "structure", "class", "instance", "where", "match", "if", "then", "else",
  "let", "fun", "forall", "exists", "import", "open", "namespace", "section",
  "variable", "variables", "universe", "universes", "notation", "infix", "prefix",
  "postfix", "macro", "syntax", "deriving", "partial", "private", "protected",
  "mutual", "with", "do", "return", "continue", "break", "for", "while", "try",
  "catch", "finally", "throw", "initialize", "builtin_initialize", "opaque",
  "abbrev", "example", "show", "have", "suffices", "by", "calc", "rewrite",
  "rw", "simp", "aesop", "trivial", "apply", "exact", "refine", "cases", "rcases",
  "obtain", "constructor", "injection", "subst", "induction", "generalize",
  "rename_i", "revert", "clear", "specialize", "use", "existsi", "left", "right",
  "split", "done", "skip", "stop", "repeat", "all_goals", "any_goals", "focus",
  "first", "try", "solve", "fail", "guard", "check", "set_option", "extends"]

## Sanitize Lean Identifier.
func sanitizeLeanIdentifier*(raw: string): string {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0) (= (str.len token) 0) (>= token 0)))", "raw.length ≥ 0 ∧ token.length = 0 ∧ (token ≥ 0)"].} =
  var token = sanitizeToken(raw).toLowerAscii()
  if token.len == 0:
    token = "symbol"
  ## Avoid Lean reserved keywords by appending a safe suffix.
  if token in leanReservedKeywords:
    token = token & "_thm"
  token

## Build Lean String Literal.
func buildLeanStringLiteral*(raw: string): string {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0)))", "raw.length ≥ 0"].} =
  "\"" & raw.replace("\\", "\\\\").replace("\"", "\\\"") & "\""

## Build Lean String List.
func buildLeanStringList*(items: seq[string]): string {.raises: [], axiom: ["(assert (and (= (str.len items) 0) (forall ((itemsIdx Int)) (=> (and (>= itemsIdx 0) (< itemsIdx (seq.len items))) (>= (str.len (seq.nth items itemsIdx)) 0)))))", "items.length = 0 ∧ (∀ (itemsIdx : Fin items.size), (items.get itemsIdx).length ≥ 0)"].} =
  if items.len == 0:
    return "[]"
  "[" & items.mapIt(buildLeanStringLiteral(it)).join(", ") & "]"

## Minimize Proof Path.
func minimizeProofPath*(tactic: string): seq[string] {.raises: [], axiom: ["(assert (and (= (str.len normalized) 0)))", "normalized.length = 0"].} =
  var seen: seq[string] = @[]
  for rawLine in tactic.splitLines():
    let normalized = rawLine.strip()
    if normalized.len == 0:
      continue
    if seen.len == 0 or seen[^1] != normalized:
      seen.add(normalized)
  seen

## Minimize Proof Tactic.
func minimizeProofTactic*(tactic: string): string {.raises: [], axiom: ["(assert (and (>= (str.len tactic) 0)))", "tactic.length ≥ 0"].} =
  minimizeProofPath(tactic).join("\n")

{.pop.}
