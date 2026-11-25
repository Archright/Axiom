## tools/ci/rule_suite_bypass_ledger.nim — deterministic ruleset bypass ledger
## (collect → merge → assert).
##
## WHY A LEDGER EXISTS AT ALL: the GitHub rulesets bypass surface is only
## observable through a ROLLING WINDOW.
##   GET /repos/{owner}/{repo}/rulesets/rule-suites
##       ?ref=refs/heads/main&per_page=100&time_period=month
##       &rule_suite_result=bypass
## accepts `time_period` up to `month` (measured 2026-11-25: 26 bypass
## landings inside the window, oldest 2026-11-17T01:50:38+09:00). Every day
## the window slides forward, so a landing that is not copied into the repo
## during its 30-day residency is destroyed by the platform — the evidence
## does not exist anywhere else. This file is the copy machine plus the
## reader: the ledger is the permanent per-landing record, the API is only a
## rolling feed into it.
##
## FOUR JUDGMENTS, ONE AUTHORITY MODEL:
##   1. append + dedupe by `id`  — the API page contents are not stable
##      across runs (entries enter and leave the window), so merging is
##      set-union keyed on the immutable `id` and re-sorting on
##      (pushed_at, id). A re-run of the collector therefore cannot
##      duplicate a line: it re-derives the same file.
##   2. direct-push detection — a landing whose `after_sha` is not a
##      first-parent commit of main did not arrive through a merge commit.
##      The first-parent SET IS AN INPUT, never fetched here: the repo's
##      depth-1 CI path forbids unbounded history walks
##      (tools/ci/git_access_scan.sh clause 1), so this tool takes the set
##      from the caller and reports UNKNOWN when it is absent rather than
##      silently reporting zero findings.
##   3. elevation-window overlap — a landing that is *expected* to bypass is
##      not evidence of a defect. The windows are an INPUT (a JSON document
##      of [start, end] intervals); with no windows document every landing is
##      UNKNOWN, never "unexplained".
##   4. freshness — the ledger is only evidence about the window it covers.
##      A ledger whose newest row is months old says nothing about the
##      bypasses of the last month, so "0 findings" over stale contents is
##      the same statement as "no bypasses", which is exactly the collapse
##      AGENTS.md §0.9 forbids. The age limit and the clock are both INPUTS
##      (`--max-age-days`, `--now`): without the limit the verdict is
##      UNKNOWN, never FRESH. A ledger whose newest row is in the FUTURE is
##      its own verdict, not a negative age that quietly satisfies the
##      limit — a future row means the clock or the record is wrong, and
##      neither can be attested as fresh.
##
## EVIDENCE FIDELITY: an entry is canonicalised to a FIXED field order and a
## FIXED field set (the ten fields below). Extra API fields — notably
## `evaluation_result` — are dropped rather than guessed at, so the ledger
## bytes depend only on the ten declared fields and a re-fetch is a no-op.
## Two sources disagreeing about the SAME id is a fail-closed conflict, not a
## last-writer-wins update: a bypass record is immutable once created, so a
## differing value for one id means the input is corrupt or forged.
##
## USAGE (read from repo root):
##   rule_suite_bypass_ledger merge --raw <api.json> --ledger <ledger.jsonl>
##                                  [--out <path>]
##       Set-union `raw` into `ledger`; refuse to write an empty ledger or a
##       conflicting id. Prints the count before/after. `--out` writes
##       elsewhere (used by the CI collector, which must not mutate the
##       tracked file).
##   rule_suite_bypass_ledger assert --ledger <ledger.jsonl>
##                                   [--first-parent <shas.txt>]
##                                   [--windows <windows.json>]
##                                   [--max-age-days <N>] [--now <iso8601>]
##                                   [--json]
##       Read-only report: total landings + date range, freshness,
##       direct pushes, elevation-window matches.
##
##       EXIT CONTRACT (three codes, and a finding is a finding — freshness
##       does not get its own code, because a caller that had to distinguish
##       "stale" from "direct push" would need to parse the text, and a
##       caller that only looks at zero/non-zero must see both):
##         0 = no finding (every PERFORMED check clean)
##         1 = FINDING — a direct push, an elevation-window match, or
##             freshness STALE. Any one of them makes the exit non-zero.
##         2 = usage/config/parse error, or a judgment that could not be
##             performed (unparsable ledger, empty first-parent set,
##             malformed windows document, non-positive --max-age-days).
##       A check that was not supplied is reported UNKNOWN in the text AND
##       in the JSON; UNKNOWN never exits 1, because "not asked" is not
##       "found", and never exits 0 as a clean result either — the UNKNOWN
##       line is the finding-shaped notice, printed unconditionally.
##
##       `--now` exists so the freshness judgment is reproducible: the
##       wall clock is read exactly once, in `runAssert`, and passed in as a
##       value. Every judgment below it stays `func` + {.raises: [].}.

