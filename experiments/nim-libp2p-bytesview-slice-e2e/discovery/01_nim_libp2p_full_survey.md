# nim-libp2p — read-only inventory report

Target: `<workspace>/nim-libp2p` @ `a130a7f32` (status-im/nim-libp2p fork, package version 2.4.0). Repo was not modified; scratch experiments were done on copies under `/tmp` and have been removed.

---

## 1. BUILD & TOOLCHAIN

**Nim version — exact match with the verifier's pin (2.2.10):**

| source | statement |
|---|---|
| `libp2p.nimble:10` | `requires "nim >= 2.2.4"` |
| `Makefile:6` | `NIM_VERSION ?= 2.2.10` |
| `Makefile:60,78,81` | every nimble invocation passes `--requires:"nim == $(NIM_VERSION)"` |
| `nix/libp2p.lock:3-11` | nim pinned to `2.2.10`, rev `9fe2137fa2f3f66cf5a44f357d461829ac9e20c4` |
| `nix/deps.nix:5-9` | nim fetched via `pkgs.fetchgit` at that rev |
| `flake.nix:115` | devShell uses `pkgs.nim-2_2` |
| `.github/workflows/*.yml` | `nim_ref: v2.2.10` (cbindings.yml and others) |
| `README.md:36` | "The currently supported Nim versions are v2.2.4 and v2.2.10." |

→ **Yes, it compiles under Nim 2.2.10** — that is the exact pinned/CI version, not merely "plausible".

**Hard dependency set** (`libp2p.nimble:10-17`; all versions pinned in `nix/libp2p.lock`):

`nimcrypto ≥0.6.0` (lock: 0.6.4) · `bearssl ≥0.2.7` (0.2.8) · `https://github.com/vacp2p/nim-boringssl ≥0.0.14` (0.0.14) · `chronicles ≥0.12.3` (0.12.3) · `chronos ≥4.2.2` (4.2.2) · `metrics ≥0.2.2` (0.2.2) · `secp256k1` (0.6.0.3.2) · `stew ≥0.4.2` (0.4.2) · `results` (0.5.1) · `serialization ≥0.5.0` (0.5.0) · `json_serialization ≥0.4.4` (0.4.4) · `lsquic ≥0.11.2` (0.11.2) · `protobuf_serialization ≥0.6.0` (0.6.0) · `https://github.com/status-im/nim-websock ≥0.4.1` (0.4.1) · `https://github.com/logos-storage/nim-libplum ≥0.6.2` (0.6.2). Transitive: `unittest2 0.2.5`, `faststreams 0.5.1`, `npeg 1.3.0`, `httputils 0.4.1`, `zlib 0.1.0`, `testutils 0.8.2`, `libbacktrace` (tests only, `tests/tests.nimble:9`).

**Vendored or fetched?** *Fetched, never vendored.* `.gitignore:20,22,42,45` excludes `nimbledeps/` and `nimble.paths`; neither exists in the checkout. `config.nims:2-3` only adds `nimbledeps/pkgs2` to `NimblePath` *if* it exists. `Makefile:78-81` populates it via `nimble --noLockfile --resolver:minver -l setup`. `nix/deps.nix` is the Nix-pinned mirror. **Implication for the verifier: a Lean-4 extraction of the pure modules needs only `stew`, `nimcrypto`, `results` — the heavy `boringssl`/`lsquic`/`secp256k1` C stack is avoidable.**

**Other build facts:** `config.nims:5-19` turns 14 warnings + 4 hints into errors (incl. `UnreachableCode`, `UnreachableElse`, `UnusedImport`); `config.nims:25-27` pins `--mm: refc`; `config.nims:31-33` adds `nimRawSetjmp` on Windows; `Makefile:22-23` ASan builds use `--mm:orc` (assertions off by default in orc/release? — see §6).

---

## 2. PRE-EXISTING REQUIREMENTS / PROPOSITIONS

**There is no spec/ directory and no formal requirement document.** `docs/` holds only 9 operational guides (`README.md`, `common_hurdles.md`, `compile_time_flags.md`, `contributing.md`, `development.md`, `interop_hole_punching.md`, `logging.md`, `mobile_android.md`, `mobile_ios.md`). `mkdocs.yml:10` sets `docs_dir: examples` — the published "documentation" is the example tutorials; `mkdocs.yml:52` points the reference at nimdoc output only. Grepping the whole repo for `MUST|SHALL|REQUIRED` yields **exactly one hit inside `libp2p/`**: `libp2p/protocols/pubsub/gossipsub/partial_message.nim:10` — "views of the same logical message MUST use the same GroupId."

