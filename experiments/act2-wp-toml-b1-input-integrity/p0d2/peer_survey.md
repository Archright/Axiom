# P0-D2 peer survey — peer-side handling of an ill-formed devp2p `clientId`

Experiment: `act2-wp-toml-b1-input-integrity/p0d2` · Survey date: 2026-10-12
Question left open by the 3-way contrast (experiment.md): does the egress delta — a
devp2p Hello `clientId` whose byte string is `87 6E 69 6D 62 75 73 80` (lone `0x80`,
invalid UTF-8, unreachable by any valid TOML input) — change any peer-side
security-relevant outcome?

Method: read-only source survey of the receiving implementations. No repository was
modified; clones used for grepping live in `/tmp/peer_survey` only. No severity
assessment, no CVSS, no issue filed.

## Refs surveyed (pinned)

| repo | ref |
|---|---|
| ethereum/devp2p (spec) | `2c19a28b25c2` (master) |
| ethereum/go-ethereum | `3a6c2e3b35ef8caa3d39dcbea3fe9f09099cca8c` (master) |
| NethermindEth/nethermind | `2cbc4fd99995` (master) |
| hyperledger/besu | `d05d8e745383699dd686e6efb090eddeb63a7380` (master) |
| erigontech/erigon | `1d3ebbf217f6b4f99028cd590889a5c9f3aaa969` (main) |
| status-im/nimbus-eth1 | `af9e318f80f2` (master) |
| status-im/nimbus-eth2 | `657beb3d6e13` (master) |
| status-im/nim-eth | `91596d606dab` (master) |

## 1. What does the wire format allow?

The devp2p capability handshake is specified in `rlpx.md` of `github.com/ethereum/devp2p`
(there is no `devp2p.md` in the repo — 404; the spec set is `rlpx.md`, `discv4.md`,
`discv5/`, `enr.md`, `dnsdisc.md`, `caps/`). The "p2p" capability Hello section says,
verbatim:

> `clientId` Specifies the client software identity, as a human-readable string (e.g.
> "Ethereum(++)/1.0.0").

That is the entire normative content about `clientId`. Consequences:

- **No encoding constraint.** The spec never says "UTF-8". RLP strings are byte strings;
  `87 6E 69 6D 62 75 73 80` is a perfectly valid RLP byte string. The `rlpx.md` RLP
  reference (ethereum.org RLP docs / Yellow Paper Appx B) likewise carries no
  character-encoding requirement.
