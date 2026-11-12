## src/core/debt/debt_registry_projection.nim — P1 Debt Registry Projection (contract implementation).
##
## `data/debt_registry.json` (SSOT) 을 두 P1 산출물로 접는다:
##   - docs/DEBT_REGISTRY.md              (markdown table)
##   - src/generated/debt_constants.nim   (compile-time const + static doAssert gate)
## 계약(contract): docs/spec/debt_projection_contract.md §1–§7.
##
## THE DECLARATION TABLE (단일 진원):
##   type FieldDecl*                       — (Markdown column ↔ registry key ↔ cell kind ↔ fidelity)
##   const DebtRowFields*                  — 위 표. `--codegen` 의 열 구성과 `--validate` 의 P3
##                                           기대값 파생이 모두 이 한 테이블에서 나온다 →
##                                           검증 없는 투영 열은 선언될 수 없다.
##   const DebtRegistryFieldsOutOfContract* — 명시적으로 투영하지 않기로 선언한 registry key.
##   func declaredCellValue*               — 계약 평가기. registry 를 직접 읽는다.
##   func cellFromEntry                    — 생성기 구현. 집계된 entry 에서 읽는다.
##                                           둘은 의도적으로 분리 — 검증자가 작성자와 함께
##                                           움직이면 생성기 결함이 증명되지 않는다.
##
## API:
##   func isDigitStr*, matchesDebtId*      — DEBT id 판별
##   func normalizeSeverity*, isOpen*      — registry 값 정규화/분류
##   func collectFiles*                    — `file`/`files` → 순서 있는 참조 목록
##   func aggregate*(registry)             — SeverityStats + seq[DebtEntry] (유일한 의미 입력 = registry)
##   func renderRow*                       — FieldDecl 순서대로 셀 조립 + escape
##   func genMarkdown*(entries)            — 헤더 수치는 전부 렌더된 행에서 파생
##   func genConstants*(stats, renderedRowCount)
##   func generateProjections*(registryJson)
##   func parseMarkdownRows*(md)           — genMarkdown 의 역함수 (read-back)
##   func orderedSeverities*(observed)     — 관측된 값만으로 만든 전순서
##
## 본 모듈은 순수 함수만 포함한다 — 파일 I/O, 시계, 프로세스 호출, 전역 가변 상태 금지.
## 동일한 registry JSON → byte-identical 두 산출물.
##
## `impact` 은 DEPRECATED 이며 계약 밖이다: 정본 severity 는 `severity` 이고, `impact` 은
## 215 엔트리 중 44 건에 없고 존재하는 171 건 중 DEBT#427 이 `severity` 와 정면으로
## 어긋난다. 계약에 편입하려면 그 불일치를 먼저 해소해야 하므로, 읽지 않고 보고만 한다.
## 근거 주석은 `DebtRowFields` 선언부 참조.

import core/trusted/layer_declaration
axiomLayer "domain"

import core/pure/json_parse
import std/[algorithm, json, strutils, tables]

# ═══════════════════════════════════════════════════════════════════════════════
# Contract constants
# ═══════════════════════════════════════════════════════════════════════════════

const
  CriticalThreshold*    = 30

  # v2: the Markdown row format changed — `title`/`declName` is replaced by
  # `description` as the Title source, and the single `File` cell becomes a
  # `Files` cell carrying every reference. See docs/spec/debt_projection_contract.md §7.
  DebtProjectionVersion* = "2"

# ═══════════════════════════════════════════════════════════════════════════════
# Registry value predicates
# ═══════════════════════════════════════════════════════════════════════════════

func isDigitStr*(s: string): bool {.raises: [].} =
  if s.len == 0: return false
  for ch in s:
    if ch < '0' or ch > '9': return false
  true

func matchesDebtId*(s: string): bool {.raises: [].} =
  if s.startsWith("DEBT#"): return isDigitStr(s[5..^1])
  if s.startsWith("DEBT-CI#"): return isDigitStr(s[8..^1])
  false

func normalizeSeverity*(s: string): string {.raises: [].} =
  let low = s.strip().toLowerAscii()
  case low
  of "critical", "high", "medium", "low": low
  of "n/a", "info", "": "low"
  else: low

func isOpen*(status: string): bool {.raises: [].} =
  let low = status.strip().toLowerAscii()
  if "closed" in low: return false
  if "exemption" in low: return false
  if status == "\u2014": return false
  true

