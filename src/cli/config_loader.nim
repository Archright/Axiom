## Minimal TOML config loader for axiom.toml.
## Handles: section headers, string/int/bool values, comments.
## Does NOT handle: nested tables, arrays, inline tables, multi-line strings.
## Sufficient for axiom.toml's flat structure.

import core/trusted/layer_declaration
axiomLayer "presentation"
import std/os
import std/strutils
import std/tables
import core/results
import core/parsers/safe_parsers
import core/axiom_pragmas

type
  TomlSection* = Table[string, string]
  TomlConfig* = Table[string, TomlSection]

func parseTomlValue(raw: string): string =
  ## Strip quotes from string values, return raw for int/bool.
  let v = raw.strip()
  if v.len >= 2 and v[0] == '"' and v[^1] == '"':
    return v[1 .. ^2]
  if v.len >= 2 and v[0] == '\'' and v[^1] == '\'':
    return v[1 .. ^2]
  v

func parseTomlConfig*(content: string): TomlConfig =
  ## Parse a TOML string into section → key → value. Pure function, no I/O.
  result = initTable[string, TomlSection]()
  var currentSection = ""

  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line[0] == '#':
      continue
    # Section header: [section.name]
    if line[0] == '[' and line[^1] == ']':
      currentSection = line[1 .. ^2]
      if currentSection notin result:
        result[currentSection] = initTable[string, string]()
      continue
    # Key = value (skip arrays and complex values)
    let eqIdx = line.find('=')
    if eqIdx < 0:
      continue
    let key = line[0 ..< eqIdx].strip()
    let valueRaw = line[eqIdx + 1 .. ^1].strip()
    # Skip arrays (contain [ and ])
    if valueRaw.len > 0 and valueRaw[0] == '[':
      continue
    if currentSection.len == 0:
      currentSection = "__root__"
    var section = result.mgetOrPut(currentSection, initTable[string, string]())
    section[key] = parseTomlValue(valueRaw)

proc loadTomlConfig*(path: string): TomlConfig {.raises: [IOError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read a TOML file and parse it into section → key → value.
  let content = readFile(path)
  result = parseTomlConfig(content)

proc loadTomlConfigIfPresent*(path: string): TomlConfig {.raises: [IOError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Optional-load variant for call-sites where the toml is a convenience
  ## overlay whose consumed fields all carry safe defaults (§1b:40 — the
  ## fail-closed catalog rule governs catalog reads, not the optional
  ## toml): an empty path or a non-existent file yields the default (empty)
  ## config. A path that EXISTS but fails to read still raises IOError —
  ## only the absence is tolerated, never a real I/O error (§0.9).
  if path.len == 0:
    return initTable[string, TomlSection]()
  var present = false
  try:
    present = fileExists(path)
  except OSError as e:
    raise newException(IOError, "config existence probe failed for \"" &
      path & "\": " & e.msg)
  if not present:
    return initTable[string, TomlSection]()
  result = loadTomlConfig(path)

func getSection*(config: TomlConfig; section: string): TomlSection =
  ## Get a section, returning empty table if not found.
  config.getOrDefault(section, initTable[string, string]())

func getString*(section: TomlSection; key: string; default: string = ""): string =
  section.getOrDefault(key, default)

func getInt*(section: TomlSection; key: string; default: int = 0): int =
  let v = section.getOrDefault(key, "")
  if v.len == 0: return default
  let r = safeParseInt(v)
  if r.isOk(): r.get() else: default

func getBool*(section: TomlSection; key: string; default: bool = false): bool =
  let v = section.getOrDefault(key, "").toLowerAscii()
  if v.len == 0: return default
  v == "true" or v == "yes" or v == "1"
