import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import ../../core/trusted/axiom_pragmas
import core/domain_types
import core/json/std_redirect
import core/symbolic_types_expr
import std/sequtils
import std/strutils
# @axiom-hint: lean="baseDir.length ≥ 0 ∧ modulePath.length ≥ 0" smt="(assert (and (>= (str.len baseDir) 0) (>= (str.len modulePath) 0)))"
# @axiom-hint: lean="modulePath.length = 0 ∧ modulePath ∧ directCandidate ∧ candidate ∧ withSrc" smt="(assert (and (= (str.len modulePath) 0) modulePath directCandidate candidate withSrc))"
# axiomIoBoundary
# axiomIoBoundary


proc mergeInvariantCandidates*(
  primary: seq[SymSExpr];
  secondary: seq[SymSExpr]
): seq[SymSExpr] =
  var seen: seq[string] = @[]
  for candidate in primary:
    if candidate.isNil:
      continue
    let key = sExprToString(candidate)
    if key.len > 0 and key notin seen:
      seen.add(key)
      result.add(candidate)
  for candidate in secondary:
    if candidate.isNil:
      continue
    let key = sExprToString(candidate)
    if key.len > 0 and key notin seen:
      seen.add(key)
      result.add(candidate)



## axiom-smt: (assert (and (>= primary 0) (>= secondary 0) (forall ((primaryIdx Int)) (=> (and (>= primaryIdx 0) (< primaryIdx (seq.len primary))) (>= (str.len (seq.nth primary primaryIdx)) 0))) (forall ((secondaryIdx Int)) (=> (and (>= secondaryIdx 0) (< secondaryIdx (seq.len secondary))) (>= (str.len (seq.nth secondary secondaryIdx)) 0)))))
## axiom-lean: (primary ≥ 0) ∧ (secondary ≥ 0) ∧ (∀ (primaryIdx : Fin primary.size), (primary.get primaryIdx).length ≥ 0) ∧ (∀ (secondaryIdx : Fin secondary.size), (secondary.get secondaryIdx).length ≥ 0)
proc mergeStringEvidence*(primary: seq[string]; secondary: seq[string]): seq[string] {.axiom, axiomImpl.} =
  var seen: seq[string] = @[]
  for item in primary:
    if item.len > 0 and item notin seen:
      seen.add(item)
      result.add(item)
  for item in secondary:
    if item.len > 0 and item notin seen:
      seen.add(item)
      result.add(item)


## axiom-smt: (assert (and (>= (str.len raw) 0)))
## axiom-lean: raw.length ≥ 0
proc keyToStatus*(raw: string): CertificateStatus {.axiom, axiomImpl.} =
  ## Map a (possibly legacy) status string to a CertificateStatus.
  ## P0: only an explicit green marker may claim dual (Z3 ∧ Lean) assurance.
  ## Ambiguous legacy success strings ("verified"/"pass"/"passed"/"ok") carry no
  ## provenance tier by themselves — mapping them to certGreen would let Z3-only
  ## evidence overclaim dual assurance. They map to the neutral certPending; the
  ## caller (stage_02_fingerprint) reconciles the final status against stored
  ## evidence via the canonical certificateEvidenceFromJson → tierFromEvidence
  ## chain (docs/spec/verification_density.md).
  case raw.toLowerAscii()
  of "green", "certgreen":
    certGreen
  of "ok", "verified", "pass", "passed", "pending", "certpending", "review",
      "needs_review":
    certPending
  of "red", "certred", "failed", "fail":
    certRed
  of "stale", "certstale":
    certStale
  of "verifiedaxiom", "certverifiedaxiom", "axiom", "intrinsic", "certintrinsic":
    certVerifiedAxiom
  of "pseudoverified", "certpseudoverified", "pseudo_verified":
    certPseudoVerified
  of "certyellow", "yellow", "bounded", "partial":
    certYellow
  of "certno_obligation", "no_obligation", "noobligation":
    certNoObligation
  else:
    certRed