func collectFiles*(entry: JsonNode): seq[string] {.raises: [].} =
  result = @[]
  if entry.isNil: return
  block:
    let f = entry{"file"}
    if f != nil and f.kind != JNull:
      if f.kind == JArray:
        for item in f: result.add(item.getStr())
      elif f.kind == JString:
        for part in f.getStr().split(','):
          let t = part.strip()
          if t.len > 0: result.add(t)
  block:
    let f2 = entry{"files"}
    if result.len == 0 and f2 != nil and f2.kind != JNull:
      if f2.kind == JArray:
        for item in f2: result.add(item.getStr())
      elif f2.kind == JString:
        for part in f2.getStr().split(','):
          let t = part.strip()
          if t.len > 0: result.add(t)

# ═══════════════════════════════════════════════════════════════════════════════
# Declaration table — types, constants, and the declared field pairs
# ═══════════════════════════════════════════════════════════════════════════════

type
  SeverityStats* = object
    total*: int
    openCount*: int
    entriesBySeverity*: CountTable[string]
    openBySeverity*: CountTable[string]

  DebtEntry* = object
    id*: string
    category*: string
    description*: string
    severity*: string
    status*: string
    source*: string
    files*: seq[string]

  ## How one projected cell is derived from the registry entry.
  CellSourceKind* = enum
    cskText          ## scalar registry field, verbatim
    cskSeverityLabel ## `severity` through the declared case display
    cskFileRefs      ## the ordered reference list, joined by FilesRefSeparator
    cskStatusLabel   ## `status` through the declared open/closed display

  ## One declared (Markdown column <-> registry key) contract pair.
  FieldDecl* = object
    column*: string       ## Markdown header cell
    registryKey*: string  ## registry entry key the cell must mirror
    kind*: CellSourceKind ## how the value becomes a cell
    fidelity*: bool       ## --validate re-derives this cell from the registry and compares

  ## One rendered Markdown row, kept with the cells it claims to satisfy.
  MdRow* = object
    line*: int
    cells*: seq[string]

const
  ## Join separator for the Files cell. References may legitimately contain
  ## commas (line annotations such as `src/core/audit/sad_gate.nim:59,147`), so a
  ## comma join cannot round-trip. `--validate` additionally fails closed when
  ## splitting a Files cell yields a different part count than the registry holds
  ## references, so a separator collision surfaces instead of silently merging two
  ## references into one.
  FilesRefSeparator* = "<br>"

  ## Rendered encoding of "this entry carries no file reference".
  EmptyFilesMarker* = "\u2014"

  ## Presentation preference for severity sections. This is NOT a vocabulary and
  ## NOT a filter: any severity value absent from the list still receives its own
  ## section and every entry renders. See `orderedSeverities`.
  SeveritySectionPreference = ["critical", "high", "medium", "low"]

  ## Header cells of the rendered Markdown table, in render order.
  RowColumns* = ["ID", "Severity", "Category", "Title", "Files", "Status"]

  RowSeparator = "|----|----------|----------|-------|------|--------|"

## THE PROJECTION DECLARATION TABLE.
##
## This table is the single source both writers and readers of the projection
## obey: `--codegen` lays its Markdown table out from `RowColumns`, and
## `--validate` derives its P3 field-fidelity expectations from `DebtRowFields`.
## Adding a column therefore obliges adding its validation in the same edit —
## a projected cell that nothing checks cannot be declared.
##
## `impact` is DEPRECATED and deliberately OUT of contract. Nothing reads it any
## more: the canonical severity is `severity` (the field `validateDebtRegistry`
## and `parseRegistry` have always read). The stale alias is inconsistent with
## the registry — it is absent on 44 of the 215 entries, and of the 171 that do
## carry it DEBT#427 disagrees with `severity` outright. Admitting it to the
## contract would require reconciling that first, so it is reported as deprecated
## and left unread instead of projected.