The normative content therefore lives **in doc-comments and in code invariants**. The strongest 10:

1. `libp2p/varint.nim:5-11` — "Google ProtoBuf varint, which is able to encode full uint64 number and maximum size of encoded value is 10 octets… LibP2P varint, which is able to encode only 63bits of uint64 number and maximum size of encoded value is 9 octets."
2. `libp2p/varint.nim:119-127` — "When decoding 10th byte of Google Protobuf's 64bit integer only 1 bit from byte will be decoded, all other bits will be ignored." (same for the 5th byte of a 32-bit int)
3. `libp2p/stream/lpstream.nim:51-56` — the **stream read/write state table**:
   ```
   #        X        |           Read            |         Write
   #   Local close   |           Works           |  LPStreamClosedError
   #  Remote close  | LPStreamRemoteClosedError |         Works
   #   Local reset   |    LPStreamClosedError    |  LPStreamClosedError
   #  Remote reset  |    LPStreamResetError     |  LPStreamResetError
   # Connection down |     LPStreamConnDown      | LPStreamConnDownError
   ```
4. `libp2p/muxers/mplex/lpchannel.nim:26-36` — the **channel half-close state table**: "| State | Closed local | Closed remote |  | Read | Yes (until EOF) | No |  | Write | No | Yes |" + "Channels are considered fully closed when both outgoing and incoming directions are closed and when the reader of the channel has read the EOF marker".
5. `libp2p/utils/iptree.nim:66-68` — "Counters never go below zero. Any trailing run of nodes left at counter 0 with no children is unlinked, so a fully-removed address doesn't leave dead nodes behind." (+ `:119` "Returns an IP similarity score in **[0.0, 1.0]**"; `:123-124` the exact threshold law "root.counter / 2^(depth+1)").
6. `libp2p/peerstore.nim:206` — "A previously verified (High/Infinite) address is **never downgraded**"; `:262` "a high-confidence entry is never downgraded by a lower-confidence update"; `:264` "a verified dial address is never evicted by a later Identify update"; `:183` "Returns true **only when** the TTL is positive and the elapsed time exceeds it".
7. `libp2p/muxers/yamux/yamux.nim:515-519` — "During initialization, recvWindow can be larger than maxRecvWindow. This is because the peer we're connected to will always assume that the initial recvWindow is 256k. To solve this contradiction, no updateWindow will be sent until recvWindow is less than maxRecvWindow".
8. `libp2p/multibase.nim:395-407` — "Return estimated size of buffer to store MultiBase encoded value… Procedure returns `-1` if `encoding` scheme is not supported or not present."
9. `libp2p/multihash.nim:500-505` — "On success decoded MultiHash will be stored into `mhash` and **number of bytes consumed will be returned**. On error `-1` will be returned." (stale — see C1).
10. `libp2p/muxers/mplex/coder.nim:26-27` — `# https://github.com/libp2p/specs/tree/master/mplex#writing-to-a-stream` + `const MaxMsgSize* = 1 shl 20`; `libp2p/multistream.nim:290-292` — "#TODO this doens't seem to follow spec, each protocol should be length prefixed."
11. `libp2p/protocols/kademlia/types.nim:18-21` — "MaxBucketsLimit = IdLength * 8 — a bucket per shared prefix bit; deeper prefixes than the key is long cannot exist" (→ `IdLength` = 32 ⇒ 256 buckets max).

Encoding-law ground truth already exists as **table-driven test vectors**: `tests/libp2p/test_varint.nim:9-100` (PB/LP edge values with expected byte strings and octet counts), `tests/libp2p/multiformat/test_multihash.nim:10-60` (Rust `RustTestVectors`), `tests/libp2p/multiformat/test_multibase.nim:10-68` (Go `GoTestVectors`), `tests/libp2p/kademlia/test_encoding.nim`, `tests/libp2p/muxers/test_yamux_header.nim:313`.

---

## 3. TEST INFRASTRUCTURE

