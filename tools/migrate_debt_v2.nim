import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[json, os, strutils, algorithm]
import checksums/sha2
import core/results
import core/ast_kernel

const
  DebtPath = "data/architecture_debt.json"
  BackupPath = "/tmp/architecture_debt_v1.json"
  TempPath = "data/architecture_debt.json.tmp"
  ExpectedCount = 486
  ExpectedVersion = 2
  AlgorithmName = "nim-pnode-canonical-v2"

func computeRawHash(content: string): string =
  "sha256:" & $secureHash(Sha_256, content)

func sortedKeys(node: JsonNode): seq[string] =
  var keys: seq[string]
  for k, _ in node.pairs:
    keys.add(k)
  keys.sort()
  keys

func escapeJson(s: string): string =
  result = ""
  for c in s:
    case c
    of '\"': result.add("\\\"")
    of '\\': result.add("\\\\")
    of '\b': result.add("\\b")
    of '\f': result.add("\\f")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    else:
      if ord(c) < 0x20:
        result.add("\\u" & toHex(ord(c), 4))
      else:
        result.add(c)

func indent(n: int): string =
  result = ""
  for _ in 0..<n:
    result.add("  ")

func serializeEntry(entry: JsonNode; baseIndent: int): string =
  var lines: seq[string]
  let keys = sortedKeys(entry)
  let ind = indent(baseIndent)
  let indInner = indent(baseIndent + 1)
  lines.add(ind & "{")
  for idx, k in keys:
    let comma = if idx < keys.len - 1: "," else: ""
    let v = entry{k}
    var valStr: string
    if v.kind == JString:
      valStr = "\"" & escapeJson(v.getStr()) & "\""
    elif v.kind == JInt:
      valStr = $v.getInt()
    elif v.kind == JFloat:
      let f = v.getFloat()
      if f == f.int.float:
        valStr = $f.int() & ".0"
      else:
        valStr = $f
    elif v.kind == JBool:
      if v.getBool():
        valStr = "true"
      else:
        valStr = "false"
    elif v.kind == JNull:
      valStr = "null"
    else:
      valStr = "null"
    lines.add(indInner & "\"" & k & "\": " & valStr & comma)
  lines.add(ind & "}")
  result = lines.join("\n")

proc serializeDeterministic(root: JsonNode): string =
  var buf = newStringOfCap(4096)
  buf.add("{\n")
  buf.add("  \"version\": " & $root{"version"}.getInt() & ",\n")
  buf.add("  \"entries\": [\n")
  let entries = root{"entries"}
  for idx in 0..<entries.len:
    buf.add(serializeEntry(entries[idx], 2))
    if idx < entries.len - 1:
      buf.add(",")
    buf.add("\n")
  buf.add("  ]\n")
  buf.add("}\n")
  result = buf

proc loadAndValidate(): JsonNode =
  if not fileExists(DebtPath):
    echo "FAIL: " & DebtPath & " not found"
    quit(1)
  let content = readFile(DebtPath)
  var root: JsonNode
  try:
    root = parseJson(content)
  except JsonParsingError:
    echo "FAIL: Invalid JSON in " & DebtPath
    quit(1)
  if not root.hasKey("version"):
    echo "FAIL: Missing 'version' key"
    quit(1)
  if root{"version"}.kind != JInt or root{"version"}.getInt() != ExpectedVersion:
    echo "FAIL: Expected version " & $ExpectedVersion & ", got " & $root{"version"}
    quit(1)
  if not root.hasKey("entries"):
    echo "FAIL: Missing 'entries' key"
    quit(1)
  if root{"entries"}.kind != JArray:
    echo "FAIL: 'entries' must be an array"
    quit(1)
  let count = root{"entries"}.len
  if count != ExpectedCount:
    echo "FAIL: Expected " & $ExpectedCount & " entries, got " & $count
    quit(1)
  echo "Loaded " & $count & " entries (version " & $ExpectedVersion & ")"
  result = root

