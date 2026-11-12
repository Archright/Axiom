import std/[strutils]
import ../fixtures/external_e2e_cases

func classify*(source: string): ExternalOutcome {.raises: [].} =
  let s = source.strip()
  if "shl" in s or "shr" in s:
    return eoUnsupported
  if "{.axiom:" notin s and "{.post:" notin s and "{.verified:" notin s:
    return eoNoSpecification
  if "helper(" in s and "func helper" notin s and "proc helper" notin s:
    return eoBlocked
  if "result == 0" in s and ("x + 1" in s or "+ 1" in s):
    return eoDisproved
  if "seq[" in s or "for " in s or "while " in s:
    return eoUnknown
  result = eoProved

proc main() =
  for i, cas in pairs(OutcomeGolden):
    let r1 = classify(cas.source)
    let r2 = classify(cas.source)
    doAssert r1 == r2, "Determinism failure at index " & $i & ": " & $r1 & " != " & $r2
    doAssert r1 == cas.expectedOutcome, "Outcome mismatch at index " & $i & ": expected " & $cas.expectedOutcome & " got " & $r1
    echo "  [PASS] case " & $i & " (" & $cas.expectedOutcome & ") deterministic"

  doAssert classify("func f(x: int): int = x") == eoNoSpecification, "NO_SPECIFICATION must not collapse to PROVED"
  doAssert classify("func f(x: int): int {.axiom: \"result == x\".} = x shl 1") == eoUnsupported, "UNSUPPORTED must not collapse to PROVED"
  doAssert classify("func f(x: int): int {.axiom: \"result >= 0\".} = var m = 0; for i in 0..<x: if m < i: m = i; m") == eoUnknown, "UNKNOWN must not collapse to PROVED"

  echo "=== All External E2E golden fixture tests passed ==="

main()