- **Framework:** `unittest2` (status-im fork) — `tests/tests.nimble:9` requires `unittest2 >= 0.2.5`; wrapped by `tests/tools/unittest.nim` (260 lines) which re-exports `unittest2 except suite` and adds `suite`, `asyncTest` (with per-test timeouts, `unittest.nim:75-90`), `asyncSetup`/`asyncTeardown`, `expectMsg`/`expectMsgContains` (`unittest.nim:98-159`), `checkUntilTimeout` (`:226-248`), `finalCheckTrackers` (`:250-260`).
- **Discovery:** `tests/imports.nim:25-77` is a compile-time macro that walks the tree and imports every `test_*.nim` (deterministically sorted, `:66-70`); `tests/test_all.nim:16-18` drives `libp2p/`, `interop/`, `tools/`.
- **Runners:** `Makefile:87-112` (`make test`, `make test <path>` → `-d:path=`, `make test_multiformat_exts`), `Makefile:114-118` (`test_integration`), `Makefile:122-129` (`bench_dial`).
- **No property-based testing, no fuzzing.** Grep for `fuzz|property|quickCheck|rapidCheck|hypothesis` across `.nim/.yml/.md` matched only `tests/libp2p/test_peer_info.nim` (the word "property" in prose). No `tests/fuzz/`, no libFuzzer/AFL harness, no `nimble` fuzz task.
- **Invariant-encoding tests:** round-trip vectors in `test_varint.nim` (440 lines), `test_multihash.nim` (158), `test_multibase.nim` (292), `test_multiaddress.nim` (663), `test_cid.nim` (109), `test_peer_id.nim` (290); frame-level codecs in `tests/libp2p/muxers/test_yamux_header.nim` (313) and `test_mplex.nim` (1317); state-machine/half-close behaviour in `tests/libp2p/stream/test_bufferstream.nim` (389), `test_connection.nim` (50), `test_bridgestream.nim` (61).
- **Coverage:** `.github/workflows/coverage.yml`; `libp2p_testing_slow` doubles timeouts (`docs/compile_time_flags.md`).

---

## 4. SMALLEST PURE MODULES SUITABLE FOR FORMAL VERIFICATION

Purity column: "pure" = no I/O, no globals/mutable singletons, `{.push raises: [].}` or explicit `raises: []`, deterministic.