## axiom-smt: (assert (and (>= depth 0) (>= result 0)))
## axiom-lean: depth >= 0 ∧ (result ≥ 0)
proc toStringList*(node: JsonNode): seq[string] {.axiomOpaque.} =
  if node.kind == JArray:
    for item in node.elems:
      if item.kind == JString:
        result.add(item.getStr().strip())
  result = result.filterIt(it.len > 0).deduplicate()


## axiom-smt: (assert (and (>= (seq.len keys) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len keys))) (>= (str.len (seq.nth keys i)) 0))) (> (str.len value) 0) value (=> (> (str.len value) 0) (= result value)) (>= keys 0) (forall ((keysIdx Int)) (=> (and (>= keysIdx 0) (< keysIdx (seq.len keys))) (>= (str.len (seq.nth keys keysIdx)) 0)))))
## axiom-lean: keys.size ≥ 0 ∧ ∀ (i : Fin keys.size), (keys.get i).length ≥ 0 ∧ value.length > 0 ∧ value ∧ value.length > 0 → result = value ∧ (keys ≥ 0) ∧ (∀ (keysIdx : Fin keys.size), (keys.get keysIdx).length ≥ 0)
proc firstStringField*(node: JsonNode; keys: seq[string]): string {.axiom, axiomImpl.} =
  for key in keys:
    if node.hasKey(key) and node.getOrDefault(key).kind == JString:
      let value = node.getOrDefault(key).getStr().strip()
      if value.len > 0:
        return value
  ""


## CONTRACT-AUDIT Case B (sound — tautological post): for any bool candidate,
## returning `true` satisfies `result == true`; returning `defaultValue` satisfies
## `result == defaultValue`. No reachable input can violate the post. The CHC
## discharge for this obligation is a routing/encoding artifact, not a real bug.
## See docs/spec/cfg_contract_specification.md.
func firstBoolCore*(candidates: seq[bool]; defaultValue: bool): bool {.
  axiom, axiomImpl, axiom: [post: (candidates.len == 0 and result == defaultValue) or (candidates.len > 0 and result == candidates[0])]
.} =
  ## Pure bool core: returns the value of the first candidate, or defaultValue
  ## when there are no candidates. An explicit `false` is read as `false`.
  if candidates.len > 0:
    candidates[0]
  else:
    defaultValue

## axiom-smt: (assert (and (>= (seq.len keys) 0) (forall ((keysIdx Int)) (=> (and (>= keysIdx 0) (< keysIdx (seq.len keys))) (>= (str.len (seq.nth keys keysIdx)) 0))) (or (= defaultValue true) (= defaultValue false)) (>= keys 0) (forall ((keysIdx Int)) (=> (and (>= keysIdx 0) (< keysIdx (seq.len keys))) (>= (str.len (seq.nth keys keysIdx)) 0))) (or (= defaultValue true) (= defaultValue false))))
## axiom-lean: keys.size ≥ 0 ∧ (∀ (keysIdx : Fin keys.size), (keys.get keysIdx).length ≥ 0) ∧ defaultValue = true ∨ defaultValue = false ∧ (keys ≥ 0) ∧ (∀ (keysIdx : Fin keys.size), (keys.get keysIdx).length ≥ 0) ∧ defaultValue = true ∨ defaultValue = false
func firstBoolField*(node: JsonNode; keys: seq[string]; defaultValue: bool): bool {.
  axiomOpaque
.} =
  var candidates: seq[bool] = @[]
  for key in keys:
    if node.hasKey(key):
      let v = node[key]
      case v.kind
      of JBool: candidates.add(v.getBool(defaultValue))
      of JInt: candidates.add(v.getInt(0) != 0)
      else: discard
  firstBoolCore(candidates, defaultValue)