const
  DebtRowFields*: array[6, FieldDecl] = [
    FieldDecl(column: "ID",       registryKey: "id",          kind: cskText,          fidelity: true),
    FieldDecl(column: "Severity", registryKey: "severity",    kind: cskSeverityLabel, fidelity: true),
    FieldDecl(column: "Category", registryKey: "category",    kind: cskText,          fidelity: true),
    FieldDecl(column: "Title",    registryKey: "description", kind: cskText,          fidelity: true),
    FieldDecl(column: "Files",    registryKey: "files",       kind: cskFileRefs,      fidelity: true),
    FieldDecl(column: "Status",   registryKey: "status",      kind: cskStatusLabel,   fidelity: true)
  ]

  ## Registry entry keys that are deliberately NOT projected. `--validate` fails
  ## closed when a key appears in the registry that is in neither this list nor
  ## `DebtRowFields`, so a newly added field cannot silently escape the contract.
  DebtRegistryFieldsOutOfContract*: seq[string] = @[
    # deprecated severity alias — see the DEPRECATED note above
    "impact",
    # deprecated title alias, superseded by `description`
    "title",
    "declName",
    "resolution", "resolvedAt", "resolvedBy", "resolutionNote",
    "lastVerifiedAt", "symbol", "contentHash", "lineRange", "note",
    "kind", "historicalFiles", "source",
    # binding-type pair (docs/spec/debt_registry_schema.md §10): machine
    # medium for documented registry-side dispositions. Shape is enforced by
    # data/debt_schema.json + `debt_engine --validate`; this projection
    # deliberately neither reads nor renders them.
    "binding", "bindingRationale",
    # `file` is an accepted spelling of the `files` reference list
    "file"
  ].sorted

# ═══════════════════════════════════════════════════════════════════════════════
# Cell derivation — contract evaluator (oracle) and generator implementation
# ═══════════════════════════════════════════════════════════════════════════════

func severityLabel(sev: string): string {.raises: [].} =
  if sev.len == 0: return sev
  sev[0].toUpperAscii() & sev[1..^1]

func statusLabel(status: string): string {.raises: [].} =
  if isOpen(status): "**Open**" else: "Closed"

func escapeCell(s: string): string {.raises: [].} =
  ## A Markdown table cell is single-line and `|`-delimited; the registry is
  ## neither — DEBT#466 carries a literal newline in its `description`, which
  ## used to be hidden by the shorter `title`. Escaping makes the cell
  ## round-trippable instead of silently truncating the table.
  s.replace("\\", "\\\\").replace("\r", "\\r").replace("\n", "\\n").replace("|", "\\|")

func unescapeCell(s: string): string {.raises: [].} =
  ## Inverse of `escapeCell`, applied only once the cell delimiters are known.
  result = newStringOfCap(s.len)
  var i = 0
  while i < s.len:
    if s[i] == '\\' and i + 1 < s.len:
      case s[i + 1]
      of '\\': result.add('\\')
      of 'n': result.add('\n')
      of 'r': result.add('\r')
      of '|': result.add('|')
      else:
        result.add('\\')
        result.add(s[i + 1])
      i += 2
    else:
      result.add(s[i])
      inc i

func trimCellPad(s: string): string {.raises: [].} =
  ## Rows are written as `| cell | cell |`, so exactly one space delimits each
  ## cell. Removing exactly one keeps any space that belongs to the data.
  result = s
  if result.len > 0 and result[0] == ' ': result = result[1..^1]
  if result.len > 0 and result[^1] == ' ': result.setLen(result.len - 1)

## CONTRACT EVALUATOR — the cell value a declared field must have, read straight
## from the registry node. `--validate` compares the Markdown on disk against
## this; the generator's own extraction below is the implementation under test.
func declaredCellValue*(decl: FieldDecl; node: JsonNode): string {.raises: [].} =
  case decl.kind
  of cskText: node{decl.registryKey}.getStr()
  of cskSeverityLabel: severityLabel(normalizeSeverity(node{decl.registryKey}.getStr("medium")))
  of cskFileRefs:
    let refs = collectFiles(node)
    if refs.len == 0: EmptyFilesMarker else: refs.join(FilesRefSeparator)
  of cskStatusLabel: statusLabel(node{decl.registryKey}.getStr())

## GENERATOR IMPLEMENTATION — cell value for one declared field, from the
## aggregated entry. Kept separate from `declaredCellValue` on purpose: the
## validator must evaluate the contract independently of the writer, otherwise a
## generator defect moves both sides at once and proves nothing.
func cellFromEntry(decl: FieldDecl; e: DebtEntry): string {.raises: [].} =
  case decl.registryKey
  of "id": e.id
  of "severity": severityLabel(e.severity)
  of "category": e.category
  of "description": e.description
  of "files":
    if e.files.len == 0: EmptyFilesMarker else: e.files.join(FilesRefSeparator)
  of "status": statusLabel(e.status)
  else: ""

func renderRow*(e: DebtEntry): seq[string] =
  var row = newSeq[string](DebtRowFields.len)
  for i, decl in DebtRowFields:
    row[i] = escapeCell(cellFromEntry(decl, e))
  result = row

