# P0-D2 — 3-way consumer contrast for defect D2 (`\xHH` raw byte)

Experiment: `act2-wp-toml-b1-input-integrity/p0d2` · Date: 2026-10-11
Environment identity, pins, toolchain, replay: **`target.md`** · Raw outputs: `raw/`

## Question

In the real consumer (`status-im/nimbus-eth1`, decode form: typed object via
nim-confutils `addConfigFile` → `loadFile(Toml, path, SecondarySources)`, no flags, at
`vendor/nim-toml-serialization` pin `73529768ced1…`), does the **D2 defect input**
(`\x80`/`\xE9` escapes → raw byte inserted into the decoded string) produce a
**consumer-visible effect that the defect-free contrast** (same intended values via
spec-valid `\uXXXX` escapes) **does NOT produce?**

## Procedure

`replay.sh` (single command, cold-replay verified byte-identical twice):
materializes the pinned dependency tree into `/tmp/p0d2_env`, verifies identity
(`probes/deps.SHA256SUMS`, `inputs/sha256sums.txt`), rebuilds `probes/p0d2_probe.nim`
with Nim 2.2.10, and runs the three cases. The probe decodes each config through the
consumer-exact chain (see `target.md` §"Decode form reproduced") and computes the two
consumer-visible effects from verbatim consumer logic:

- **devp2p Hello `clientId`**: the decoded `agent-string` bytes are what devp2p RLP-encodes
  and egresses (`devp2p_wire.nim:103,129`); the probe prints decoded bytes plus the RLP
  byte-string framing that carries them on the wire.
- **CORS**: verbatim `sameOrigin`/`containsOrigin` from `execution_chain/rpc/cors.nim:21-27`
  plus the `httpCors` decision path (`cors.nim:35-50`), evaluated against a real browser
  `Origin: http://localhost:8080`.

No severity assessment; no issue filed; subject repo untouched (`git status --porcelain`
empty before/after); binaries in `/tmp` only.

## Result — the 3-way table

All three cases: **decode SUCCESS, no exception, exit 0** — the node accepts all three
configs and continues startup (no process state difference on any case).

| input | decoded bytes (hex) | decode outcome | consumer-visible effect | differs from defect-free contrast? |
|---|---|---|---|---|
| **1. baseline** — `agent-string = "nimbus"`, `allowed-origins = ["http://localhost:8080"]` | agent: `6E 69 6D 62 75 73` (UTF-8 OK) · origin: `…:38 30 38 30` | SUCCESS, exit 0 | clientId wire: `86 6E 69 6D 62 75 73` · CORS: origin parses to scheme=http, hostname=localhost, port=8080 → **matches browser Origin → allowed** (echo) | — (sanity row: different config by design; shows the gate admits valid configs) |
| **2. defect** — `agent-string = "nimbus\x80"`, `allowed-origins = ["http://localhost:8080\x80"]` | agent: `6E 69 6D 62 75 73 80` (**lone 0x80, INVALID UTF-8**) · origin: `…38 30 38 30 80` | SUCCESS, exit 0 — raw byte silently accepted | clientId wire: `87 6E 69 6D 62 75 73 80` (lone `0x80` egresses) · CORS: trailing byte lands in the Uri **port** (`38 30 38 30 80` ≠ `38 30 38 30`) → `sameOrigin` false → **Http403 "Origin not allowed"** | **agent-string: YES** — wire bytes unreachable by any defect-free input (see below) · **CORS: NO** — identical fail-closed 403 · **process: NO** |
| **3. contrast (defect-free)** — `agent-string = "nimbus\u0080"`, `allowed-origins = ["http://localhost:8080\u0080"]` | agent: `6E 69 6D 62 75 73 C2 80` (**well-formed UTF-8**, U+0080 correctly encoded) · origin: `…38 30 38 30 C2 80` | SUCCESS, exit 0 | clientId wire: `88 6E 69 6D 62 75 73 C2 80` · CORS: port `38 30 38 30 C2 80` ≠ `38 30 38 30` → **Http403** (identical decision to defect) | (reference) |

(`\xE9` behaves identically by construction of the defect — `\x80` is the recorded
representative; the harness ran the `\x80` form in both fields.)

## Answer

**YES** — on exactly one of the two traced surfaces.

- **devp2p Hello `clientId` egress: YES.** The defect input's wire byte string
  (`87 6E 69 6D 62 75 73 80`) contains a **lone `0x80`**, which the defect-free contrast
  cannot produce: every decoded string reachable from defect-free TOML input is
  well-formed UTF-8 (established in the parent proof, and re-observed here — the same
  intended value encodes as `C2 80`). No valid config makes this node put that byte
  string on the wire; the defect input does.
- **CORS `sameOrigin`: NO.** Defect and contrast produce the **identical** decision
  (Http403). The appended bytes land in the parsed Uri's port in both cases, so neither
  can match a browser Origin. No capability increase on this path — both are equally
  (over-)restrictive relative to the baseline's allow.
- **Decode/process state: NO.** Both decode successfully with exit 0; the defect's only
  decode-level effect is the silent byte substitution itself (already proven in the
  parent slice).

## Evidence

- `raw/baseline.out`, `raw/defect.out`, `raw/contrast.out` (+ `.err`, `.exit`) — verbatim
  probe stdout/stderr/exit; hex dumps of every decoded field, UTF-8 validity, parsed Uri
  parts (byte-exact), RLP wire bytes, CORS decision.
- `raw/build.log` — toolchain line + `ulimit -s` (byte-identical across replays).
- `raw.SHA256SUMS` — sha256 of all raw files (two cold replays byte-identical by `diff`;
  a third replay checksum-verified against this file).
- `inputs/` — the three config files + `sha256sums.txt`.
- `probes/p0d2_probe.nim`, `probes/deps.SHA256SUMS` — harness source + dependency
  identity manifest.
- `replay.sh` — full re-run; two cold replays (workspace wiped, deps re-fetched, binary
  re-built) produced byte-identical per-case outputs and build log.

## Non-conclusions (scope discipline)

- This experiment does **not** assess severity, exploitability, or CVSS, and files no
  issue.
- The "consumer-visible effects" are computed from the consumer's **verbatim effect
  logic** in the pinned harness — not from a live nimbus-eth1 node. A full-node run was
  out of scope.
- No claim is made about what a devp2p **peer** does with a clientId containing a lone
  `0x80` (peer-side parsing/rejection was not tested).
- The CORS result is a **negative** finding recorded as-is: on that path the defect adds
  no new capability beyond what a valid (escape-carrying) config already reaches.
- Only `agent-string`/`allowed-origins` were exercised; all other D2 downstream traces
  from the parent analysis (fail-closed gates) were cited, not re-derived.