| # | path | LOC | key exports | purity assessment |
|---|---|---|---|---|
| 1 | `libp2p/utils/bytesview.nim` | 22 | `BytesView.init/len/consume/toOpenArray/data` | **Zero imports.** Pure. Ideal size for a first proposition (and it contains C2). |
| 2 | `libp2p/utils/offsettedseq.nim` | 62 | `OffsettedSeq.add/[]/items/mitems/high/low/flushIf/all/any/count` | Pure (`sequtils` only). Mutable ref-free object; `[]` is index-relative. |
| 3 | `libp2p/utils/collections.nim` | 62 | `capLen/exclIfIt/filterIt/removeFirstIfIt/toChunks/take` | Pure (`std/sets`). `toChunks`/`take` have crisp length laws. |
| 4 | `libp2p/utils/opt.nim` | 83 | `getOpt/toOpt/noneWhenEmpty/ifValue` | Pure (macros+tables+results). Template-heavy → hard to extract; use `getOpt`/`noneWhenEmpty` only. |
| 5 | `libp2p/utils/zeroqueue.nim` | 67 | `ZeroQueue.push/consumeTo/popChunkSeq/len/isEmpty/clear` | Pure (`std/deques`). Invariant: `len == Σ chunk lengths`; `consumeFirst` asserts `0 < count ≤ first.len()`. |
| 6 | `libp2p/utils/iptree.nim` | 164 | `IpTree.insertIp/removeIp/insertIps/removeIps/ipsLen/ipScore/ipsMaxScore` | **Pure** (`std/net` only, every proc `{.raises: [].}`). Best "documented invariant" target (counters ≥ 0, score ∈ [0,1], pruning rule). |
| 7 | `libp2p/utils/rfc3339.nim` | 96 | `parseRfc3339DateTime` | Pure (`std/times`), `{.push raises: [].}`. Deterministic parse law; leap-second branch at `:90-94`. |
| 8 | `libp2p/utils/conversion.nim` | 35 | `safeConvert/ipv4ToString/ipv6ToString` | Pure (`std/net`); `ipv4ToString` raises `ValueError` unless `len == 4`. |
| 9 | `libp2p/varint.nim` | 315 | `putUVarint/getUVarint/putSVarint/getSVarint/putVarint/getVarint/encodeVarint/vsizeof/toUleb/fromUleb` | **Pure** (`{.push raises: [].}`, `stew/leb128` + `results`). Best *encoding-law* target; the 63-bit vs 64-bit split (`:138-143`, `:171-173`) and the `Overlong` canonicality check (`:142-143`) are the propositions. |
| 10 | `libp2p/vbuffer.nim` | 184 | `VBuffer.writeVarint/writePBVarint/writeLPVarint/writeSeq/writeArray/readVarint/readSeq/readArray/peek*` | Pure (varint+strutils). Offset-based buffer semantics; has C5. |
| 11 | `libp2p/multicodec.nim` | 119 | `MultiCodec.codec/multiCodec/$/==/hash`, `write` | Pure; tables built at `{.compileTime.}` (`:35-58`) ⇒ uniqueness/totality are statically decidable. |
| 12 | `libp2p/multibase.nim` | 547 | `MultiBase.encode/decode/encodedLength/decodedLength` | Pure but depends on `stew/base32,base58,base64`. Contains C3 (base16 stubs). |
| 13 | `libp2p/multihash.nim` | 648 | `MultiHash.digest/init/decode/validate/encode/base58/hex` | Pure-ish: `nimcrypto` digests are deterministic, no I/O, `{.push raises: [].}`. Contains C1, C7. |
| 14 | `libp2p/cid.nim` | 282 | `Cid.init/decode/validate/mhash/contentType/version/base58/hex/repr` | Pure (tables+hashes+stew/base58). CIDv0/v1 structural laws (`:85-88`, `:213-236`). |
| 15 | `libp2p/peerid.nim` | 306 | `PeerId.init/validate/match/cmp/toCid/toCidString/hasPublicKey/extractPublicKey` | Pure except `PeerId.random` (needs `Rng`, `:246-258`) — exclude that one. |
| 16 | `libp2p/protocols/kademlia/types.nim:159-225` | ~67 | `XorDistance`, `xorDistance` (4 overloads), `cmp`, `<`, `<=`, `leadingZeros`, `countLeadingZeroBits` | **Pure, and mathematically the richest**: XOR-metric laws (symmetry, zero-distance, lexicographic consistency with `leadingZeros`). `defaultHasher` (`:164-167`) = sha256; `noOpHasher` (`:170-175`) makes it deterministic. |
| 17 | `libp2p/muxers/yamux/yamux.nim:53-96` | ~44 | `YamuxHeader` type, `encode` (private) | The **encode** side is pure (12-byte big-endian header); `readHeader` is I/O-bound. Flag check at `:69-71` (`flags notin 0'u16..15'u16`) is a crisp parse law. |
| 18 | `libp2p/muxers/mplex/coder.nim` | 81 | `MessageType`, `Msg`, `MaxMsgSize`, `writeMsg` | `writeMsg` is pure (buffer construction); `readMsg` is I/O. |

Not recommended: `libp2p/multiaddress.nim` (1401 lines, imports chronos/chronicles/protobuf_serialization), `libp2p/multistream.nim` (434, async), `libp2p/crypto/*` (boringssl/secp C deps), `libp2p/stream/*` (chronos async).

---

## 5. CONTRADICTION CANDIDATES (ranked)

**C1 — `libp2p/multihash.nim:588`: a *dormant type error* plus a three-way doc/API/caller mismatch.** *(verified experimentally)*
`decode` returns `MhResult[int]` (`:497-499`) and its docstring still says "On error `-1` will be returned" (`:505`); `init58` tests `MultiHash.decode(...) == -1` (`:588`). Nim's `Result` only defines `==` between two `Result`s (nim-results `results.nim:831`), so `Result[int,cstring] == -1` is a **type mismatch** — proven by injecting one call site into a `/tmp` copy: `Error: type mismatch / Expression: decode(MultiHash, decode(Base58, data), hash) == -1`. It survives in the real tree only because `init58` has a `typedesc[MultiHash]` first parameter (Nim semchecks generic bodies **only on instantiation**) and `MultiHash.init58` has **zero call sites** — a repo-wide scan showed it is the *only* such proc among 206 `typedesc`-generic procs in `libp2p/`.
*Proposition:* "∀ b: MultiHash.decode(b, mh) = ok(n) where n = bytes consumed, ∨ err(·)" **and** "the error branch of `init58` is well-typed and reachable".

