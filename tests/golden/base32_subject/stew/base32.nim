## base32 synthesis fixture — VERBATIM transcription of the decodedLength
## (stew/base32.nim:55-60, status-im/nim-stew v0.5.2). The real subject
## tree is a READ-ONLY clone outside this repo (Zero-Footprint); this
## fixture carries the same body so the rem lane's term-splice binding is
## locked without touching the subject clone.
type Base32Types* = object

func decodedLength*(btype: typedesc[Base32Types], length: int): int =
  let reminder = length mod 8
  return (length div 8) * 5 + ((reminder * 5) div 8)
