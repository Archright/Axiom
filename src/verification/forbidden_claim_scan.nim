import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## INV-9 forbidden-claim sentence scanner — pure, deterministic, fail-closed.
##
## Closes ADR-0030 Residual Limit U2 ("INV-9 static scan unimplemented"):
## `docs/spec/certification_continuity_contract.md` §5 INV-9 mandates a static
## scan of certificate-adjacent text for forbidden claim sentences; ADR-0030
## (docs/adr/0030-rust-subject-semantic-authority.md, U2 + D3) requires the same
## scan to catch the Rust analogue.
##
## Vocabulary derivation (closed set — every entry cites its contract text):
##   1. "Nim semantics certified"     — INV-9 row, named verbatim.
##   2. "최종 TCB 폐쇄"                — INV-9 row, named verbatim.
##   3. "Rust semantics certified"    — ADR-0030 U2: "the same scan must catch
##                                      the Rust analogue ('Rust semantics
##                                      certified')"; also D3.
##   4. "source semantics certified"  — the source-level axis both contracts
##                                      fix as forbidden: D3 bounds every Rust
##                                      artifact claim to "verified w.r.t. the
##                                      extracted representation under a
##                                      Qualified extractor"; a source-semantics
##                                      certification claim is the unconditional
##                                      form the bounded shape replaces. The
##                                      phrase containment also catches the
##                                      "<Lang> source semantics certified"
##                                      spellings for any subject language
##                                      without extending the set.
##
## Matching discipline (deterministic, NOT fuzzy):
##   - exact phrase match, case-sensitive (the contracts name the sentences in
##     canonical casing; paraphrase/letter-case evasion is out of scope for a
##     closed honesty vocabulary — the set grows only by contract amendment);
##   - word boundaries on both ends: an adjacent [A-Za-z0-9_] character
##     (identifier char) cancels the match ("XRust semantics certified",
##     "certifiedX" do not match); all other characters (space, punctuation,
##     Hangul) are boundaries;
##   - stdlib strutils only — no regex, same input -> same findings, in
##     declaration order then left-to-right.
##
## Scan surface (the contract names the certificate payload): certificate JSON
## payloads — every string value is scanned (leanProposition / leanSource /
## reason are the v1 claim fields; scanning ALL string values keeps the surface
## closed when fields are added). Free-text targets are scanned as raw text.
##
## Allowlist discipline (docs/spec/theater_allowlist_stability.md): an entry is
## anchored by file + symbol + ruleId + contentHash, where symbol is the JSON
## field path ("reason", "claim.note", "entries[0].reason") and contentHash is
## sha256Hex of the offending string VALUE. All four must match — any drift in
## the sanctioned occurrence (tamper, moved field, edited sentence) breaks the
## anchor and the finding resurfaces as a FAIL.
##
## Fail-closed: this module is pure. The I/O boundary (the CLI runner) must
## treat an unreadable or unparseable scan target as FAIL, never skip.

import std/[json, strutils]
import core/crypto/hash_kernel

type
  ForbiddenClaimRule* = object
    ruleId*: string
    phrase*: string
    contract*: string

  ClaimFinding* = object
    ruleId*: string
    phrase*: string
    offset*: int   ## byte offset of the match inside the scanned text
    line*: int     ## 1-based line of the match inside the scanned text

  PayloadFinding* = object
    symbol*: string  ## JSON field path — the allowlist symbol anchor
    ruleId*: string
    phrase*: string
    value*: string   ## full string value; content-hash input for the allowlist
    offset*: int
    line*: int

  ClaimAllowlistEntry* = object
    file*: string        ## repo-relative scanned-file identity
    symbol*: string      ## JSON field path of the sanctioned occurrence
    ruleId*: string      ## forbidden-claim rule the entry sanctions
    contentHash*: string ## sha256Hex of the sanctioned string VALUE
    note*: string        ## human justification (derived evidence, not identity)

