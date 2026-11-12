# nim-check: skip
# Rationale: out-of-tree P0-D2 probe (convention:
# experiments/bug-verdict-e2e/cout_probe.nim). It imports the PINNED consumer
# dependency tree (nimbus-eth1 vendor pins, see p0d2/target.md) via explicit
# --path entries into /tmp/p0d2_env/deps; those imports cannot resolve inside
# the Axiom3 repo by design (Zero-Footprint: the subject is never vendored).
#
# Reproduces the consumer decode form of status-im/nimbus-eth1 @ 0c0230857dd8
# (vendor/nim-toml-serialization @ 73529768ced17720f78fb5b57191e863f8d8a9c1):
#   typed object -> confutils generateSecondarySources + addConfigFile(Toml, path)
#   -> serialization loadFile(Toml, path, SecondarySourcesModel) [no flags]
#   -> toml_serialization Reader with flavorRuntimeFlags(Toml) = Toml_v110_Flags
#      (TomlHexEscape active; callers cannot subtract it, reader.nim:62-64).
#
# Consumer-visible effect ports (verbatim logic, cited):
#   - rpc/cors.nim:21-27 sameOrigin/containsOrigin (nimbus-eth1 @ 0c0230857dd8)
#   - devp2p Hello clientId network egress: the decoded string is the RLP
#     byte string put on the wire (devp2p_wire.nim:103,129); RLP framing
#     reproduced below per DEVp2p/RLP rules.
#
# Output is deterministic by construction: no timestamps, no env reads.

import std/[os, strutils, options, uri, unicode, sequtils]
import confutils
import confutils/defs
import confutils/toml/defs            # nimbus-eth1 execution_chain/conf.nim:18
import toml_serialization

type
  # Mirrors the two nimbus-eth1 fields under test (verbatim names + pragmas):
  #   execution_chain/conf.nim:287-290  agentString* {.name: "agent-string" .}: string
  #   execution_chain/conf.nim:489-493  allowedOrigins* {.name: "allowed-origins".}: seq[string]
  ProbeConf = object
    agentString* {.name: "agent-string".}: string
    allowedOrigins* {.name: "allowed-origins".}: seq[string]

# confutils-generated decode model (all fields Option[T]).
# confutils `load` template uses the same consume-the-macro form:
#   let secondarySourcesRef = generateSecondarySources(Configuration)   (confutils.nim:1582)
let primarySources = generateSecondarySources(ProbeConf)

const
  BrowserOrigin = "http://localhost:8080"   # real browser Origin header under test

# --- verbatim port: nimbus-eth1 execution_chain/rpc/cors.nim:21-27 ----------
proc sameOrigin(a, b: Uri): bool =
  a.hostname == b.hostname and a.scheme == b.scheme and a.port == b.port

proc containsOrigin(list: seq[Uri], origin: Uri): bool =
  for x in list:
    if x.sameOrigin(origin):
      return true
# ---------------------------------------------------------------------------

proc hexOf(s: string): string =
  if s.len == 0: return "(empty)"
  var parts: seq[string]
  for c in s: parts.add(toHex(ord(c), 2))
  parts.join(" ")

proc rlpString(s: string): string =
  # DEVp2p/RLP encoding of a byte string (what carries Hello.clientId on the
  # wire). len < 56: single prefix byte 0x80+len. Else 0xb7+lenOfLen + len bytes.
  let n = s.len
  if n < 56:
    result.add(char(0x80 + n))
  else:
    var lenBytes: string
    var m = n
    while m > 0:
      lenBytes.add(char(m and 0xFF))
      m = m shr 8
    for i in countdown(lenBytes.high, 0): result.add(lenBytes[i])
    result.add(char(0xb7 + lenBytes.len))
  result.add(s)

proc corsDecision(configured: seq[string]): string =
  # Exact httpCors decision path for one Origin header (cors.nim:35-50):
  #   origins.len == 0      -> "OK(no-origin: maybe not CORS)"
  #   everyOriginAllowed    -> "OK(Access-Control-Allow-Origin: *)"
  #   containsOrigin(...)   -> "OK(echo origin)"
  #   else                  -> "Http403 'Origin not allowed'"
  let allowedOrigins: seq[Uri] = configured.mapIt(parseUri(it))
  let origin = parseUri(BrowserOrigin)
  let everyOriginAllowed = allowedOrigins.len == 0
  if not everyOriginAllowed and not allowedOrigins.containsOrigin(origin):
    result = "Http403 Origin not allowed"
  elif everyOriginAllowed:
    result = "OK(Allow-Origin: *)"
  else:
    result = "OK(echo " & BrowserOrigin & ")"

proc uriParts(u: Uri): string =
  "scheme=" & (if u.scheme.len == 0: "(empty)" else: u.scheme) &
  " hostname=" & (if u.hostname.len == 0: "(empty)" else: hexOf(u.hostname)) &
  " port=" & (if u.port.len == 0: "(empty)" else: hexOf(u.port)) &
  " path=" & (if u.path.len == 0: "(empty)" else: hexOf(u.path))

proc validUtf8(s: string): string =
  let bad = validateUtf8(s)
  if bad == -1: "well-formed-UTF8" else: "INVALID-UTF8(first-bad-offset=" & $bad & ")"

proc runCase(name: string, path: string) =
  echo "=== case: ", name, " ==="
  echo "input_file: ", path
  let src = new(SecondarySources)     # fresh decode model per case (setter array unused: decode-only)
  var outcome: string
  var decoded = false
  try:
    src.addConfigFile(Toml, InputFile(path))
    decoded = true
    outcome = "decode SUCCESS (no exception)"
  except CatchableError as e:
    outcome = "decode RAISED " & $e.name & ": " & e.msg

  echo "decode_outcome: ", outcome
  echo "process_effect: ",
    (if decoded: "none - config accepted, node would continue startup"
     else: "ConfigurationError propagated (nimbus fatal-quit path: quit QuitFailure)")

  if not decoded:
    return

  let model = src.data[0]
  # The generated model names fields by their `name` pragma verbatim
  # (config_file.nim:257-258,279) - same as the consumer's model.
  let agent = model.`agent-string`
  let origins = model.`allowed-origins`

  echo "field agent-string present: ", isSome(agent)
  if isSome(agent):
    let s = agent.get
    echo "agent_string_bytes_hex: ", hexOf(s)
    echo "agent_string_utf8: ", validUtf8(s)
    echo "agent_string_len: ", s.len
    echo "devp2p_hello_clientId_wire_hex: ", hexOf(rlpString(s)),
         "  (RLP string framing + clientId bytes, devp2p_wire.nim:103,129)"

  echo "field allowed-origins present: ", isSome(origins)
  if isSome(origins):
    let list = origins.get
    for i, o in list:
      let u = parseUri(o)
      echo "allowed_origin[", i, "]_bytes_hex: ", hexOf(o)
      echo "allowed_origin[", i, "]_utf8: ", validUtf8(o)
      echo "allowed_origin[", i, "]_parseUri: ", uriParts(u)
    echo "cors_decision vs Origin <" & BrowserOrigin & ">: ", corsDecision(list)

when isMainModule:
  if paramCount() != 2:
    stderr.writeLine "usage: p0d2_probe <case-name> <config.toml>"
    quit(QuitFailure)
  let name = paramStr(1)
  let path = paramStr(2)
  if not fileExists(path):
    stderr.writeLine "config file not found: " & path
    quit(QuitFailure)
  runCase(name, path)
  quit(QuitSuccess)