**C2 — `libp2p/utils/bytesview.nim:18-19`: off-by-`b` in `toOpenArray`, locked in by the test.**
`v.data.toOpenArray(v.rpos + b, v.rpos + e - b)` yields a slice of length `e-2b+1`, but the Nim-idiomatic inclusive range `[b,e]` should give `e-b+1`. `tests/libp2p/utils/test_bytesview.nim:14` asserts the buggy result (`b.toOpenArray(1,3) == @[2,3]`, 2 bytes instead of 3) and `:19` repeats it after `consume(2)`. All current call sites use `b = 0` (`libp2p/protocols/secure/noise.nim:314,333`), so it is latent — but `BytesView` is used in the Noise handshake (`:390,424,439`).
*Proposition:* "∀ 0 ≤ b ≤ e: `len(v.toOpenArray(b,e)) = e-b+1` **and** `v.toOpenArray(b,e) = v.data[v.rpos+b .. v.rpos+e]`" — **FALSE** for b>0.

**C3 — `libp2p/multibase.nim:75-93` + `306-309`: base16 / base16upper are registered as supported codecs but are `discard` stubs.**
`b16d`, `b16e`, `b16ud`, `b16ue` are `discard` bodies ⇒ they return `MultiBaseStatus.Error` (the first enum member, `:19-25`). Yet the codecs are registered with `encl`/`decl` (`:306-309`), so `MultiBase.encodedLength("base16", n)` returns `2n+1` (`:395-407`) — a positive "supported" answer — while `MultiBase.encode("base16", …)` always fails. The test file has **every base16 vector and assertion commented out**: `tests/libp2p/multiformat/test_multibase.nim:12-21`, `:80-81`, `:102-103`, `:138-145`.
*Proposition:* "∀ c ∈ supported, ∀ x: `MultiBase.encode(c,x) = ok(s)` and `MultiBase.decode(s) = ok(x)`" — **FALSE** for base16/base16upper. Sharper: "∀ c,n: `encodedLength(c,n) ≥ 0 ⟹ c` is encodable" — **FALSE**.

**C4 — two mutually incompatible varint dialects inside the same wire formats.**
`libp2p/varint.nim:9-11` and `:171-173` define the libp2p dialect as ≤63 bits / ≤9 octets and *reject* values ≥ 2^63. But the stream length prefix uses the **protobuf** dialect: `libp2p/stream/lpstream.nim:253` (`PB.toBytes`) and `:217` (`PB.getUVarint`, with a 10-byte buffer at `:209`). Worse, **one mplex frame mixes both**: `libp2p/muxers/mplex/coder.nim:63` writes the header with `writePBVarint` (protobuf) while `:64` writes the payload length with `writeSeq` (libp2p, `vbuffer.nim:77`).
*Proposition:* "∀ frames: the length prefix is a canonical unsigned varint of ≤9 octets and < 2^63" — **FALSE** on the stream path; "the two framing paths are equivalent" — **FALSE** (PB accepts 2^63…2^64−1, LP rejects it).

**C5 — `libp2p/vbuffer.nim:63`: masking before the overflow check makes `LP.putUVarint`'s `Overflow` branch unreachable.**
`var v = value and cast[type(value)](0x7FFF_FFFF_FFFF_FFFF)` truncates the top bit *before* `LP.putUVarint` (`:65`) can test it (`varint.nim:172`). A 64-bit value ≥ 2^63 is therefore silently written as `value mod 2^63` (2^63 → 0) instead of failing.
*Proposition:* "∀ v: `writeLPVarint` either encodes `v` exactly or returns an error" — **FALSE** (silent truncation); "∀ v ≥ 2^63: `LP.putUVarint` = Overflow" — TRUE but unreachable through `VBuffer`.

**C6 — `libp2p/muxers/mplex/mplex.nim:151` + `lpchannel.nim:317-319`: channel role is taken from the message-type bit, not the channel-id parity, and the message naming is inverted w.r.t. the mplex spec.**
`initiator = bool(ord(msgType) and 1)`; the spec defines `MsgIn(0x1)` = "from initiator to receiver" and `MsgOut(0x2)` = "from receiver to initiator", but the code assigns **MsgOut to the channel creator** (`lpchannel.nim:317-319`). The two halves are self-consistent, but (a) a frame whose type bit disagrees with the channel-id parity is routed to the wrong table and **silently dropped** (`mplex.nim:163-166`, "Channel not found, skipping"), and (b) the on-wire convention is the *opposite* of the spec's naming. Additionally `mplex.nim:247` uses `m.inChannTimeout` for an **outgoing** stream while `:177` uses `m.outChannTimeout` for a **remote-created (incoming)** stream — the two timeouts appear swapped.
*Proposition:* "∀ frames f on an existing channel c: f is delivered to c (no silent drop)" — **FALSE**; and the spec-conformance proposition "the channel initiator sends `MsgIn`" — **FALSE** here.

