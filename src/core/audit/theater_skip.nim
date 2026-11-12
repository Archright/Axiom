{.push raises: [].}
import core/trusted/layer_declaration
axiomLayer "domain"

import std/os
import std/strutils
import std/json except parseJson
import core/axiom_pragmas

func normalizePathSeparators*(path: string): string {.raises: [].} =
  path.replace('\\', '/')

func defaultRegistryPath*(): string {.raises: [].} =
  parentDir(currentSourcePath()) / "data" / "debt_registry.json"

func jString(entry: JsonNode; key: string): string {.raises: [KeyError].} =
  if entry.kind == JObject and entry.hasKey(key):
    result = entry[key].getStr()

func jStringArray(entry: JsonNode; key: string): seq[string] {.raises: [KeyError].} =
  if entry.kind == JObject and entry.hasKey(key):
    let node = entry[key]
    if node.kind == JArray:
      for item in node:
        if item.kind == JString:
          result.add(item.getStr())

func normalizeEntryPath(path: string): string {.raises: [].} =
  normalizePathSeparators(path.strip())

func entryMatchesFile(entry: JsonNode; file: string): bool {.raises: [KeyError].} =
  let normalized = normalizeEntryPath(file)
  if entry.kind != JObject:
    return false
  if entry.hasKey("file"):
    return normalizeEntryPath(entry["file"].getStr()) == normalized
  if entry.hasKey("files"):
    for candidate in jStringArray(entry, "files"):
      if normalizeEntryPath(candidate) == normalized:
        return true
  false

func entryHasSymbol(entry: JsonNode; symbol: string): bool {.raises: [KeyError].} =
  let normalized = symbol.strip()
  if normalized.len == 0:
    return false
  if entry.kind != JObject:
    return false
  if entry.hasKey("symbol"):
    return entry["symbol"].getStr().strip() == normalized
  if entry.hasKey("symbols"):
    for candidate in jStringArray(entry, "symbols"):
      if candidate.strip() == normalized:
        return true
  if entry.hasKey("sig"):
    return entry["sig"].getStr().strip() == normalized
  if entry.hasKey("signature"):
    return entry["signature"].getStr().strip() == normalized
  false

func entryResolution(entry: JsonNode): string {.raises: [KeyError].} =
  jString(entry, "resolution")

func entryContentHash(entry: JsonNode): string {.raises: [KeyError].} =
  if entry.kind == JObject:
    if entry.hasKey("contentHash"):
      return entry["contentHash"].getStr()
    if entry.hasKey("content_hash"):
      return entry["content_hash"].getStr()
  ""

proc loadDebtRegistry*(registryPath: string = defaultRegistryPath()): JsonNode {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [CatchableError].} =
  parseFile(registryPath)

proc shouldSkipTheaterAudit*(file: string; symbol: string; contentHash: string; registryPath: string = defaultRegistryPath()): bool {.raises: [CatchableError].} =
  try:
    let registry = loadDebtRegistry(registryPath)
    if registry.kind != JObject or not registry.hasKey("entries") or registry["entries"].kind != JArray:
      return false
    for entry in registry["entries"]:
      if entry.kind != JObject:
        continue
      if entryMatchesFile(entry, file) and
         entryHasSymbol(entry, symbol) and
         entryResolution(entry).toUpperAscii() == "FALSE_POSITIVE" and
         entryContentHash(entry) == contentHash:
        return true
    false
  except CatchableError:
    false