const
  forbiddenClaimRules*: array[4, ForbiddenClaimRule] = [
    ForbiddenClaimRule(
      ruleId: "INV9-NIM-SEM-CERT",
      phrase: "Nim semantics certified",
      contract: "certification_continuity_contract.md section 5 INV-9 (verbatim)"),
    ForbiddenClaimRule(
      ruleId: "INV9-TCB-FINAL-CLOSURE",
      phrase: "\xEC\xB5\x9C\xEC\xA2\x85 TCB \xED\x8F\x90\xEC\x87\x84",
      contract: "certification_continuity_contract.md section 5 INV-9 (verbatim)"),
    ForbiddenClaimRule(
      ruleId: "INV9-RUST-SEM-CERT",
      phrase: "Rust semantics certified",
      contract: "ADR-0030 U2 + D3 (verbatim)"),
    ForbiddenClaimRule(
      ruleId: "INV9-SOURCE-SEM-CERT",
      phrase: "source semantics certified",
      contract: "ADR-0030 D3 source-level axis (derived; containment covers " &
                "\"<Lang> source semantics certified\")"),
  ]

func isClaimIdentChar*(c: char): bool {.inline, raises: [].} =
  ## Identifier-class characters cancel a word boundary.
  c in {'a'..'z', 'A'..'Z', '0'..'9', '_'}

func lineOf(text: string; idx: int): int {.raises: [].} =
  ## 1-based line of byte offset `idx`.
  result = 1
  for i in 0 ..< idx:
    if text[i] == '\n':
      inc result

func findForbiddenClaims*(text: string): seq[ClaimFinding] {.raises: [].} =
  ## Deterministic closed-vocabulary scan of one text blob.
  ## Order: rule declaration order, then left-to-right by offset.
  result = @[]
  for rule in forbiddenClaimRules:
    var start = 0
    while true:
      let idx = text.find(rule.phrase, start)
      if idx < 0:
        break
      let beforeOk = idx == 0 or not isClaimIdentChar(text[idx - 1])
      let afterIdx = idx + rule.phrase.len
      let afterOk = afterIdx >= text.len or not isClaimIdentChar(text[afterIdx])
      if beforeOk and afterOk:
        result.add(ClaimFinding(
          ruleId: rule.ruleId, phrase: rule.phrase,
          offset: idx, line: lineOf(text, idx)))
      start = idx + 1

func payloadPath(parent: string; key: string): string {.raises: [].} =
  if parent.len == 0:
    key
  else:
    parent & "." & key

func scanCertPayloadInto(node: JsonNode; path: string;
                         outp: var seq[PayloadFinding]) {.raises: [].} =
  case node.kind
  of JString:
    let value = node.getStr()
    for f in findForbiddenClaims(value):
      outp.add(PayloadFinding(
        symbol: if path.len == 0: "(root)" else: path,
        ruleId: f.ruleId, phrase: f.phrase, value: value,
        offset: f.offset, line: f.line))
  of JObject:
    for key, value in node:
      scanCertPayloadInto(value, payloadPath(path, key), outp)
  of JArray:
    for i in 0 ..< node.len:
      scanCertPayloadInto(node[i], path & "[" & $i & "]", outp)
  else:
    discard

func scanCertPayload*(node: JsonNode): seq[PayloadFinding] {.raises: [].} =
  ## Scan EVERY string value of a certificate payload (recursively).
  ## The symbol anchor is the JSON field path; array elements carry an index
  ## suffix ("entries[0].reason"). Deterministic: document order in, findings
  ## in document order out.
  result = @[]
  scanCertPayloadInto(node, "", result)

func findingContentHash*(f: PayloadFinding): string {.raises: [].} =
  ## Allowlist content identity — sha256 of the full offending string VALUE.
  sha256Hex(f.value)

func isAllowlisted*(f: PayloadFinding; file: string;
                    e: ClaimAllowlistEntry): bool {.raises: [].} =
  ## Canonical anchor match: file + symbol + ruleId + contentHash, ALL four.
  ## `line`/`offset` are derived evidence and never part of the anchor
  ## (theater_allowlist_stability.md). A tampered value re-hashes differently
  ## and un-allowlists the finding — sanctioned occurrences cannot drift.
  e.file == file and e.symbol == f.symbol and e.ruleId == f.ruleId and
    e.contentHash == findingContentHash(f)

func allowlistedCount*(findings: seq[PayloadFinding]; file: string;
                       allowlist: seq[ClaimAllowlistEntry]): int {.raises: [].} =
  ## Deterministic allowlist application: a finding is allowlisted when ANY
  ## entry matches its full canonical anchor.
  result = 0
  for f in findings:
    for e in allowlist:
      if isAllowlisted(f, file, e):
        inc result
        break
