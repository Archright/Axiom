{.push raises: [].}
import std/options
import std/strutils

type
  QuarantineReason* {.pure.} = enum
    ExtractorLimitation = "extractor_limitation"
    VacuousPrimitive    = "vacuous_primitive"
    VacuousContradiction = "vacuous_contradiction"

func parseQuarantineReason*(s: string): Option[QuarantineReason] =
  let normalized = s.strip().toLowerAscii().replace("-", "_").replace(" ", "_")
  try:
    some(parseEnum[QuarantineReason](normalized))
  except ValueError:
    none(QuarantineReason)

func isForceHealReason*(reasons: openArray[string]): bool =
  for r in reasons:
    let parsed = parseQuarantineReason(r)
    if parsed.isSome and parsed.get() in {
      QuarantineReason.ExtractorLimitation,
      QuarantineReason.VacuousPrimitive,
      QuarantineReason.VacuousContradiction
    }:
      return true
  return false