**C7 — `libp2p/multihash.nim:437-452` vs `467-495`: the two `init` overloads disagree on identity-hash digests.**
MDigest overload: `elif hash.size != len(mdigest.data): err(ErrWrongDigestSize)` — for `identity` (size 0) any non-empty digest is rejected. Byte-array overload: `elif (hash.size != 0) and (hash.size != len(bdigest))` — `identity` accepts any length. Same input, two answers.
*Proposition:* "∀ h, b: `MultiHash.init(h, b).isOk ⟺ MultiHash.init(h, MDigest(b)).isOk`" — **FALSE**.

**C8 — `libp2p/utils/iptree.nim:153-156`: `ipsMaxScore` returns 1.0 for the empty set although the docstring defines it as a max over the given addresses.**
`if ips.len < 1: return 1.0`; the docstring says "Max IP similarity score across the given addresses", and the test *locks the special case in*: `tests/libp2p/utils/test_iptree.nim:45` `check tree.ipsMaxScore(@[]) == 1.0`. (The companion claim at `iptree.nim:119` — score ∈ [0.0, 1.0] — *is* true.)
*Proposition:* "∀ ips: `ipsMaxScore(t, ips) = max{ipScore(ip) | ip ∈ ips}`" — **FALSE** for `ips = []` (empty max is undefined; the code returns the *worst* value 1.0).

**C9 — `libp2p/muxers/yamux/yamux.nim:515-524` + `266-280`: the configured receive window is silently raised to 256 KiB, and the code's own comment describes a different rule.**
`recvWindow: if recvWindow > YamuxDefaultWindowSize: recvWindow else: YamuxDefaultWindowSize` and `open()` sends `delta = max(maxRecvWindow - 256K, 0)` (`:455-461`), so the *effective* window is `max(configured, 256 KiB)`; the comment at `:515-519` claims "no updateWindow will be sent until recvWindow is less than maxRecvWindow", whereas `updateRecvWindow` actually fires only at `inWindow ≤ maxRecvWindow div 2` (`:273-278`). For a configured window < 256 KiB the window is never replenished (masked because the effective window is 256 KiB) and the configured value is not honoured.
*Proposition:* "∀ c: `c.recvWindow ≤ c.maxRecvWindow`" — **FALSE** right after creation when `maxRecvWindow < 256 KiB`; "∀ c: the peer-visible send window equals the configured `maxRecvWindow`" — **FALSE**.

**C10 — `libp2p/stream/lpstream.nim:189-199`: `readLine` drops the matched separator prefix (state clobbered before use).**
In the `else` branch, `state = 0` executes *before* `line.add(sep[0 ..< state])`, so the partial-separator match is always added as the empty string (and `min(state, …)` is computed with the already-zeroed `state`). Input `"abc\rdef"` with `sep = "\r\n"` loses the `"\r"`. `readLine` has **zero call sites and zero tests** in the repo (the only `readLine` uses are the stdlib `File.readLine` in `examples/directchat.nim:109,121,145`); `sep[state]` would also be out of bounds for `sep = ""`.
*Proposition:* "∀ input s, sep: `readLine(s, sep)` = the prefix of `s` up to the first occurrence of `sep`" — **FALSE** whenever a partial separator match precedes the real one.

*Minor/secondary (worth mentioning, weaker):* `libp2p/multistream.nim:290-292` — self-declared spec violation ("this doens't seem to follow spec, each protocol should be length prefixed"); `libp2p/multihash.nim:507,519,524` — `dpos` is accumulated and never used; `libp2p/vbuffer.nim:178-184` — `$` formats the *whole* buffer while sizing the string from the *remaining* bytes; `libp2p/utils/offsettedseq.nim:58-62` — `low`/`high` are inverted for an empty sequence (`low = offset`, `high = offset-1`); `libp2p/peerstore.nim:200-207` — the "never downgraded" invariant is realised by `max` over the *enum ordinal*, so it silently depends on the declaration order of `AddressConfidence` (`peerstore.nim:69-82`); `libp2p/varint.nim:142-143` — the `Overlong` canonicality check is `vsizeof(parsed.val) != parsed.len`, i.e. canonicality is decided by re-encoding, which is only sound if `Leb128.len` matches the decoder exactly.