## Effect boundary: every judgment above is `func` + {.raises: [].}; only
## file reads/writes and process exit carry {.axiomEffect: IoEffect.}.

import std/[algorithm, json, options, os, sets, strutils, tables, times]
import api/tools_facade

const
  LedgerSchema* = "axiom.rule-suite-bypass-ledger.v1"

  ## Canonical field order of one ledger line. This list is the byte identity
  ## of the ledger: `renderJsonl` emits exactly these keys in this order.
  LedgerFieldOrder* = ["id", "actor_id", "actor_name", "before_sha",
                       "after_sha", "ref", "repository_id", "repository_name",
                       "pushed_at", "result"]

  IntFields* = ["id", "actor_id", "repository_id"]

type
  LedgerEntry* = object
    ## One sorted ledger row: the canonical node plus its sort key.
    id*: int64
    epoch*: int64
    pushedAt*: string
    node*: JsonNode

  Window* = object
    ## A declared ruleset-elevation interval (inclusive on both ends).
    label*: string
    startEpoch*: int64
    endEpoch*: int64

  Freshness* = enum
    ## The third verdict dimension. `UNKNOWN` is the default and the only
    ## state reachable without an explicit age limit — a ledger that is
    ## never asked to be fresh can never be reported FRESH.
    freshUnknown = "UNKNOWN"
    freshFresh = "FRESH"
    freshStale = "STALE"
    freshFuture = "FUTURE"

  LedgerReport* = object
    ## The read-only judgment. `checkable` distinguishes "no findings" from
    ## "not asked" — the difference between a clean audit and a silent pass.
    total*: int
    oldestPushedAt*: string
    newestPushedAt*: string
    directPushCheckable*: bool
    directPushes*: seq[JsonNode]
    windowCheckable*: bool
    windowMatches*: seq[JsonNode]
    freshness*: Freshness
    ## Age of the newest row in whole days, and the limit it was measured
    ## against. Both are only meaningful when `freshness != freshUnknown`
    ## (limit) or when a newest row exists (age).
    newestAgeDays*: int64
    maxAgeDays*: int64
    ## The clock the judgment used, so a STALE verdict is re-checkable
    ## rather than a claim about an unstated "now".
    judgedAtEpoch*: int64

func field(node: JsonNode; key: string): JsonNode {.raises: [].} =
  ## Pure: `node[key]` as a value (nil when absent) — never raises on a
  ## non-object input, which is what makes the parsers below fail closed.
  if node.isNil or node.kind != JObject:
    return nil
  let v = node.getOrDefault(key)
  if v.isNil:
    return nil
  v

func scalar(node: JsonNode; key: string): string {.raises: [].} =
  ## Pure: a field rendered for the human report. `$JsonNode` on a string
  ## node emits JSON (`"x"`, quotes included), which would read as part of
  ## the value in a rendezvous/diff context; the report wants the payload.
  let v = field(node, key)
  if v.isNil:
    return "<absent>"
  if v.kind == JString:
    return v.getStr()
  $v

func twoDigits(s: string; pos: int): Option[int] {.raises: [].} =
  ## Pure: exactly two ASCII digits at `pos`.
  if pos + 2 > s.len:
    return none(int)
  var v = 0
  for i in pos ..< pos + 2:
    if s[i] notin {'0'..'9'}:
      return none(int)
    v = v * 10 + (ord(s[i]) - ord('0'))
  some(v)

func daysFromCivil(year, month, day: int): int64 {.raises: [].} =
  ## Pure: civil date → days since 1970-01-01 (proleptic Gregorian, so the
  ## leap rule is the language's, not a timezone database's).
  let y = (if month <= 2: year - 1 else: year)
  let era = (if y >= 0: y else: y - 399) div 400
  let yoe = int64(y - era * 400)
  let mp = int64((month + 9) mod 12)
  let doy = (153 * mp + 2) div 5 + int64(day - 1)
  let doe = yoe * 365 + yoe div 4 - yoe div 100 + doy
  int64(era) * 146097 + doe - 719468