func aggregate*(registry: JsonNode): (SeverityStats, seq[DebtEntry]) {.raises: [CatchableError].} =
  ## The registry is the one semantic input. `data/architecture_debt.json` is a
  ## precondition of a well-formed checkout (checked by `--validate` Parts A/B),
  ## not an input here — reading it without ever using it hid the true input set.
  var stats: SeverityStats
  var entries: seq[DebtEntry]
  let regEntries = registry{"entries"}
  if regEntries.kind != JArray: return (stats, entries)
  for node in regEntries:
    let sev  = normalizeSeverity(node{"severity"}.getStr("medium"))
    let stat = node{"status"}.getStr()
    let open = isOpen(stat)
    stats.total += 1
    stats.entriesBySeverity.inc(sev)
    if open:
      stats.openCount += 1
      stats.openBySeverity.inc(sev)
    var de: DebtEntry
    de.id          = node{"id"}.getStr()
    de.category    = node{"category"}.getStr()
    de.description = node{"description"}.getStr()
    de.severity    = sev
    de.status      = stat
    de.source      = node{"source"}.getStr("manual")
    de.files       = collectFiles(node)
    entries.add(de)
  (stats, entries)

func genConstants*(stats: SeverityStats; renderedRowCount: int): string {.raises: [].} =
  let openCrit = stats.openBySeverity.getOrDefault("critical", 0)
  let openHigh = stats.openBySeverity.getOrDefault("high", 0)
  let openMed  = stats.openBySeverity.getOrDefault("medium", 0)
  let openLow  = stats.openBySeverity.getOrDefault("low", 0)
  result.add("# AUTO-GENERATED by tools/debt_engine.nim --codegen — DO NOT EDIT\n")
  result.add("# Source: data/debt_registry.json\n")
  result.add("# Projection contract: P1 v" & DebtProjectionVersion & "\n\n")
  result.add("const\n")
  result.add("  DebtEntryCount* {.intdefine.} = " & $stats.total & "\n")
  result.add("  DebtRowCount* {.intdefine.} = " & $renderedRowCount & "\n")
  result.add("  DebtOpenCount* {.intdefine.} = " & $stats.openCount & "\n")
  result.add("  DebtOpenCritical* {.intdefine.} = " & $openCrit & "\n")
  result.add("  DebtOpenHigh* {.intdefine.} = " & $openHigh & "\n")
  result.add("  DebtOpenMedium* {.intdefine.} = " & $openMed & "\n")
  result.add("  DebtOpenLow* {.intdefine.} = " & $openLow & "\n")
  result.add("  DebtCriticalThreshold* {.intdefine.} = " & $CriticalThreshold & "\n")
  result.add("  DebtProjectionVersion* = \"" & DebtProjectionVersion & "\"\n\n")
  result.add("static:\n")
  result.add("  doAssert DebtEntryCount == DebtRowCount,\n")
  result.add("    \"P1 projection lossless: \" & $DebtEntryCount & \" registry entries but \" & $DebtRowCount & \" rendered rows\"\n")
  result.add("  doAssert DebtOpenCritical <= DebtCriticalThreshold,\n")
  result.add("    \"DEBT#256 gate FAIL: open critical debt (\" & $DebtOpenCritical & \") exceeds threshold (\" & $DebtCriticalThreshold & \")\"")
func severityRank(s: string): int {.raises: [].} =
  for i, pref in SeveritySectionPreference:
    if s == pref: return i
  SeveritySectionPreference.len

func orderedSeverities*(observed: seq[string]): seq[string] {.raises: [].} =
  ## Total order over the severity values actually present. Declared levels come
  ## first in preference order; every other value follows in code-point order, so
  ## an out-of-vocabulary severity still gets a section instead of vanishing.
  for s in observed:
    if s notin result: result.add(s)
  result.sort(proc(a, b: string): int =
    let ra = severityRank(a)
    let rb = severityRank(b)
    if ra != rb: return ra - rb
    cmp(a, b))

