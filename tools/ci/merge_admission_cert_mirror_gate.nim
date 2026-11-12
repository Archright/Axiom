## merge_admission_cert_mirror_gate.nim — certRequired + vaultCertRequired
## mirror consistency
##
## The admission predicate's certificate requirements have FOUR declarations
## (two mirror pairs, same convention for both):
##   policy SSOT — config/policy/merge_admission.json "certRequired"
##   effective   — src/cli/merge_cli.nim `CertRequired*: bool` (compile-time
##                 constant; the ONLY value the predicate actually reads)
##   policy SSOT — config/policy/merge_admission.json "vaultCertRequired"
##   effective   — src/cli/merge_cli.nim `VaultCertRequired*: bool` (same
##                 convention — proof-required admission contract §2.1)
## The policy file documents each flag and the Nim constant documents itself
## as its mirror ("update together"), but nothing checked that they agreed.
## The JSON entries were therefore decorative: flipping `CertRequired` to
## false left every admission demanding a certificate, and flipping the JSON
## to true (the state it already was) proved nothing. Neither drift was
## observable. The second pair (Pass 2.96b — docs/spec/
## proof_required_admission_contract.md §2.1) is enforced by the SAME gate,
## the SAME way: no new gate was created.
##
## This gate is a MIRROR gate, not a policy gate: it asserts the two
## declarations of each pair carry the same value and nothing else. Whether a
## flag should be true or false is a separate decision, owned by the policy
## SSOT and by the semantic regression cases in tests/cli/test_merge_cli.nim
## — this gate must not become a second place where that decision is
## expressed.
##
## Fail-closed in every direction. A missing key, a non-boolean value, an
## unparsable policy file, an unreadable predicate source, a missing
## declaration, or MORE THAN ONE declaration all FAIL. An unreadable input is
## never read as "unchanged": a real drift must not be routable around by
## corrupting the file the mirror is checked against. The declaration anchor
## is matched at the START of the stripped declaration line, so the
## VaultCertRequired* declaration can never satisfy the CertRequired* anchor
## (the former embeds the latter as a suffix — a substring find would see two
## declarations and fail closed for the wrong reason).

import std/[strutils, json]

const
  PolicyPath = "config/policy/merge_admission.json"
  PredicatePath = "src/cli/merge_cli.nim"

type
  MirrorPair = object
    ## One mirror pair: the policy key and the declaration anchor. The
    ## exported marker (`*`) and the explicit type are part of the anchor so
    ## that a rename, a type change, or a second declaration cannot move the
    ## effective value out from under this gate without the anchor failing to
    ## match.
    key: string
    anchor: string

const MirrorPairs: seq[MirrorPair] = @[
  MirrorPair(key: "certRequired", anchor: "CertRequired*: bool = "),
  MirrorPair(key: "vaultCertRequired", anchor: "VaultCertRequired*: bool = "),
]

type
  MirrorRead = object
    ## `value` is only meaningful when `err == ""`.
    value: bool
    err: string

func stripJsonc(raw: string): string =
  ## Drop full-line `//` comments before JSON parsing (JSONC convention used
  ## by the config/ policy family — see epoch_transaction_gate.nim).
  var lines = raw.splitLines()
  for i in 0 ..< lines.len:
    if lines[i].strip(leading = true).startsWith("//"):
      lines[i] = ""
  lines.join("\n")

proc readPolicyFlag(key: string): MirrorRead =
  var raw = ""
  try:
    raw = readFile(PolicyPath)
  except CatchableError:
    return MirrorRead(err: PolicyPath & " unreadable (fail-closed)")
  if raw.strip().len == 0:
    return MirrorRead(err: PolicyPath & " is empty (fail-closed)")
  var node: JsonNode
  try:
    node = parseJson(stripJsonc(raw))
  except CatchableError:
    return MirrorRead(err: PolicyPath & " unparsable (fail-closed)")
  if node.kind != JObject or not node.hasKey(key):
    return MirrorRead(err: PolicyPath & " has no '" & key & "' field (fail-closed)")
  let declared = node[key]
  if declared.kind != JBool:
    return MirrorRead(err: PolicyPath & "." & key & " is not a boolean (kind=" &
                      $declared.kind & ") (fail-closed)")
  MirrorRead(value: declared.getBool())

proc readPredicateConst(anchor: string): MirrorRead =
  var raw = ""
  try:
    raw = readFile(PredicatePath)
  except CatchableError:
    return MirrorRead(err: PredicatePath & " unreadable (fail-closed)")
  var hits: seq[string]
  for line in raw.splitLines():
    let stripped = line.strip(leading = true)
    # Anchored at line start (after leading whitespace): the declaration must
    # OPEN the line, so a longer constant whose name embeds this anchor as a
    # suffix (VaultCertRequired* ⊃ CertRequired*) never matches here.
    if stripped.startsWith(anchor):
      hits.add(stripped[anchor.len .. ^1].strip())
  if hits.len == 0:
    return MirrorRead(err: PredicatePath & " declares no '" & anchor.strip() &
                      "<bool>' constant (fail-closed)")
  if hits.len > 1:
    return MirrorRead(err: PredicatePath & " declares '" & anchor.strip() &
                      "' " & $hits.len & " times — the effective value is ambiguous (fail-closed)")
  let token = hits[0]
  if token == "true":
    return MirrorRead(value: true)
  if token == "false":
    return MirrorRead(value: false)
  MirrorRead(err: PredicatePath & " '" & anchor.strip() & "' value '" & token &
             "' is neither true nor false (fail-closed)")

proc checkPair(pair: MirrorPair) =
  let policy = readPolicyFlag(pair.key)
  let predicate = readPredicateConst(pair.anchor)
  if policy.err.len > 0:
    echo "❌ ", pair.key, " mirror: ", policy.err
    quit(1)
  if predicate.err.len > 0:
    echo "❌ ", pair.key, " mirror: ", predicate.err
    quit(1)
  let policyWord = if policy.value: "true" else: "false"
  let predicateWord = if predicate.value: "true" else: "false"
  if policy.value != predicate.value:
    echo "❌ ", pair.key, " mirror DRIFT — ", PolicyPath, ".", pair.key, "=", policyWord,
         " but ", PredicatePath, " ", pair.anchor.strip(), "=", predicateWord,
         ". The predicate reads the compile-time constant, so the policy SSOT is decorative.",
         " Change both in the same commit (fail-closed)."
    quit(1)
  echo "✅ ", pair.key, " mirror aligned — ", PolicyPath, ".", pair.key, " == ",
       PredicatePath, " ", pair.anchor.strip(), " == ", policyWord

proc main() =
  for pair in MirrorPairs:
    checkPair(pair)

main()