func pushedEpoch*(pushedAt: string): Option[int64] {.raises: [].} =
  ## Pure: ISO-8601 `pushed_at` → unix epoch, parsed HERE rather than by
  ## `times.parse` (which is a `.sideEffect` and would put the timezone
  ## database on the determinism path). Requires the exact
  ## `YYYY-MM-DDTHH:MM:SS±HH:MM` shape the rulesets API emits; `none` on any
  ## other shape — the caller decides whether that is UNKNOWN or fatal.
  ##
  ## The offset is applied as a fixed sign*minutes arithmetic, so two
  ## landings recorded in different offsets still sort on one absolute time.
  if pushedAt.len != 25:
    return none(int64)
  if pushedAt[4] != '-' or pushedAt[7] != '-' or pushedAt[10] != 'T' or
      pushedAt[13] != ':' or pushedAt[16] != ':' or
      pushedAt[19] notin {'+', '-'} or pushedAt[22] != ':':
    return none(int64)
  let year = (block:
    if pushedAt[0] notin {'0'..'9'} or pushedAt[1] notin {'0'..'9'} or
        pushedAt[2] notin {'0'..'9'} or pushedAt[3] notin {'0'..'9'}:
      return none(int64)
    (ord(pushedAt[0]) - ord('0')) * 1000 + (ord(pushedAt[1]) - ord('0')) * 100 +
      (ord(pushedAt[2]) - ord('0')) * 10 + (ord(pushedAt[3]) - ord('0')))
  let month = twoDigits(pushedAt, 5).get(-1)
  let day = twoDigits(pushedAt, 8).get(-1)
  let hour = twoDigits(pushedAt, 11).get(-1)
  let minute = twoDigits(pushedAt, 14).get(-1)
  let second = twoDigits(pushedAt, 17).get(-1)
  let offHour = twoDigits(pushedAt, 20).get(-1)
  let offMin = twoDigits(pushedAt, 23).get(-1)
  if month < 1 or month > 12 or day < 1 or day > 31 or
      hour > 23 or minute > 59 or second > 60 or
      offHour > 23 or offMin > 59:
    return none(int64)
  let sign = (if pushedAt[19] == '+': -1'i64 else: 1'i64)
  let offset = sign * (int64(offHour) * 3600 + int64(offMin) * 60)
  some(daysFromCivil(year, month, day) * 86400 +
       int64(hour) * 3600 + int64(minute) * 60 + int64(second) + offset)

func canonicalEntry*(raw: JsonNode): JsonNode {.raises: [].} =
  ## Pure: project an API entry onto the fixed field order and field set.
  ## nil when a declared field is missing or of the wrong JSON type — a
  ## partially populated ledger line is never emitted.
  if raw.isNil or raw.kind != JObject:
    return nil
  result = newJObject()
  for key in LedgerFieldOrder:
    let v = field(raw, key)
    if v.isNil:
      return nil
    if key in IntFields:
      if v.kind != JInt:
        return nil
    elif v.kind != JString:
      return nil
    result[key] = v

func toEntry*(node: JsonNode): Option[LedgerEntry] {.raises: [].} =
  ## Pure: canonical node → sortable row. `none` on a malformed row (missing
  ## id, non-integer id, unparsable pushed_at).
  let idNode = field(node, "id")
  let pushed = field(node, "pushed_at")
  if idNode.isNil or idNode.kind != JInt or pushed.isNil or pushed.kind != JString:
    return none(LedgerEntry)
  let ep = pushedEpoch(pushed.getStr())
  if ep.isNone:
    return none(LedgerEntry)
  some(LedgerEntry(id: idNode.getBiggestInt, epoch: ep.get,
                   pushedAt: pushed.getStr(), node: node))

func cmpEntry(a, b: LedgerEntry): int {.raises: [].} =
  ## Pure: ledger order — (pushed_at, id). Epoch rather than the raw string
  ## because the API offsets are not guaranteed constant across entries;
  ## `id` breaks ties so the order is total and re-derivation is stable.
  if a.epoch != b.epoch:
    return cmp(a.epoch, b.epoch)
  cmp(a.id, b.id)

func sortEntries(rows: seq[LedgerEntry]): seq[LedgerEntry] {.raises: [].} =
  result = rows
  result.sort(cmpEntry)

