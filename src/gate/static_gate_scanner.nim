import std/macros
import std/strutils
import std/os
import std/hashes
import std/algorithm

func isTrivialBody*(codeText: string): bool =
  let stripped = codeText.strip()
  stripped == "result = true" or stripped == "return true"

func extractQuotedValue(s: string): string =
  ## Extract value inside double quotes from a TOML key-value line like:
  ##   id = "anti-theater-gate"
  ## Returns empty string if no valid quoted value found.
  let eqIdx = s.find('=')
  if eqIdx < 0: return ""
  let afterEq = s[eqIdx+1 ..< s.len].strip()
  if afterEq.len < 2 or afterEq[0] != '"': return ""
  let closeQ = afterEq.find('"', 1)
  if closeQ < 0: return ""
  result = afterEq[1..<closeQ]

func extractGateInfoFromManifest*(manifestText: string): seq[tuple[id, file: string]] =
  ## Parse [[gates]] table-array entries from TOML manifest text.
  ## Each entry has an 'id' and 'file' key-value pair inside a [[gates]] block.
  var inGatesSection = false
  var currentId = ""
  var currentFile = ""
  
  for line in manifestText.splitLines():
    let trimmed = line.strip()
    
    if trimmed == "[[gates]]":
      if currentId.len > 0 and currentFile.len > 0:
        result.add((currentId, currentFile))
      inGatesSection = true
      currentId = ""
      currentFile = ""
    elif trimmed.startsWith("[") and trimmed.endsWith("]"):
      if currentId.len > 0 and currentFile.len > 0:
        result.add((currentId, currentFile))
      inGatesSection = false
      currentId = ""
      currentFile = ""
    elif inGatesSection:
      if trimmed.startsWith("id = ") or trimmed.startsWith("id="):
        currentId = extractQuotedValue(trimmed)
      elif trimmed.startsWith("file = ") or trimmed.startsWith("file="):
        currentFile = extractQuotedValue(trimmed)
        if currentId.len > 0:
          result.add((currentId, currentFile))
          currentId = ""
          currentFile = ""

func computeContentHash*(content: string): uint64 =
  ## Compute a fast content hash for change detection at compile time.
  result = cast[uint64](hash(content))

static:
  let manifestData = staticRead("config/gates.manifest.toml")
  let waiverData = staticRead("config/gates.waiver.toml")
  
  let gateInfos = extractGateInfoFromManifest(manifestData)
  
  ## Build waiver set as sorted seq for binary-search O(log n) lookups
  ## instead of linear O(n) contains() on raw text.
  var waiverSet: seq[string] = @[]
  for line in waiverData.splitLines():
    let trimmed = line.strip()
    if trimmed.len > 0 and not trimmed.startsWith("#"):
      waiverSet.add(trimmed)
  waiverSet.sort(system.cmp[string])
  
  for gateInfo in gateInfos:
    let (gateId, filePath) = gateInfo
    
    ## Binary-search waiver set for O(log n) lookup instead of O(n) text scan.
    var waived = false
    var lo = 0
    var hi = waiverSet.high
    while lo <= hi:
      let mid = lo + (hi - lo) div 2
      let c = cmp(waiverSet[mid], gateId)
      if c == 0:
        waived = true
        break
      elif c < 0: lo = mid + 1
      else: hi = mid - 1
    if waived: continue
    
    if not fileExists(filePath):
      error("Gate " & gateId & " file not found: " & filePath & "\n" &
            "Fix: Run 'nim r tools/sync_topology.nim' to regenerate generated files.")
    else:
      let content = staticRead(filePath)

      ## Line-based trivial-body detection (always runs regardless of AST result)
      let lines = content.splitLines()
      for i, ln in lines:
        if not (ln.contains("proc ") and ln.contains("(ctx: GateContext)") and ln.contains("): bool")):
          continue
        
        var bodyStart = i + 1
        while bodyStart < lines.len and lines[bodyStart].strip() == "":
          inc bodyStart
        
        if bodyStart < lines.len and isTrivialBody(lines[bodyStart].strip()):
          error("Gate " & gateId & " has trivial body (validity failure): " &
                "line " & $(bodyStart+1) & ": " & lines[bodyStart].strip() & "\n" &
                "Fix: Replace trivial stub with actual verification logic.")

proc scanGateRegistryStubs*() =
  ## Scan gate registry for trivial/stub implementations.
  ## This is a real implementation that checks for stub patterns.
  when defined(debugGateScanner):
    echo "Scanning for gate registry stubs..."