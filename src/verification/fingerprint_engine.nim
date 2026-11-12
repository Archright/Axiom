import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
{.pragma: axiomDenseProof.}
import std/sequtils
import std/strutils
import std/tables
import core/identity/axiom_identity

## Compact Whitespace.
## Kept for backward compatibility with callers that explicitly need
## newline-preserved compacting. Fingerprinting itself is delegated
## to AxiomIdentity.
# @axiom-hint: lean="raw.length ≥ 0" smt="(assert (and (>= (str.len raw) 0)))"
import core/utils/text_utils
# axiomIoBoundary

## Normalize Hash Fingerprint.
## Delegated to AxiomIdentity SSOT.
# @axiom-hint: lean="payload.length ≥ 0" smt="(assert (and (>= (str.len payload) 0)))"
func normalizeHashFingerprint*(payload: string): string =
  axiom_identity.computeAxiomFingerprint(payload)

## Compute Fingerprint.
## Delegated to AxiomIdentity SSOT.
# @axiom-hint: lean="(∀ (constraintsIdx : Fin constraints.size), (constraints.get constraintsIdx).length ≥ 0)" smt="(assert (and (forall ((constraintsIdx Int)) (=> (and (>= constraintsIdx 0) (< constraintsIdx (seq.len constraints))) (>= (str.len (seq.nth constraints constraintsIdx)) 0)))))"
func computeFingerprint*(functionBody: string; constraints: seq[string]): string =
  axiom_identity.computeAxiomFingerprint(functionBody, constraints)

## Compute Fingerprint Candidates.
## Delegated to AxiomIdentity SSOT tolerant candidate generator.
## engineSalt: when non-empty, appended to payload before hashing (platform-independent cache salt).
func computeFingerprintCandidates*(functionBody: string; constraints: seq[string]; engineSalt: string = ""): seq[string] =
  if engineSalt.len > 0:
    axiom_identity.computeAxiomFingerprintCandidates(functionBody, constraints, engineSalt)
  else:
    axiom_identity.computeAxiomFingerprintCandidates(functionBody, constraints)

# @axiom-hint: lean="s.length ≥ 0" smt="(assert (and (>= (str.len s) 0)))"
func isAllCapsIdent(s: string): bool =
  var hasAlpha = false
  for ch in s:
    if ch.isAlphaAscii():
      hasAlpha = true
      if not ch.isUpperAscii():
        return false
    elif ch in {'_', '0'..'9'}:
      discard
    else:
      return false
  hasAlpha

## I Protected CIdent.
# @axiom-hint: lean="ident.length = 0 ∧ ident = functionName ∧ true ∧ ident.length = 0 → result = true ∧ ident = functionName → result = true" smt="(assert (and (= (str.len ident) 0) (= ident functionName) true (=> (= (str.len ident) 0) (= result true)) (=> (= ident functionName) (= result true))))"
func isProtectedCIdent*(ident: string; functionName: string): bool =
  if ident.len == 0:
    return true
  if ident == functionName:
    return true
  if ident.startsWith("secp256k1_") or ident.startsWith("SECP256K1_"):
    return true
  if isAllCapsIdent(ident):
    return true
  ident in [
    "auto", "break", "case", "char", "const", "continue", "default", "do",
    "double", "else", "enum", "extern", "float", "for", "goto", "if", "inline",
    "int", "long", "register", "restrict", "return", "short", "signed",
    "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned",
    "void", "volatile", "while", "bool", "true", "false"
  ]

## Canonicalize CStructure.
# @axiom-hint: lean="body.length ≥ 0 ∧ functionName.length ≥ 0 ∧ ident.length ≥ 0" smt="(assert (and (>= (str.len body) 0) (>= (str.len functionName) 0) (>= (str.len ident) 0)))"
# @axiom-hint: lean="i + 1 < body.length ∧ i < body.length ∧ i = j ∧ (map ≥ 0) ∧ ((i ≥ 0) ∧ (i < body))" smt="(assert (and (< (+ i 1) (str.len body)) (< i (str.len body)) (= i j) (>= map 0) (and (>= i 0) (< i body))))"
func canonicalizeCStructure*(body: string; functionName: string): string =
  var map = initTable[string, string]()
  var nextId = 0

# @axiom-hint: lean="ident.length ≥ 0" smt="(assert (and (>= (str.len ident) 0)))"
# @axiom-hint: lean="(map ≥ 0)" smt="(assert (and (>= map 0)))"
  proc internIdent(ident: string): string =
    if map.hasKey(ident):
      return map.getOrDefault(ident)
    let rep = "id" & $nextId
    inc nextId
    map[ident] = rep
    rep

  var tokens: seq[string] = @[]
  var i = 0
  while i < body.len:
    let ch = body[i]
    if ch.isSpaceAscii():
      inc i
      continue
    if ch == '/' and i + 1 < body.len and body[i + 1] == '/':
      i += 2
      while i < body.len and body[i] != '\n':
        inc i
      continue
    if ch == '/' and i + 1 < body.len and body[i + 1] == '*':
      i += 2
      while i + 1 < body.len and not (body[i] == '*' and body[i + 1] == '/'):
        inc i
      if i + 1 < body.len:
        i += 2
      continue
    if ch.isAlphaAscii() or ch == '_':
      var j = i + 1
      while j < body.len and (body[j].isAlphaNumeric() or body[j] == '_'):
        inc j
      let ident = body[i ..< j]
      if isProtectedCIdent(ident, functionName):
        tokens.add(ident)
      else:
        tokens.add(internIdent(ident))
      i = j
      continue
    if ch.isDigit():
      var j = i + 1
      while j < body.len and (body[j].isDigit() or body[j] in {'x', 'X', 'a'..'f', 'A'..'F'}):
        inc j
      tokens.add(body[i ..< j])
      i = j
      continue
    tokens.add($ch)
    inc i
  tokens.join(" ")

## Compute Structural Fingerprint Candidates.
# @axiom-hint: lean="functionBody.length ≥ 0 ∧ constraints.size ≥ 0 ∧ (∀ (constraintsIdx : Fin constraints.size), (constraints.get constraintsIdx).length ≥ 0) ∧ functionName.length ≥ 0" smt="(assert (and (>= (str.len functionBody) 0) (>= (seq.len constraints) 0) (forall ((constraintsIdx Int)) (=> (and (>= constraintsIdx 0) (< constraintsIdx (seq.len constraints))) (>= (str.len (seq.nth constraints constraintsIdx)) 0))) (>= (str.len functionName) 0)))"
# @axiom-hint: lean="constraints.length > 0 ∧ (result ≥ 0) ∧ (∀ (constraintsIdx : Fin constraints.size), (constraints.get constraintsIdx).length ≥ 0)" smt="(assert (and (> (str.len constraints) 0) (>= result 0) (forall ((constraintsIdx Int)) (=> (and (>= constraintsIdx 0) (< constraintsIdx (seq.len constraints))) (>= (str.len (seq.nth constraints constraintsIdx)) 0)))))"
func computeStructuralFingerprintCandidates*(functionBody: string; constraints: seq[string]; functionName: string): seq[string] =
  var payload = canonicalizeCStructure(functionBody, functionName)
  if constraints.len > 0:
    payload.add("\n--constraints--\n")
    payload.add(constraints.join("\n"))
  let compactPayload = compactWhitespace(payload)
  result = @[
    normalizeHashFingerprint(payload),
    normalizeHashFingerprint(payload.toLowerAscii()),
    normalizeHashFingerprint(compactPayload),
    normalizeHashFingerprint(compactPayload.toLowerAscii())
  ].deduplicate()
{.pop.}