## axiom-smt: (assert (and (>= (seq.len keys) 0) (forall ((keysIdx Int)) (=> (and (>= keysIdx 0) (< keysIdx (seq.len keys))) (>= (str.len (seq.nth keys keysIdx)) 0))) (> (str.len values) 0) values (=> (> (str.len values) 0) (= result values)) (>= keys 0) (forall ((keysIdx Int)) (=> (and (>= keysIdx 0) (< keysIdx (seq.len keys))) (>= (str.len (seq.nth keys keysIdx)) 0)))))
## axiom-lean: keys.size ≥ 0 ∧ (∀ (keysIdx : Fin keys.size), (keys.get keysIdx).length ≥ 0) ∧ values.length > 0 ∧ values ∧ values.length > 0 → result = values ∧ (keys ≥ 0) ∧ (∀ (keysIdx : Fin keys.size), (keys.get keysIdx).length ≥ 0)
proc firstArrayField*(node: JsonNode; keys: seq[string]): seq[string] {.axiomOpaque.} =
  for key in keys:
    if node.hasKey(key):
      let values = toStringList(node.getOrDefault(key))
      if values.len > 0:
        return values
  @[]


## axiom-smt: (assert (and (>= depth 0)))
## axiom-lean: depth >= 0
proc isPreludeOnlyVerifiedAxiom*(cert: FunctionCertificate): bool {.axiom, axiomImpl.} =
  cert.status == certVerifiedAxiom and
    cert.reason == "verified-axiom:nim.ast.parse.failed.isolated"


## CONTRACT-AUDIT Case A (candidate unsound post): when defaultValue == 0
## and a negative non-zero candidate exists in the sequence (e.g. candidates = [-1]),
## the function returns that negative value while the post result >= defaultValue
## (i.e. -1 >= 0) is false. The post can be violated by a reachable input.
## Do NOT weaken the contract in this commit — a deliberate spec-approval step
## follows. See docs/spec/cfg_contract_specification.md.
func firstIntCore*(candidates: seq[int]; defaultValue: int): int {.
  axiom, axiomImpl, axiom: [post: (result >= defaultValue)]
.} =
  ## Pure integer core: returns the first non-zero candidate, or defaultValue.
  for c in candidates:
    if c != 0:
      return c
  defaultValue

## axiom-smt: (assert (and (>= (seq.len keys) 0) (forall ((keysIdx Int)) (=> (and (>= keysIdx 0) (< keysIdx (seq.len keys))) (>= (str.len (seq.nth keys keysIdx)) 0))) (and (>= defaultValue -9223372036854775808) (<= defaultValue 9223372036854775807)) (>= keys 0) (forall ((keysIdx Int)) (=> (and (>= keysIdx 0) (< keysIdx (seq.len keys))) (>= (str.len (seq.nth keys keysIdx)) 0)))))
## axiom-lean: keys.size ≥ 0 ∧ (∀ (keysIdx : Fin keys.size), (keys.get keysIdx).length ≥ 0) ∧ defaultValue ≥ -9223372036854775808 ∧ defaultValue ≤ 9223372036854775807 ∧ (keys ≥ 0) ∧ (∀ (keysIdx : Fin keys.size), (keys.get keysIdx).length ≥ 0)
func firstIntField*(node: JsonNode; keys: seq[string]; defaultValue: int = 0): int {.
  axiomOpaque
.} =
  var candidates: seq[int] = @[]
  for key in keys:
    if node.hasKey(key):
      let v = node[key]
      case v.kind
      of JInt: candidates.add(v.getInt(defaultValue))
      of JFloat: candidates.add(int(v.getFloat(defaultValue.float)))
      else: discard
  firstIntCore(candidates, defaultValue)

# @axiom-hint: lean="baseDir.length ≥ 0 ∧ modulePath.length ≥ 0" smt="(assert (and (>= (str.len baseDir) 0) (>= (str.len modulePath) 0)))"
# @axiom-hint: lean="modulePath.length = 0 ∧ modulePath ∧ directCandidate ∧ candidate ∧ withSrc" smt="(assert (and (= (str.len modulePath) 0) modulePath directCandidate candidate withSrc))"


{.pop.}

