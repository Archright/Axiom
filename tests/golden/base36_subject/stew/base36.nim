## §2.1a synthesis fixture — VERBATIM transcription of the sizing functions
## (stew/base36.nim:52-60, status-im/nim-stew v0.5.2). The real subject tree
## is a READ-ONLY clone outside this repo (Zero-Footprint); this fixture
## carries the same two bodies so the composite synthesis and its rendered
## Lean golden are locked without touching the subject clone.
type Base36Types* = object

func encodedLength*(btype: typedesc[Base36Types], length: int): int =
  return (length * 277) div 179 + 1

func decodedLength*(btype: typedesc[Base36Types], length: int): int =
  return (length * 179) div 277
