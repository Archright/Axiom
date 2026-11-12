## BUG_FOUND mutant fixture — S6 of the nim-stew BUG_FOUND/NO_BUG_PROVED
## operational-verdict milestone. VERBATIM transcription of the sizing
## functions (stew/base36.nim:52-60, status-im/nim-stew v0.5.2) with ONE
## seeded mutation: the `+ 1` rounding increment in `encodedLength` is
## REMOVED. Under the committed P_rel overlay
## (config/spec/base36_sizing_relational_spec.json) the mutation breaks the
## roundtrip equality at n=1: encodedLength(1) = (1*277) div 179 = 1 (the
## sound subject yields 2), decodedLength(1) = (1*179) div 277 = 0, so
## decodedLength(encodedLength(1)) = 0 != 1 (PR #579 evidence). The same
## pipeline that proves the golden pair
## (tests/golden/base36_subject/stew/base36.nim) must DISPROVE this subject:
## Lean kernel reject → BMC SAT → cvConfirmed promotion → replay agreement →
## PROPOSITION_DISPROVED payload. The real subject tree (nim-stew) stays READ-ONLY —
## Zero-Footprint; the mutant lives inside THIS repo and its git identity
## anchor is the Axiom commit that versions this fixture (measured, not
## labeled).
type Base36Types* = object

func encodedLength*(btype: typedesc[Base36Types], length: int): int =
  return (length * 277) div 179

func decodedLength*(btype: typedesc[Base36Types], length: int): int =
  return (length * 179) div 277
