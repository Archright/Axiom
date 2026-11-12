{.push raises: [].}
import std/[json, sets]
import checksums/sha1

const SpecRegistryRaw = staticRead("../../../docs/spec/spec_registry.json")

const SpecIds = block:
  let jObj = parseJson(SpecRegistryRaw)
  var ids: seq[string]
  for key in jObj.keys:
    ids.add(key)
  ids

let CompiledSpecHash* = $secureHash(SpecRegistryRaw)

var runtimeSpecSet {.threadvar.}: HashSet[string]

proc initSpecRuntime*() =
  for key in SpecIds:
    runtimeSpecSet.incl(key)

proc validateSpecId*(specId: string): bool =
  if runtimeSpecSet.len == 0:
    initSpecRuntime()
  result = specId in runtimeSpecSet

template requireSpec*(specId: static[string]) =
  static:
    var found = false
    for id in SpecIds:
      if id == specId:
        found = true
        break
    assert found, "Invalid Spec ID at compile-time: " & specId