---

## 6. HARD ASSUMPTIONS NOTICED

1. **Toolchain**: Nim **2.2.4 or 2.2.10 only** (`libp2p.nimble:10`, `README.md:36`); Nimble ≥ 0.24 required for `--resolver:minver` (`docs/development.md:19`).
2. **Dependency resolution is min-version, not locked**: `Makefile:78-81` uses `--resolver:minver` without the lockfile ⇒ the code must work against the *lowest* allowed versions, so `nix/libp2p.lock` is not the semantic reference.
3. **No vendored dependencies** — everything is fetched at build time (`.gitignore:20,22,42,45`; `nimbledeps/` absent) ⇒ offline/hairpin builds of the whole package are impossible; only the pure subset (stew + nimcrypto + results) is realistically extractable.
4. **Memory manager is `refc`** (`config.nims:25-27`, with a TODO about orc) but ASan builds force `--mm:orc` (`Makefile:22-23`) ⇒ **`doAssert`-based invariants are configuration-dependent** and cannot be treated as enforcement.
5. **Assertions are the de-facto invariant mechanism** but `UnreachableCode`/`UnreachableElse` are compile errors (`config.nims:13-14`) ⇒ dead branches are compiler-eliminated, so "always-true branch" candidates must be looked for in *runtime* conditions, not in `if true`/`if false`.
6. **Async runtime**: chronos 4.2.2, single-threaded event loop, with `{.push raises: [].}` in nearly every module and explicit `raises:` annotations; `cancelAndWait`/`noCancel` semantics are load-bearing for correctness (`libp2p/stream/connection.nim:95-101` explicitly avoids `cancelAndWait` to prevent deadlock).
7. **Crypto stack**: nimcrypto (sha2/keccak/blake2/sha1) + nim-boringssl 0.0.14 (TLS) + lsquic 0.11.2 (QUIC) + secp256k1 0.6.0.3.2 ⇒ C-library build burden and platform-specific behaviour; the multiformat modules avoid all of them.
8. **Platform matrix**: x86_64/aarch64/armv7a linux, x86_64/aarch64 darwin, x86_64 windows (`flake.nix:17-20`) plus Android/iOS cbind targets; `nimRawSetjmp` is defined on Windows only (`config.nims:31-33`).
9. **Compile-time extension points** (`-d:libp2p_multihash_exts`, `libp2p_multibase_exts`, `libp2p_multicodec_exts`, `libp2p_multiaddress_exts`, `libp2p_contentids_exts`; `docs/compile_time_flags.md`) inject code at compile time ⇒ the "pure module" set is open-ended and the codec tables are not closed.
10. **Compile-time tables** (`multicodec_table.nim` 647 lines, `initLists` at `multicodec.nim:35-58`, `initMultiHashCodeTable` at `multihash.nim:348-363`, `initLists` at `multibase.nim:376-393`, `initCidCodeTable` at `cid.nim:67-82`) ⇒ name/code uniqueness and totality are *statically decidable* properties, ideal for compile-time (Lean) checks rather than runtime ones.
11. **Style/lint gates are errors** (`config.nims:5-19`, `--styleCheck:error` at `:21-24`, `nph` formatter at `Makefile:148`) ⇒ any patch must be nph-formatted and warning-clean.
12. **Semantic-versioning contract** (`README.md:83-86`): "Releases within the same MAJOR version are backwards compatible" ⇒ the public API surface of `libp2p/varint.nim`, `multibase.nim`, `multihash.nim`, `cid.nim`, `peerid.nim` is a compatibility promise — relevant if a proposition-driven fix would change observable behaviour (e.g. C3's base16, C4's varint dialect).

**Suggested next step for the parent task:** the highest-value formal targets are `libp2p/utils/bytesview.nim` (C2 — 22 lines, fully pure, falsifiable in one proposition), `libp2p/utils/iptree.nim` (C8 + the counter/score laws), `libp2p/varint.nim` (C4/C5 — encode/decode round-trip and canonicality), and `libp2p/protocols/kademlia/types.nim:159-225` (XOR-metric laws). C1 is the strongest *narrative* candidate because it is a proven latent compile error rather than a merely arguable mismatch.