- **No length limit in the spec.** The only related spec rules are generic: implementations
  must ignore additional list elements in Hello (EIP-8 forward compatibility:
  "Implementations must ignore any additional list elements in Hello because they may be
  used by a future version."), and messages carrying uncompressed data larger than 16 MiB
  "should be rejected by closing the connection" (EIP-706 snappy note). Each implementation
  applies its own smaller Hello cap (2 KiB in Geth, Nethermind, Besu; 16 MiB
  `maxMsgSize` in nimbus-eth1's rlpx.nim:46-48).
- **What a peer must do with unexpected bytes: nothing is specified.** The only
  malformed-input hook is the Disconnect reason table: `0x02` = "Breach of protocol,
  e.g. a malformed message, bad RLP, ...". Since an ill-formed-UTF-8 but well-formed-RLP
  `clientId` is not malformed RLP, the spec gives peers no basis to reject it. EIP-8 and
  EIP-706 (both referenced from rlpx.md) impose no constraint on `clientId` content either.

So: a lone `0x80` inside `clientId` is spec-conformant at the wire level. Anything a peer
does with it (accept, log, normalize, dispatch) is implementation policy.

## 2 + 3. What do implementations do with it, and where does it go?

| implementation | receive path (file:line) | validated? | where it goes | ill-formed value changes behavior? |
|---|---|---|---|---|
| go-ethereum `3a6c2e3b` | `p2p/transport.go:154-181` (`readProtocolHandshake`: 2 KiB cap `p2p/peer.go:44`, msg-code check, RLP decode `p2p/peer.go:60-70` struct, pubkey check `:176-178`) | **No content check** — `Name string` RLP-decoded raw; Go strings are byte sequences; no UTF-8 or length validation (go-ethereum `rlp` package has no UTF-8 check) | stored verbatim `p2p/server.go:920`; truncated to 20 bytes for display `p2p/peer.go:160-167`; log lines `p2p/server.go:677`, `eth/handler.go:321,390`; JSON RPC `admin_peers` via `PeerInfo.Name` `p2p/peer.go:553,571` → `node/api.go:307` | **NO** (surveyed paths: logs, RPC JSON, display only; no comparison/dispatch on the name anywhere in `p2p`, `eth`, `ethstats`, `internal/ethapi`) |
| Nethermind `2cbc4fd9` | `Network/P2P/Messages/HelloMessageSerializer.cs:58-67` (decode; 1024-byte RlpLimit `:15`; 2 KiB msg cap `P2PProtocolHandler.cs:41,99-101`) | **Length-capped and UTF-8-normalized**: `RlpHelpers.Cursor.cs:776-781` `DecodeString` → `Encoding.UTF8.GetString(bytes)` — .NET replaces invalid sequences with U+FFFD at decode time | `P2PProtocolHandler.cs:295-296` (`RemoteClientId`, `Session.Node.ClientId`); trace logs `:357-360`, `:425`; event args `:336-344`; JSON RPC `Admin/PeerInfo.cs:65`, `Parity/PeerInfo.cs:35`; diag tracer `NetworkDiagTracer.cs:77-80`; node stats `Network.Stats/Model/P2PNodeDetails.cs:11`; pivot sync logs `StartingSyncPivotUpdater.cs:192-207`; exception text `HelloMessageSerializer.cs:92` | **NO** — the ill-formed bytes never survive decode; every sink sees a U+FFFD-sanitized string. No dispatch on ClientId found in any surveyed file |
| Besu `d05d8e74` | `rlpx/connections/netty/DeFramer.java:154-182` (2 KiB cap `:66`, RLPException → disconnect `:171-173`, nodeId-vs-authenticated check `:182`); `HelloMessage.java:56` → `PeerInfo.readFrom` | **UTF-8-normalized**: `PeerInfo.java:68` `new String(bytes, StandardCharsets.UTF_8)` — Java replaces malformed input with U+FFFD. Also derives a dispatch key: `PeerInfo.java:62,168-172` `detectClientName` (split at first `/`) → `PeerClientName.fromAgentName` exact `equals` (`PeerClientName.java:38-45`) | toString is OWASP-sanitized for logs (`PeerInfo.java:133-135`, `Encode.forJava`); connect/disconnect logs `netty/ApiHandler.java:89-125`; JSON RPC peers `api/.../PeerResult.java:43` | **NO** — bytes normalized at decode; the derived clientName would be identical for a trailing-byte delta (prefix match before `/`), and **no consumer of `getClientName()`/`PeerClientName` was found in the surveyed modules** (`ethereum/p2p`, `ethereum/api`, `ethereum/core`) — it is currently derived but unread |
| Erigon `1d3ebbf2` | `p2p/transport.go:159-186` (same shape as Geth: 2 KiB cap, RLP decode `p2p/peer.go:65-74`, pubkey check only) | **No content check** — same Go `string` semantics | stored verbatim `p2p/server.go:1015`; 20-byte display truncation `p2p/peer.go:161-167`; log lines `p2p/server.go:775`, `p2p/sentry/sentry_grpc_server.go:313,407,417,722`; optional diagnostics `:616,983` → `trackPeerStatistics` (`:624-639`, `diaglib.PeerStatisticMsgUpdate` carries `PeerName=Fullname`, only when diagnostics enabled) | **NO** on surveyed paths — logs and optional diag records only; no string comparison on the name found in `p2p` |
| nimbus-eth1 `af9e318f` (the same client family as the egress source) | `execution_chain/networking/devp2p_wire.nim:126-138` (helloThunk) + `rlpx.nim:529-556` (`helloHandshake`: first-msg check, RLP read `:537`, nodeId-match check `:538-542`, decode failure → BreachOfProtocol `:556`); decode is `nim-eth eth/rlp.nim:377-381` `readImpl(string)` = byte copy, **no UTF-8 validation** | **Stored raw** — `rlpx.nim:386` `peer.clientId = h.clientId`, no length cap beyond msg size, no encoding check | chronicles log lines (~12 sites: `rlpx.nim:242,258,266,279,334,538,624,630,638`; `devp2p_wire.nim:136-137,152-153`; `eth_broadcast.nim`, `eth_responder.nim`); two `startsWith("Nethermind")` log gates (`rlpx.nim:327-329`, `devp2p_wire.nim:150-153`); JSON RPC peers `rpc/common.nim:120,138` (+`networking/p2p_peers.nim:71`); snap-sync peer type: `snap/worker/start_stop.nim:106` `buddy.only.peerType = buddy.peer.clientId.split('/',1)[0]` (field `worker_desc.nim:111` "Self declared peer type"; consumed only by a debug log `worker.nim:74-79` and a debug tuple accessor `worker_desc.nim:178-184`) | **NO in current code** — for the specific delta in question (one trailing `0x80`): `startsWith("Nethermind")` unchanged (prefix match unaffected by trailing bytes); `split('/')[0]` unchanged (no `/` inserted); all other sinks are logs/RPC display. Unlike all other surveyed clients, nimbus-eth1 keeps the raw bytes in memory, so *future* name-dependent logic would observe them |
| nimbus-eth2 `657beb3d` | **Does not implement the devp2p Hello.** It is a libp2p beacon node; repo has no rlpx/devp2p wire code (path search empty). Its `clientId` symbol (`networking/eth2_network.nim:252`) is a local constant for its own banner/logging; the eth2 "Hello" is the libp2p status RPC (different protocol) | n/a | n/a | **UNKNOWN→inapplicable** — no devp2p Hello receive path exists to exercise |
| nim-eth `91596d60` | **No longer contains the devp2p Hello code**: `eth/p2p` holds only `discoveryv5`; commit `ac1be3135a` "Move p2p code to execution client (#777)" relocated the RLPx peer/hello stack into the execution client (now `nimbus-eth1/execution_chain/networking/`). The RLP string decode it contributes (`eth/rlp.nim:377-381`) is a raw byte copy with no UTF-8 validation | see nimbus-eth1 | see nimbus-eth1 | see nimbus-eth1 |

### Sink details that matter for the impact question

- **Logging.** Every surveyed client logs the peer's clientId at least at trace/debug level
  (a remote peer fully controls this value — it is a remote-controlled log field). Geth's
  logfmt path escapes non-printables via `strconv.Quote` (`log/format.go:320`); its JSON
  output uses Go `encoding/json`, which replaces invalid UTF-8 with U+FFFD at marshal time.
  nimbus-eth1's chronicles performs no UTF-8 validation; text output embeds the raw byte.
  Nethermind and Besu strings are already U+FFFD-normalized before any log sees them.
- **Metrics/dashboards.** No surveyed client uses clientId as a Prometheus label. Erigon
  passes it into optional diagnostics records (`diaglib.PeerStatisticMsgUpdate.PeerName`),
  Nethermind into its node-stats model; both are observational, not decision paths.
- **String comparison / dispatch.** Exactly three dispatch points exist in the surveyed code:
  1. nimbus-eth1 `startsWith("Nethermind")` log gates (`rlpx.nim:327`, `devp2p_wire.nim:151`)
     — a workaround for NethermindEth/nethermind#7727 (Nethermind sending BreachOfProtocol on
     network-id mismatch). A trailing `0x80` does not change the match outcome.
  2. nimbus-eth1 snap `peerType = clientId.split('/',1)[0]` (`start_stop.nim:106`) —
     logging/diagnostics only; unchanged by a trailing byte.
  3. Besu `PeerClientName.fromAgentName` exact-match (`PeerInfo.java:168-172`) — no
     consumers found in the surveyed modules; identical result for a trailing-byte delta
     (and unreachable anyway after Java's UTF-8 normalization).
  No client found compares the name against a version, gates protocol behavior on it, uses
  it as a filename/identifier/shell argument, or renders it into HTML.
- **JSON RPC.** Geth `admin_peers` (`node/api.go:307`), Nethermind admin/parity peer lists
  (`Admin/PeerInfo.cs:65`, `Parity/PeerInfo.cs:35`), Besu `PeerResult.java:43`, nimbus-eth1
  `rpc/common.nim:138` — in all cases the value reaches an operator-facing JSON response
  (after each runtime's UTF-8 handling; Go's `encoding/json` coerces invalid bytes to U+FFFD,
  .NET/Java normalize at decode, Nim emits raw bytes).

## 4. History: clientId-based attacks or advisories?

- Published GitHub Security Advisories for the surveyed clients: `ethereum/go-ethereum`
  lists multiple p2p advisories (several "DoS via malicious p2p message", one RLPx ECIES
  key-validation flaw GHSA-m6j8-rg6r-7mv8, one consensus flaw, one GraphQL DoS); none
  involve `clientId`/`clientVersion` content. **No published advisories at all** were found
  for Nethermind, Besu, Erigon, or nimbus-eth1 via the GitHub advisory API.
- Closest precedent, and it is about a *log* sink, not clientId: GHSA-wjxw-gh3m-7pm5 —
  go-ethereum could crash at high-verbosity logging when handling specially crafted p2p
  messages (fixed in PR #24507, 2022-01). Demonstrates that the logging path around p2p
  input has had defects, but that advisory does not involve the Hello name.
- Interop precedent for name-gated behavior: NethermindEth/nethermind#7727 (Nethermind
  emits `BreachOfProtocol` on network-id mismatch), which is why nimbus-eth1 carries the
  `clientId.startsWith("Nethermind")` log gates cited above — the one live example of
  clientId-conditioned code in the surveyed set (log-path only).
- No prior work on log-injection via client version strings or RLP-string validation gaps
  surfaced in GitHub issue/advisory searches for these repos (searched `clientId`,
  `clientVersion`, "hello" terms; see coverage limits).

## 5. Established vs. still unknown

**Established by this survey:**

1. The RLPx spec constrains `clientId` only as "a human-readable string"; no encoding or
   length rule exists, and the spec defines no rejection behavior for unexpected byte
   content. An ill-formed-UTF-8 but well-formed-RLP clientId is spec-legal on the wire.
2. Geth and Erigon accept and store it verbatim; Nethermind and Besu normalize it to
   U+FFFD at decode; nimbus-eth1 accepts and stores it verbatim (nimbus-eth2 has no such
   receive path; nim-eth no longer hosts one).
3. In all surveyed implementations, every post-receipt use is observational (log lines,
   RPC peer listings, optional diagnostics). The only three name-derived dispatch points
   (nimbus-eth1's two `startsWith` log gates and snap `peerType`; Besu's unread
   `PeerClientName` derivation) produce **identical outcomes for the concrete defect delta
   (one trailing `0x80`)** as for the well-formed contrast value.
4. Therefore, for the surveyed code at the pinned refs: an ill-formed (invalid UTF-8)
   devp2p `clientId` does **not** change any security-relevant outcome on any surveyed
   path. It is inert in current behavior — recorded as a clean negative.

**Still unknown / coverage limits:**

- Verdicts are source-level, at the pinned commits (all `master`/`main` as of 2026-10-12).
  No live node was connected to; no fuzzing or dynamic test of the receive path was run.
- Other devp2p-speaking implementations were **not** surveyed: OpenEthereum
  (discontinued), Reth, Grandine, and other or custom/private clients. A peer that,
  unlike those surveyed, compares or re-emits the raw name in a decision path would
  fall outside this table.
- Erigon's RPC peer surface and any decision logic outside `p2p/`+`eth/` (e.g. its
  grpc sentry consumers) were only partially traced; `nim-eth` history beyond the move
  commit was not audited.
- Besu's `PeerClientName` "no consumers" finding is limited to the surveyed modules
  (`ethereum/p2p`, `ethereum/api`, `ethereum/core`) — plugin code could consume it via
  the `plugin-api` PeerInfo interface.
- chronicles' JSON writer escape-set was not pinned to a commit; the text-format path
  (raw bytes embedded) is the load-bearing observation for nimbus-eth1 log sinks.
- The advisory search covered GitHub's published GHSAs and issue text search; it cannot
  exclude non-public bounty reports or advisories hosted outside GitHub.
- Whether any *combination* of an ill-formed clientId with another input (e.g. a log
  aggregator that parses chronicles JSON, or a monitoring stack that treats the raw byte
  specially) behaves differently was not tested — out of scope here.
