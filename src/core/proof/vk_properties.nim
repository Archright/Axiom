import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/[strutils]

func vkPropertySmt*(vulnerabilityKind: string, varMap: openArray[tuple[key, val: string]] = []): string {.raises: [].} =
  let templ = case vulnerabilityKind
    of "vkBufferOverflow": "(and (>= $idx 0) (< $idx $length))"
    of "vkNullPointerDereference": "(not (= $ptr nil))"
    of "vkIntegerOverflowUnderflow": "(and (>= $amount 0) (<= $amount $balance))"
    of "vkGhostUpdate": "(>= $version_next $version)"
    of "vkDeadlockRaceCondition": "$lockHeld"
    else: "true"
  result = templ
  # Prioritized: longer placeholders first to prevent $version corrupting $version_next
  const prioritizedPlaceholders = [
    "version_next", "version", "length", "balance", "amount", "lockHeld", "idx", "ptr"
  ]
  if varMap.len == 0:
    for ph in prioritizedPlaceholders:
      result = result.replace("$" & ph, ph)
  else:
    for ph in prioritizedPlaceholders:
      for (k, v) in varMap:
        if k == ph:
          result = result.replace("$" & ph, v)
          break

static:
  assert vkPropertySmt("vkBufferOverflow").len > 0
  assert vkPropertySmt("vkNullPointerDereference").len > 0
  assert vkPropertySmt("vkIntegerOverflowUnderflow").len > 0
  assert vkPropertySmt("vkGhostUpdate").len > 0
  assert vkPropertySmt("vkDeadlockRaceCondition").len > 0
  assert vkPropertySmt("unknown") == "true"
  assert "$" notin vkPropertySmt("vkBufferOverflow")
  assert "$" notin vkPropertySmt("vkGhostUpdate")
  assert "$" notin vkPropertySmt("vkNullPointerDereference")
  assert "$" notin vkPropertySmt("vkIntegerOverflowUnderflow")
  assert "$" notin vkPropertySmt("vkDeadlockRaceCondition")
  # SSA mapping: $version must not corrupt $version_next
  let ghostMapped = vkPropertySmt("vkGhostUpdate", [("version", "version_0"), ("version_next", "version_1")])
  assert "version_0_next" notin ghostMapped
  assert ghostMapped == "(>= version_1 version_0)"

{.pop.}
