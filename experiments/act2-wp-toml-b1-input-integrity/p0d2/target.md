# P0-D2 target identity — pinned environment of the 3-way contrast

Experiment: `act2-wp-toml-b1-input-integrity/p0d2` · Date: 2026-10-11
Question: does the D2 defect input produce a consumer-visible effect unreachable by the
defect-free contrast, in the real consumer's decode form?

## Consumer identity

| item | value |
|---|---|
| consumer repo | `status-im/nimbus-eth1` (Nimbus execution client) |
| consumer commit used for pin extraction | `0c0230857dd8dbd5961e092add7cdfcd4a04ba66` (2026-07-04, "build(deps): bump vendor/nim-toml-serialization (#4402)") |
| current master at observation | `97d1f982c67fcff9b7f18b74e075179d9d5a7df1` (2026-10-11) — pins the **same** submodule sha |
| `vendor/nim-toml-serialization` submodule | **`73529768ced17720f78fb5b57191e863f8d8a9c1`** (verified twice via GitHub contents API: at `0c0230857dd8` and at master `97d1f982`; upstream commit date 2026-07-02 20:39:36 +0700, "Rename Toml_v100_Flags to Toml_v110_Flags (#118)") |

## Sibling vendor pins (all at nimbus-eth1 `0c0230857dd8`, via GitHub contents API)

| vendor path | git sha | fetched from |
|---|---|---|
| `vendor/nim-confutils` | `671145b7e68fb9dcac08b62b890d44eb15c72859` | status-im/nim-confutils |
| `vendor/nim-stew` | `83eb1157963b7f49351dbdd858355fa990bbe23c` | status-im/nim-stew |
| `vendor/nim-serialization` | `4092500cea76154576539371709ae801afbd2a9d` | status-im/nim-serialization |
| `vendor/nim-faststreams` | `50889cd16ec8771106cdd0eeea460039e8571e06` | status-im/nim-faststreams |
| `vendor/nim-unittest2` | `92e1c13dcfb6d7e4ea6fb624fe9cc31e3dc76813` | status-im/nim-unittest2 (fetched; not imported by the harness) |
| `vendor/nim-results` | `df8113dda4c2d74d460a8fa98252b0b771bf1f27` | **arnetheduck**/nim-results (submodule URL; `status-im/nim-results` does not exist) |

Per-file sha256 of the load-bearing dependency files: `probes/deps.SHA256SUMS`
(checked by `replay.sh` with `sha256sum -c` on every replay).

Cross-check: `serialization/object_serialization.nim` (`049d26ae…`), `serialization.nim`
(`ee248aaa…`), `faststreams.nim` (`c3983ebf…`) are byte-identical to the versions recorded
for the parent slice (`../JUDGMENT.md` §1.2), and the pin's `toml_serialization/lexer.nim`
(`19d69eed…`) is byte-identical to the file recorded there for subject HEAD `4aa8e22` —
i.e. the defect code (`scanHexEscape`, lexer.nim:416-431, `res.add char(code)`) is the same
bytes whose behavior was already proven for D2.

## Subject repo handling (Zero-Footprint)

- Subject clone: `<workspace>/nim-toml-serialization`
  (HEAD `4aa8e2223649fc0837c490a4acfca7b8b1e756f9`; `git status --porcelain` = 0 entries
  before and after the experiment).
- The pin is materialized read-only: `git -C <subject> archive 73529768ced1… | tar -x -C
  /tmp/p0d2_env/deps/toml_serialization`. No worktree, no checkout, no mutation.
- Binaries and the whole dependency tree live under `/tmp/p0d2_env` only.

## Decode form reproduced (consumer-exact)

Chain (all cited from the pinned sources):
1. nimbus `execution_chain/conf.nim:11-30` imports `confutils`, `confutils/toml/defs`,
   `toml_serialization`; fields under test verbatim:
   `agentString* {.name: "agent-string".}: string` (conf.nim:287-290),
   `allowedOrigins* {.name: "allowed-origins".}: seq[string]` (conf.nim:489-493).
2. confutils `addConfigFile(sources, Toml, InputFile)` (`confutils.nim:1206-1211`) →
   `addConfigFileImpl` → `loadFile(Format, string path, typeof(sources.data[0]), {})`
   (`confutils.nim:1182-1193`) — **no flags passed**.
3. The decode target is the confutils-generated model type whose fields are named by the
   `name` pragma verbatim (`config_file.nim:257-258,279`) — identical mechanism in the
   consumer.
4. toml_serialization reader init unions `flags + flavorRuntimeFlags(Flavor)`
   (`reader.nim:57-66`); `flavorRuntimeFlags(Toml) = Toml_v110_Flags` which **includes
   `TomlHexEscape`** (`format.nim:28-36`) — callers cannot subtract it. `\xHH` → raw byte.

## Toolchain & execution environment

| item | value |
|---|---|
| Nim | 2.2.10 [Linux: amd64], compiled 2026-04-24, git hash `bfeb3146d1638b39f69007a4ae5a23e23ae4e5ef` (`<user-home>/.choosenim/toolchains/nim-2.2.10/bin/nim`) |
| build command | see `replay.sh` step 5 (`nim c --warnings:off --hints:off --mm:orc --skipUserCfg --skipParentCfg --skipProjCfg --nimcache:… --path:<6 pinned dep dirs> --out:bin/p0d2_probe probe.nim`, run from neutral cwd `/tmp/p0d2_env`) |
| `ulimit -s` | 8192 |
| determinism | two full cold replays (workspace deleted, deps re-fetched, binary re-built) produced byte-identical `raw/*.{out,err,exit}` **and** `raw/build.log` — sha256 lists compared with `diff`, zero differences; a third replay verified against `raw.SHA256SUMS` |
| replay | `bash replay.sh` (also re-verifies dep + input identity every run) |

## Scope boundary (what this pinning does and does not cover)

The harness reproduces the consumer's **decode form** and the two **consumer-visible
effect computations** under test (devp2p Hello clientId egress bytes; CORS `sameOrigin`
decision per `rpc/cors.nim:21-27,35-50`). It does not build or run the full
nimbus-eth1 node; fields outside `agent-string`/`allowed-origins`, and effect paths other
than the two above (all of which were traced fail-closed in the parent analysis), are out
of scope and untouched.