func genMarkdown*(entries: seq[DebtEntry]): string {.raises: [].} =
  ## Every number in the header is derived from the rows this function actually
  ## rendered — never from the input count. A header that echoes the input count
  ## cannot detect rows the table dropped. `stats` is deliberately not a
  ## parameter: taking it would invite reading the input totals back in.
  var rows: seq[seq[string]]
  var rowSeverity: seq[string]
  for e in entries:
    rows.add(renderRow(e))
    rowSeverity.add(e.severity)
  let header = "| " & RowColumns.join(" | ") & " |"

  var severityCount: Table[string, int]
  var severityOpen: Table[string, int]
  var openRows = 0
  for i, cells in rows:
    let sev = rowSeverity[i]
    severityCount[sev] = severityCount.getOrDefault(sev, 0) + 1
    if cells[5] == "**Open**":
      inc openRows
      severityOpen[sev] = severityOpen.getOrDefault(sev, 0) + 1

  result.add("# Axiom Technical Debt Registry\n\n")
  result.add("> Auto-generated from `data/debt_registry.json`\n")
  result.add("> Projection: P1 v" & DebtProjectionVersion & "\n")
  result.add("> Total entries: " & $rows.len & "\n")
  result.add("> Open: " & $openRows & " | Closed: " & $(rows.len - openRows) & "\n")
  var severitySummary = ""
  for sep in orderedSeverities(rowSeverity):
    if severitySummary.len > 0: severitySummary.add(" | ")
    severitySummary.add(severityLabel(sep) & ": " & $severityCount.getOrDefault(sep, 0) &
                        " (open: " & $severityOpen.getOrDefault(sep, 0) & ")")
  result.add("> " & severitySummary & "\n\n")
  result.add("## Schema\n\n")
  result.add(header & "\n")
  result.add(RowSeparator & "\n\n")

  for sev in orderedSeverities(rowSeverity):
    var groupRows: seq[int]
    for i, rowSev in rowSeverity:
      if rowSev == sev: groupRows.add(i)
    if groupRows.len == 0: continue
    result.add("## " & severityLabel(sev) & " (" & $groupRows.len & ")\n\n")
    result.add(header & "\n")
    result.add(RowSeparator & "\n")
    for i in groupRows:
      result.add("| " & rows[i].join(" | ") & " |\n")
    result.add("\n")

# ═══════════════════════════════════════════════════════════════════════════════
# Markdown read-back — the inverse of `genMarkdown`, used by --validate
# ═══════════════════════════════════════════════════════════════════════════════

func splitMarkdownCells(line: string): seq[string] {.raises: [].} =
  ## Split a Markdown table row on unescaped `|`. A backslash escape is a
  ## two-character unit that can never be a delimiter, so a description
  ## carrying a raw pipe (7 registry entries do) cannot shift the cells that
  ## follow it.
  result = @[]
  var cur = newStringOfCap(line.len)
  var i = 0
  while i < line.len:
    let ch = line[i]
    if ch == '\\' and i + 1 < line.len:
      cur.add(ch)
      cur.add(line[i + 1])
      i += 2
    elif ch == '|':
      result.add(cur.strip())
      cur.setLen(0)
      inc i
    else:
      cur.add(ch)
      inc i
  result.add(cur.strip())

func parseMarkdownRows*(md: string): seq[MdRow] {.raises: [].} =
  ## Data rows only: a row is data when its first cell is a debt id, which
  ## excludes the `## Schema` header row, every per-section header row and the
  ## `|----|` delimiters without having to recognize their text. The leading and
  ## trailing `|` are row delimiters, not cells, so they are dropped first and
  ## the remaining cells line up 1:1 with `DebtRowFields`.
  let lines = md.splitLines()
  for idx in 0 ..< lines.len:
    let line = lines[idx].strip()
    if not line.startsWith("|"): continue
    var raw = splitMarkdownCells(line)
    if raw.len > 0 and raw[0].len == 0: raw.delete(0)
    if raw.len > 0 and raw[^1].len == 0: raw.setLen(raw.len - 1)
    if raw.len == 0: continue
    var cells: seq[string]
    for c in raw: cells.add(unescapeCell(trimCellPad(c)))
    if not matchesDebtId(cells[0]): continue
    result.add(MdRow(line: idx + 1, cells: cells))

# ═══════════════════════════════════════════════════════════════════════════════
# Pure projection core (no I/O, no timestamps)
# ═══════════════════════════════════════════════════════════════════════════════

func generateProjections*(registryJson: string): tuple[md, constants: string] {.raises: [CatchableError].} =
  ## PURE PROJECTION CORE — the whole semantic input is `registryJson`.
  ## Counted from the rendered Markdown, never from the input, so the two
  ## constants that must agree cannot agree by construction.
  ## std/json.parseJson carries a .sideEffect annotation (stdlib quirk), so
  ## parsing goes through core/pure/json_parse.pureParseJson and this core
  ## stays func. [SEE: nim_effect_system_quirks.md §9.1]
  let registry = pureParseJson(registryJson)
  let (stats, entries) = aggregate(registry)
  result.md = genMarkdown(entries)
  result.constants = genConstants(stats, parseMarkdownRows(result.md).len)