func mergeNodes*(left, right: seq[JsonNode]):
    tuple[ok: bool; rows: seq[JsonNode]; conflictId: int64] {.raises: [].} =
  ## Pure: set-union of two entry lists, keyed on the immutable `id`.
  ##
  ## A repeated id with IDENTICAL bytes is the ordinary re-run case (the
  ## merge is idempotent). A repeated id with DIFFERENT bytes is
  ## `ok: false` — a bypass record cannot change after creation, so the
  ## inputs contradict each other and the caller must fail closed rather
  ## than pick a winner.
  var byId = initTable[int64, LedgerEntry]()
  var rows: seq[LedgerEntry] = @[]
  for source in [left, right]:
    for n in source:
      let canon = canonicalEntry(n)
      if canon.isNil:
        return (false, @[], -1'i64)
      let entry = toEntry(canon)
      if entry.isNone:
        return (false, @[], -1'i64)
      let e = entry.get()
      if byId.hasKey(e.id):
        if $byId.getOrDefault(e.id).node != $e.node:
          return (false, @[], e.id)
        continue
      byId[e.id] = e
      rows.add(e)
  let order = sortEntries(rows)
  var merged: seq[JsonNode] = newSeq[JsonNode](order.len)
  for i in 0 ..< order.len:
    merged[i] = order[i].node
  result = (true, merged, 0'i64)

proc parseJsonl*(text: string): tuple[ok: bool; rows: seq[JsonNode]] {.raises: [].} =
  ## Decoder for the ledger's own bytes — deliberately a `proc`, not a `func`.
  ##
  ## [SEE: nim_effect_system_quirks.md §1.1] `std/json.parseJson` is not
  ## declared `{.noSideEffect.}`, so ANY function calling it is judged
  ## side-effecting; the spec's rule is that such callers stay `proc`. The
  ## sanctioned `pureParseJson` wrapper is `src/core`-only by its own header,
  ## so it is not available here. Casting the effect away instead would hide
  ## a real allocation rather than isolate it (§0.9 theater), so this decode
  ## step sits with the other input boundaries and every judgment below
  ## receives already-parsed nodes.
  ##
  ## Semantics: one JSON object per LF-terminated line. Blank lines are
  ## tolerated (a trailing newline is not a record); any unparsable line
  ## fails the whole file — a ledger with one bad line is not "mostly right".
  var rows: seq[JsonNode] = @[]
  for line in text.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0:
      continue
    var node: JsonNode
    try:
      node = parseJson(trimmed)
    except CatchableError:
      return (false, @[])
    if node.isNil or node.kind != JObject:
      return (false, @[])
    rows.add(node)
  (true, rows)

func renderJsonl*(rows: seq[JsonNode]): string {.raises: [].} =
  ## Pure: canonical ledger bytes — one compact object per line, fixed key
  ## order, LF, trailing newline. Same rows → same bytes → same git diff.
  for n in rows:
    let canon = canonicalEntry(n)
    if canon.isNil:
      continue
    result.add($canon)
    result.add('\n')

func dateRange*(rows: seq[JsonNode]):
    tuple[oldest: string; newest: string] {.raises: [].} =
  ## Pure: the (pushed_at, id) first and last rows, as recorded.
  var entries: seq[LedgerEntry] = @[]
  for n in rows:
    let e = toEntry(n)
    if e.isSome:
      entries.add(e.get())
  if entries.len == 0:
    return ("", "")
  let sorted = sortEntries(entries)
  (sorted[0].pushedAt, sorted[^1].pushedAt)

func landingOf*(node: JsonNode): JsonNode {.raises: [].} =
  ## Pure: the report projection of one landing — the audit trail keeps the
  ## SHA pair and the actor, which is what a reader needs to re-verify.
  %*{
    "id": field(node, "id"),
    "pushed_at": field(node, "pushed_at"),
    "before_sha": field(node, "before_sha"),
    "after_sha": field(node, "after_sha"),
    "actor_name": field(node, "actor_name"),
    "result": field(node, "result")
  }

func findDirectPushes*(rows: seq[JsonNode];
                       firstParent: HashSet[string]): seq[JsonNode] {.raises: [].} =
  ## Pure: landings whose `after_sha` is not in the caller-supplied
  ## first-parent set of main. A merge-queue landing always writes a merge
  ## commit at the tip, so a tip that is absent from the first-parent chain
  ## arrived by some other route (a direct ref update is the canonical one).
  ##
  ## HONEST LIMIT: this is a proxy, not proof. It cannot distinguish a
  ## direct push from a landing that was later rewritten out of the chain,
  ## and it needs the chain as input — hence UNKNOWN, never zero, when the
  ## caller supplies nothing.
  for n in rows:
    let after = field(n, "after_sha")
    if after.isNil or after.kind != JString:
      continue
    if not firstParent.contains(after.getStr()):
      result.add(landingOf(n))

func parseWindows*(doc: JsonNode):
    tuple[ok: bool; windows: seq[Window]] {.raises: [].} =
  ## Pure: `{"windows": [{"label", "start", "end"}]}`. Every window must
  ## parse; a malformed elevation document is a configuration error, not
  ## "no windows" — the two would produce opposite audit conclusions.
  if doc.isNil or doc.kind != JObject:
    return (false, @[])
  let arr = field(doc, "windows")
  if arr.isNil or arr.kind != JArray:
    return (false, @[])
  var windows: seq[Window] = @[]
  for w in arr.items:
    if w.kind != JObject:
      return (false, @[])
    let start = field(w, "start")
    let finish = field(w, "end")
    if start.isNil or start.kind != JString or
        finish.isNil or finish.kind != JString:
      return (false, @[])
    let s = pushedEpoch(start.getStr())
    let e = pushedEpoch(finish.getStr())
    if s.isNone or e.isNone:
      return (false, @[])
    let label = field(w, "label")
    windows.add(Window(label: (if label.isNil: "" else: label.getStr()),
                       startEpoch: s.get, endEpoch: e.get))
  (true, windows)

func findWindowMatches*(rows: seq[JsonNode];
                        windows: seq[Window]): seq[JsonNode] {.raises: [].} =
  ## Pure: landings whose timestamp falls inside ANY declared elevation
  ## window (inclusive). `window` on each finding names the interval so the
  ## reader can check the claim instead of trusting the verdict.
  for n in rows:
    let e = toEntry(n)
    if e.isNone:
      continue
    for w in windows:
      if e.get().epoch >= w.startEpoch and e.get().epoch <= w.endEpoch:
        var outNode = landingOf(n)
        outNode["window"] = %w.label
        result.add(outNode)

func judgeFreshness*(newestEpoch: int64; hasNewest: bool; nowEpoch: int64;
                     maxAgeDays: int64; maxAgeSupplied: bool):
    tuple[verdict: Freshness; ageDays: int64] {.raises: [].} =
  ## Pure: is the ledger new enough to be evidence about the current window?
  ##
  ## Whole days are counted by integer division of the epoch delta, so the
  ## boundary is exact for the only shape a caller can express: a row exactly
  ## N days old yields ageDays == N and is FRESH under a limit of N. The
  ## comparison is `<=`, i.e. the limit is inclusive — an off-by-one that
  ## made N days STALE would force every operator to pad the limit
  ## downward, and padding is how a real limit stops meaning anything.
  ##
  ## `hasNewest` false means the ledger has no parsable rows at all. That is
  ## UNKNOWN rather than STALE: there is no age to measure, and reporting
  ## STALE would invent a measurement. (An empty ledger is already refused
  ## by `merge`; this is the read side declining to guess.)
  ##
  ## A NEGATIVE age (newest row in the future) is FUTURE, not a very fresh
  ## ledger. Clock skew and a hand-edited record are both real, both mean the
  ## attestation is untrustworthy, and neither is a limit violation — so it
  ## is reported as its own verdict rather than folded into STALE. It is
  ## still a finding: an unauditable record must not exit 0.
  if not maxAgeSupplied:
    return (freshUnknown, 0'i64)
  if not hasNewest:
    return (freshUnknown, 0'i64)
  if newestEpoch > nowEpoch:
    return (freshFuture, 0'i64)
  let age = (nowEpoch - newestEpoch) div 86400
  let verdict = if age <= maxAgeDays: freshFresh else: freshStale
  (verdict, age)

func judge*(rows: seq[JsonNode]; firstParent: HashSet[string];
            firstParentSupplied: bool; windows: seq[Window];
            windowsSupplied: bool; nowEpoch: int64;
            maxAgeDays: int64;
            maxAgeSupplied: bool): LedgerReport {.raises: [].} =
  ## Pure: the whole audit as one value. The `*Supplied` flags are what
  ## keep an unperformed check out of the finding set — they are reported as
  ## UNKNOWN instead of masquerading as a clean result.
  result.total = rows.len
  let range = dateRange(rows)
  result.oldestPushedAt = range.oldest
  result.newestPushedAt = range.newest
  result.directPushCheckable = firstParentSupplied
  if firstParentSupplied:
    result.directPushes = findDirectPushes(rows, firstParent)
  result.windowCheckable = windowsSupplied
  if windowsSupplied:
    result.windowMatches = findWindowMatches(rows, windows)
  result.judgedAtEpoch = nowEpoch
  result.maxAgeDays = maxAgeDays
  # `dateRange` renders the newest row as text; re-parse it here so the
  # freshness judgment is over the same absolute instant the sort used
  # rather than over a second, possibly divergent, read of the rows.
  let newest = pushedEpoch(range.newest)
  let fresh = judgeFreshness(newest.get(0'i64), newest.isSome, nowEpoch,
                             maxAgeDays, maxAgeSupplied)
  result.freshness = fresh.verdict
  result.newestAgeDays = fresh.ageDays

func isFinding*(report: LedgerReport): bool {.raises: [].} =
  ## Pure: the single place that decides "finding". Kept next to the report
  ## so the exit code and the text can never disagree about what counts.
  report.directPushes.len > 0 or report.windowMatches.len > 0 or
    report.freshness == freshStale or report.freshness == freshFuture


func reportJson*(report: LedgerReport): JsonNode {.raises: [].} =
  ## Pure: machine-readable projection of the report (the text renderer and
  ## this share the same struct, so the two can never disagree).
  ##
  ## `freshnessCheck` is PERFORMED/UNKNOWN exactly like the other two, so a
  ## consumer that reads only the check fields still cannot mistake an
  ## unasked freshness question for a clean ledger. The measured age is
  ## emitted alongside the verdict rather than recomputed by the consumer:
  ## two clocks would let a consumer re-derive a different answer from the
  ## one the tool exited on.
  %*{
    "schemaVersion": LedgerSchema,
    "totalBypassLandings": report.total,
    "dateRange": {
      "oldest": report.oldestPushedAt,
      "newest": report.newestPushedAt
    },
    "directPushCheck": (if report.directPushCheckable: "PERFORMED"
                        else: "UNKNOWN"),
    "directPushes": report.directPushes,
    "elevationWindowCheck": (if report.windowCheckable: "PERFORMED"
                             else: "UNKNOWN"),
    "elevationWindowMatches": report.windowMatches,
    "freshness": $report.freshness,
    "freshnessCheck": (if report.freshness == freshUnknown: "UNKNOWN"
                       else: "PERFORMED"),
    "freshnessAgeDays": report.newestAgeDays,
    "freshnessMaxAgeDays": report.maxAgeDays,
    "freshnessJudgedAtEpoch": report.judgedAtEpoch,
    "finding": isFinding(report)
  }

func renderReport*(report: LedgerReport): string {.raises: [].} =
  ## Pure: the human report. UNKNOWN lines are printed unconditionally so a
  ## missing input can never read as a passing check.
  ##
  ## Each line is terminated by an explicit LF: `add` concatenates, so a
  ## missing newline would silently fuse the whole report into one line and
  ## hide the UNKNOWN notices inside it.
  let header = "rule_suite_bypass_ledger: " & $report.total & " bypass landing(s)"
  result.add(header & "\n")
  result.add("  date range: " & report.oldestPushedAt & " .. " &
             report.newestPushedAt & "\n")
  if not report.directPushCheckable:
    result.add("  direct-push check: UNKNOWN (no --first-parent set supplied" &
               " — unperformed, NOT zero)\n")
  elif report.directPushes.len == 0:
    result.add("  direct-push check: PASS — every after_sha is a first-parent" &
               " commit of main\n")
  else:
    result.add("  direct-push check: FINDING — " & $report.directPushes.len &
               " landing(s) whose after_sha is not a first-parent commit:\n")
    for p in report.directPushes:
      result.add("    - " & scalar(p, "id") & " " & scalar(p, "pushed_at") &
                 " " & scalar(p, "after_sha") & "\n")
  if not report.windowCheckable:
    result.add("  elevation-window check: UNKNOWN (no --windows document" &
               " supplied — unperformed, NOT zero)\n")
  elif report.windowMatches.len == 0:
    result.add("  elevation-window check: no landing inside a declared window\n")
  else:
    result.add("  elevation-window check: " & $report.windowMatches.len &
               " landing(s) inside declared window(s):\n")
    for m in report.windowMatches:
      result.add("    - " & scalar(m, "id") & " " & scalar(m, "pushed_at") &
                 " [" & scalar(m, "window") & "]\n")
  case report.freshness
  of freshUnknown:
    result.add("  freshness: UNKNOWN (no --max-age-days supplied — unperformed," &
               " NOT fresh; without it a rotted ledger clears its own" &
               " contents)\n")
  of freshFresh:
    result.add("  freshness: FRESH (age=" & $report.newestAgeDays &
               "d, limit=" & $report.maxAgeDays & "d)\n")
  of freshStale:
    result.add("  freshness: STALE (age=" & $report.newestAgeDays &
               "d, limit=" & $report.maxAgeDays & "d) — FINDING: landings" &
               " newer than the ledger's newest row are unrecorded\n")
  of freshFuture:
    # No day count is printed: the exact skew can be seconds, and rounding it
    # to whole days would state a measurement the tool did not make. The two
    # timestamps are both shown so the reader can see the gap directly.
    result.add("  freshness: FUTURE (newest pushed_at " &
               report.newestPushedAt & " is ahead of the judgment clock " &
               $report.judgedAtEpoch & ") — FINDING: the clock or the record" &
               " is wrong, so NEITHER freshness NOR staleness can be" &
               " attested\n")

# ── I/O boundary (the only effectful procs) ─────────────────────────────────

proc readText(path: string): string
    {.axiomEffect: IoEffect, raises: [CatchableError].} =
  readFile(path)

proc writeText(path, text: string)
    {.axiomEffect: IoEffect, raises: [CatchableError].} =
  let dir = parentDir(path)
  if dir.len > 0 and not dirExists(dir):
    createDir(dir)
  writeFile(path, text)

proc readJsonFile(path: string): JsonNode
    {.axiomEffect: IoEffect, raises: [CatchableError].} =
  parseJson(readText(path))

proc loadFirstParent(path: string): HashSet[string]
    {.axiomEffect: IoEffect, raises: [CatchableError].} =
  for line in readText(path).splitLines():
    let s = line.strip()
    if s.len > 0:
      result.incl(s)

proc fail(msg: string)
    {.axiomEffect: IoEffect, noreturn, raises: [CatchableError].} =
  # stderr.writeLine can itself fail (EPIPE on a closed pipe), so the raise
  # set is honest here: a dying stderr must not be silently swallowed.
  stderr.writeLine("rule_suite_bypass_ledger: " & msg)
  quit(2)

proc usage() {.axiomEffect: IoEffect, noreturn, raises: [CatchableError].} =
  fail("usage: merge --raw <api.json> --ledger <ledger.jsonl> [--out <path>]" &
       " | assert --ledger <ledger.jsonl> [--first-parent <shas.txt>]" &
       " [--windows <windows.json>] [--max-age-days <N>] [--now <iso8601>]" &
       " [--json]")

proc parseMaxAgeDays(text: string): int64
    {.raises: [CatchableError].} =
  ## `--max-age-days` must be a POSITIVE integer. Zero or negative is a
  ## configuration error rather than a very strict limit: `0` would report
  ## STALE for a ledger written seconds ago, and a negative limit can never
  ## be satisfied by any real clock — both are almost certainly a mistake,
  ## and a limit nobody can meet silently turns the check into a red light
  ## that gets ignored.
  try:
    result = parseBiggestInt(text).int64
  except ValueError:
    raise newException(ValueError,
                       "--max-age-days is not an integer: " & text)
  if result <= 0:
    raise newException(ValueError,
                       "--max-age-days must be positive: " & text)

proc parseNow(text: string): int64
    {.raises: [CatchableError].} =
  ## `--now` accepts exactly the shape the ledger records
  ## (`YYYY-MM-DDTHH:MM:SS±HH:MM`) so the test clock and the judged
  ## timestamps go through ONE parser — a second, more permissive parser
  ## here would let the two disagree about what an instant is.
  let parsed = pushedEpoch(text)
  if parsed.isNone:
    raise newException(ValueError,
                       "--now is not YYYY-MM-DDTHH:MM:SS±HH:MM: " & text)
  parsed.get()

proc wallClockEpoch(): int64
    {.axiomEffect: IoEffect, raises: [CatchableError].} =
  ## The ONLY reading of the wall clock in this tool. Isolated here so every
  ## judgment above receives `now` as a value and stays `func` +
  ## {.raises: [].} — which is what makes the freshness tests deterministic
  ## instead of racing the host clock.
  getTime().toUnix


proc runMerge(args: seq[string])
    {.axiomEffect: IoEffect, raises: [CatchableError].} =
  var rawPath, ledgerPath, outPath = ""
  var i = 0
  while i < args.len:
    case args[i]
    of "--raw": rawPath = args[i + 1]; i += 2
    of "--ledger": ledgerPath = args[i + 1]; i += 2
    of "--out": outPath = args[i + 1]; i += 2
    else: usage()
  if rawPath.len == 0 or ledgerPath.len == 0:
    usage()

  let rawDoc = readJsonFile(rawPath)
  if rawDoc.kind != JArray:
    fail("raw input is not a JSON array: " & rawPath)

  var existing: seq[JsonNode] = @[]
  if fileExists(ledgerPath):
    let parsed = parseJsonl(readText(ledgerPath))
    if not parsed.ok:
      fail("existing ledger is unparsable: " & ledgerPath)
    existing = parsed.rows

  var incoming: seq[JsonNode] = @[]
  for n in rawDoc.items:
    incoming.add(n)

  let merged = mergeNodes(existing, incoming)
  if not merged.ok:
    fail("conflicting record for id " & $merged.conflictId &
         " — a bypass entry is immutable, so two different bodies for one id" &
         " mean the input is corrupt (fail-closed, ledger not written)")
  if merged.rows.len == 0:
    fail("merge produced an EMPTY ledger — refusing to write (an empty" &
         " ledger is indistinguishable from a failed fetch)")

  let target = if outPath.len > 0: outPath else: ledgerPath
  writeText(target, renderJsonl(merged.rows))
  echo "rule_suite_bypass_ledger: merged — existing=", existing.len,
       " incoming=", incoming.len, " wrote=", merged.rows.len, " -> ", target

proc runAssert(args: seq[string])
    {.axiomEffect: IoEffect, raises: [CatchableError].} =
  var ledgerPath, fpPath, windowsPath, nowText = ""
  var maxAgeText = ""
  var asJson = false
  var i = 0
  while i < args.len:
    if i + 1 >= args.len and args[i] in ["--ledger", "--first-parent",
                                         "--windows", "--max-age-days",
                                         "--now"]:
      fail(args[i] & " requires a value")
    case args[i]
    of "--ledger": ledgerPath = args[i + 1]; i += 2
    of "--first-parent": fpPath = args[i + 1]; i += 2
    of "--windows": windowsPath = args[i + 1]; i += 2
    of "--max-age-days": maxAgeText = args[i + 1]; i += 2
    of "--now": nowText = args[i + 1]; i += 2
    of "--json": asJson = true; i += 1
    else: usage()
  if ledgerPath.len == 0:
    usage()

  let parsed = parseJsonl(readText(ledgerPath))
  if not parsed.ok:
    fail("ledger is unparsable: " & ledgerPath)

  var firstParent: HashSet[string]
  var fpSupplied = false
  if fpPath.len > 0:
    firstParent = loadFirstParent(fpPath)
    if firstParent.len == 0:
      fail("first-parent set is empty: " & fpPath &
           " (an empty chain cannot prove anything — refusing to report PASS)")
    fpSupplied = true

  var windows: seq[Window] = @[]
  var windowsSupplied = false
  if windowsPath.len > 0:
    let doc = readJsonFile(windowsPath)
    let parsedWindows = parseWindows(doc)
    if not parsedWindows.ok:
      fail("malformed windows document: " & windowsPath)
    windows = parsedWindows.windows
    windowsSupplied = true

  var maxAgeDays = 0'i64
  var maxAgeSupplied = false
  if maxAgeText.len > 0:
    try:
      maxAgeDays = parseMaxAgeDays(maxAgeText)
    except ValueError as e:
      fail(e.msg)
    maxAgeSupplied = true

  var nowEpoch = 0'i64
  if nowText.len > 0:
    try:
      nowEpoch = parseNow(nowText)
    except ValueError as e:
      fail(e.msg)
  else:
    nowEpoch = wallClockEpoch()

  let report = judge(parsed.rows, firstParent, fpSupplied, windows,
                     windowsSupplied, nowEpoch, maxAgeDays, maxAgeSupplied)
  if asJson:
    stdout.write($reportJson(report) & "\n")
  else:
    stdout.write(renderReport(report))
  if isFinding(report):
    quit(1)

proc main() {.axiomEffect: IoEffect, raises: [].} =
  # A crash must never reach the caller as exit 1 — that code means "audit
  # finding" here, so an unhandled exception would be indistinguishable from
  # a REAL bypass finding. Every failure inside the run is a judgment that
  # could not be performed, which is exactly what exit 2 is for.
  try:
    let args = commandLineParams()
    if args.len == 0:
      usage()
    case args[0]
    of "merge": runMerge(args[1 .. ^1])
    of "assert": runAssert(args[1 .. ^1])
    else: usage()
  except CatchableError as e:
    try:
      fail(e.msg)
    except CatchableError:
      quit(2)

when isMainModule:
  main()