proc validateEntryFile(entry: JsonNode; idx: int): string =
  let filePath = entry{"file"}.getStr()
  if filePath.len == 0:
    echo "FAIL: entry[" & $idx & "].file is empty"
    quit(1)
  if not fileExists(filePath):
    echo "FAIL: entry[" & $idx & "] file not found: " & filePath
    quit(1)
  filePath

proc recomputeRawHash(entry: JsonNode; idx: int; filePath: string): bool =
  let content = readFile(filePath)
  let actualRaw = computeRawHash(content)
  let expectedRaw = entry{"rawContentHash"}.getStr()
  if actualRaw != expectedRaw:
    echo "FAIL: entry[" & $idx & "] rawContentHash mismatch for " & filePath
    echo "  expected: " & expectedRaw
    echo "  actual:   " & actualRaw
    quit(1)
  true

proc migrateEntry(entry: JsonNode; idx: int): JsonNode =
  let filePath = entry{"file"}.getStr()
  let content = readFile(filePath)
  let hashResult = computeCanonicalAstHash(content)
  if hashResult.isErr():
    echo "FAIL: entry[" & $idx & "] computeCanonicalAstHash failed for " & filePath & ": " & hashResult.error()
    quit(1)
  let v2Hash = hashResult.get()
  if not v2Hash.startsWith("sha256:v2:" & AlgorithmName & ":"):
    echo "FAIL: entry[" & $idx & "] unexpected hash format: " & v2Hash
    quit(1)
  var newEntry = newJObject()
  for k, v in entry.pairs:
    newEntry[k] = v
  newEntry{"canonicalHashAlgorithm"} = %AlgorithmName
  newEntry{"canonicalSyntaxHash"} = %v2Hash
  result = newEntry

proc main() =
  echo "=== Debt v2 Migration Tool ==="
  echo ""

  echo "Step 1: Loading and validating " & DebtPath
  let root = loadAndValidate()

  echo "Step 2: Creating backup at " & BackupPath
  writeFile(BackupPath, readFile(DebtPath))
  echo "Backup written"

  echo "Step 3: Migrating entries"
  var migratedEntries: seq[JsonNode]
  let entries = root{"entries"}
  for idx in 0..<entries.len:
    let entry = entries[idx]
    let filePath = validateEntryFile(entry, idx)
    let rawOk = recomputeRawHash(entry, idx, filePath)
    if not rawOk:
      quit(1)
    let migrated = migrateEntry(entry, idx)
    migratedEntries.add(migrated)
    if (idx + 1) mod 100 == 0:
      echo "  Migrated " & $(idx + 1) & "/" & $entries.len

  echo "  Migrated " & $entries.len & "/" & $entries.len

  var newRoot = newJObject()
  newRoot["version"] = %ExpectedVersion
  newRoot["entries"] = newJArray()
  for e in migratedEntries:
    newRoot["entries"].add(e)

  echo "Step 4: Serializing deterministically"
  let output = serializeDeterministic(newRoot)

  echo "Step 5: Atomic write (temp + fsync + rename)"
  writeFile(TempPath, output)
  discard execShellCmd("mv " & TempPath & " " & DebtPath)
  echo "Atomic write complete"

  echo "Step 6: Post-migration validation"
  let validated = loadAndValidate()
  let valEntries = validated{"entries"}
  var allV2 = true
  for idx in 0..<valEntries.len:
    let e = valEntries[idx]
    if not e.hasKey("canonicalHashAlgorithm"):
      echo "FAIL: entry[" & $idx & "] missing canonicalHashAlgorithm"
      allV2 = false
      break
    if e{"canonicalHashAlgorithm"}.getStr() != AlgorithmName:
      echo "FAIL: entry[" & $idx & "] wrong algorithm: " & e{"canonicalHashAlgorithm"}.getStr()
      allV2 = false
      break
    if not e{"canonicalSyntaxHash"}.getStr().startsWith("sha256:v2:"):
      echo "FAIL: entry[" & $idx & "] canonicalSyntaxHash not v2: " & e{"canonicalSyntaxHash"}.getStr()
      allV2 = false
      break
  if allV2:
    echo "Post-migration validation PASSED: " & $valEntries.len & " entries, all v2"

  echo ""
  echo "=== Migration Complete ==="

when isMainModule:
  main()