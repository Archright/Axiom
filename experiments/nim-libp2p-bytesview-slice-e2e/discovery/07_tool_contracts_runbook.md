I have all three contracts confirmed from source. Here is the deliverable.

---

# Tool contracts (file:line evidence)

## 1. `bin/derive_checker_closure` — the closure derivation authority

**What it is:** a compiled x86-64 ELF binary (not a shell shim, not a symlink). Sole source: `tools/ci/derive_checker_closure.nim`. `bin/*` is gitignored (`.gitignore:29`), so it is a local build artifact. Canonical build recipe (org gate + closure-watcher): `nim c --hints:off --skipParentCfg --skipProjCfg --skipUserCfg --noNimblePath --path:src -o:bin/derive_checker_closure tools/ci/derive_checker_closure.nim`. The org gate compiles the deriver **from the B tree** (`/tmp/btree`), never from H (`tmp/org-dotgithub/.github/workflows/admission-gate-v2.yml:262-270`).

**CLI contract** (`tools/ci/derive_checker_closure.nim:1330-1344` help text; parser `:1365-1409`):

| Flag | Accepted | Validation | Failure |
|---|---|---|---|
| `--ref <git-ref>` | any commit-ish — 40-hex SHA, branch name, `HEAD`, tag | `git rev-parse --verify --quiet <ref>^{commit>` (`:1428-1432`) | exit **2**, `ERROR: --ref 존재하지 않음 또는 커밋 아님` |
| `--tree <tree-oid>` | tree object (merge-tree candidate M) | `rev-parse <oid>^{tree}` (`:1418-1426`) | exit **2** |
| `--repo <dir>` | repo root; default cwd, walks up to `.git` (`:1346-1355`) | — | exit 2 if no `.git` |
| `--ref` + `--tree` together | — | mutually exclusive (`:1405-1407`) | exit **2** |

Exit codes: `0` = success, `1` = UNRESOLVED members (fail-closed, diagnostics on stderr, `:1444-1452`), `2` = usage/ref error. No `--help` option — unknown option prints usage and exits 2 (`:1382-1384`).
Empirically verified: `--ref HEAD` → 880 lines, exit 0, empty stderr; `--ref main` → 880 lines; `--ref deadbeef…` → exit 2; `--ref HEAD --tree HEAD^{tree}` → exit 2.

**What it computes over:** the Tier-C "checker tree" — the gateway *execution-code* closure — derived **only** from the ref's tree. Entry points: `.github/workflows/runner-pool-acceptance.yml` @ref (`run:` blocks, `:1221-1303`) and `ci/checker.mk` @ref (make targets/recipes/`$(shell …)`, `:658-782`), plus static seeds (`:56-66`): `ci/checker.mk`, `tools/ci/derive_checker_closure.nim`, `tools/ci/impact_closure_selector.nim`, `tools/ci/proof_reconcile_gate.nim`, `tests/gateway/all_gateway_runner.nim`, `nimble.lock`, `config.nims`, `config/effects.nims`, `src/gate/config.nims`. It recursively resolves the Nim import/from/include graph (`:554-593`), maps `nim c -o:<out> <src>.nim` products back to their sources (`:622-656`), eliminates generated/downloaded binaries, and **fail-closes** on anything not statically eliminable (`:788-818`, `:1034-1037`).

**Output:** stdout = the **full membership** as `<mode> <type> <sha>\t<path>` lines, byte-sorted (`:1316-1324`). stderr = UNRESOLVED diagnostics. **It does not write, edit, or patch any file.** The consumer of that output is the pin `config/trusted_writer_set.json` → `trustedCheckerTreeClosure` (path → `{mode,type,sha}` map); the deriver line format is exactly the JSON map's serialization — see `src/core/policy/rotation_closure_facts.nim:102-130` (`pinClosureLineSet` rebuilds `<mode> <type> <sha>\t<path>` from the JSON).

**CRITICAL — committed content only.** The tool never reads the working tree: `snapshotTree` uses `git ls-tree -r --full-tree <ref>` (`:477-492`), `fileContent` uses `git show <ref>:<path>` (`:468-475`); the header states it analyses H "오직 `git ls-tree <ref>` / `git show <ref>:<path>` 로만 … 워킹 트리를 읽지 않고" (`:4-5`). ⇒ **The modified `src/cli/axiom_engine.nim` must already be committed when the closure is derived**, otherwise the deriver sees the old blob sha and the pin is silently wrong.

## 2. `bin/axiom-gate commit`

**Source:** `src/gate/gateway.nim`; build line `:17` → `nim c -d:release -o:bin/axiom-gate src/gate/gateway.nim`. The checked-out `bin/axiom-gate` (mtime Oct 7 13:45) **predates** the last commit touching the source (`f878f61a`, Oct 7 14:25) → rebuild before running.

**CLI:** `axiom-gate commit --message "msg" [--skip-ci] [file1 file2 ...]` (`:10`, `parseCommitArgs` `:108-136`). `--message`/`-m` or the first positional is the message; the remaining positionals are the file list.

**Staging — the crux:**
- Named files → `git add <file>` one by one (`stageFiles` `:142-151`, called `:338-341`). **Untracked new files are staged only if named** (`git add -u` never adds untracked files).
- **`git add -u` runs unconditionally right after** (`:342`) → *every* dirty **tracked** file in the worktree is staged, named or not. Contract doc: `docs/guides/axiom_gate_commit_staging_contract.md:63, :71-79`.
- `hasStagedChanges()` (`:153-158`); if nothing is staged the commit becomes `--allow-empty` (`:446-447`).

**Gates: yes.** Phase 1 normalize (read-only manifest verify, `:171-176`) → Phase 2 stage → Phase 2a HEAD snapshot for CAS (`:346-348`) → Phase 2b toolchain-lock verify (`:350-355`) → Phase 2c `make test` perf budget (`:357-362`) → Phase 2d spec-drift check `nim c -r src/gate/runners/spec_binding_gate.nim` (`:364-369`) → Phase 2.5 seed `.git/COMMIT_EDITMSG` (`:371-376`) → Phase 3 pre-commit gate hook, spawned out-of-process (`:383-396`) → Phase 3.6 CAS lock, HEAD must not have moved (`:431-436`) → Phase 4 `git commit --no-verify -m <msg>` (`:438-450`).
- `--no-verify` suppresses pre-commit and commit-msg but **prepare-commit-msg still runs**, and it enforces "the staged index must be unchanged since the gates passed" via the State Ledger v4 recorded staging-tree SHA (`:713-759`). The index is untouched between Phase 3 and Phase 4, so it passes.
- If no gate binary is available → hard fail + bypass audit record (DEBT#286 remediation, `:410-428`), exit 1.

**Two sequential commits: yes.** It is a pure *stage → gate → commit-the-index* pipeline, so invoking it twice works. The only hard requirement is that the **working tree differs between the two invocations in exactly the intended way** — at invocation #1 the TWS and `data/architecture_debt.json` must **not** be dirty yet, otherwise `git add -u` sweeps them into the feature commit and the two-commit rotation shape is destroyed.

**Exit codes:** `runCommitCommand` returns 1 for missing message (`:322-325`), stage failure (`:339-341`), toolchain failure (`:352-354`), `make test` failure (`:359-361`), spec drift failure (`:366-368`), gate failure (`:392-396`), missing gate binary (`:428`), CAS lock failure (`:433-435`); otherwise git's own commit exit code (`:454-456`). Dispatch `quit(runCommitCommand(args[1..^1]))` at `:975-978`. On success it prints `{"exitCode":0,"stdout":…,"stderr":"","skipCi":bool,"version":"1.0.0"}` (`:461-467`).
(`[Arch-Review-Verified]` is only demanded when `gate_contract.nim` is modified — `:591-604`; not applicable here.)

## 3. `bin/debt_engine --regen-arch` / `--validate`

**Source:** `tools/debt_engine.nim`; dispatcher `:3437-3457`, `of "--regen-arch": cmdRegenArch()` at `:3450`.

**`--regen-arch`** (`cmdRegenArch` `:1910-1944`):
- Reads `data/architecture_debt.json` (`ArchDebtPath` `:96`); requires an `entries` array (`:1918-1919`) else exit 1.
- For each entry it takes `e["file"]` and **re-reads that file from the WORKING TREE** (`:1925-1927`) and recomputes `rawContentHash` = `computeRawContentHash` (`src/core/debt/debt_integrity.nim:28`) and `canonicalSyntaxHash` = `computeCanonicalSyntaxHash` (`src/core/debt/debt_integrity.nim:212`). Missing file → skipped silently (`:1925-1926`).
- No drift → "No drift detected"; drift → updates both fields and **rewrites the whole file** via `writeFile(path, archJson.pretty())` (`:1939-1941`) — i.e. it re-serializes the entire JSON (precedent diffs stayed small only because the file is already `pretty()`-normalized).
- **It does not need a commit** — it hashes on-disk content, not committed content. It reads neither the closure nor the TWS.
- `src/cli/axiom_engine.nim` **is** an entry (count 1, `rawContentHash sha256:7f931454…`, `canonicalSyntaxHash sha256:v2:nim-pnode-canonical-v2:cc58c216…`) → it will drift, so regen is mandatory. There is **no `--dry-run`** for regen (unlike `--prune`/`--sync-budget`).

**`--validate`** (`cmdValidate` `:1296…`): Part A calls `validateArchitectureDebt` (`:369-414`), which recomputes the hashes from the live file and compares against the stored ones → **it fails if regen has not been run** after modifying a `.nim` file. Then cross-file consistency (`:1326-1329`), registry/ledger/markdown sync (`:1346-1356`). ⇒ order is **regen → validate**.

---

# The resolved runbook sequence

Preconditions: a workstream branch (AGENTS.md §2.1 — the clone is currently on `main`, clean tree); fresh `bin/axiom-gate` (rebuild per `gateway.nim:17`), `bin/derive_checker_closure` and `bin/debt_engine` (`nim c -d:release -o:bin/debt_engine tools/debt_engine.nim`; Makefile:1188).

**Step 0 — write the feature files.** New `config/spec` overlay, new `docs/spec` contract, new unit test, and the modification to `src/cli/axiom_engine.nim`. **Do not touch `config/trusted_writer_set.json` or `data/architecture_debt.json` yet.**

**Step 1 — COMMIT #1 (feature).**
```
bin/axiom-gate commit --message "<feature msg>" \
  <new-config-overlay> <new-docs-contract> <new-unit-test> src/cli/axiom_engine.nim
```
- Precondition: the worktree contains **only** the feature changes; TWS + architecture_debt are clean.
- The three new files **must be named** (they are untracked; `git add -u` skips untracked). `src/cli/axiom_engine.nim` would be picked up by `git add -u` anyway.
- Output: commit **C1** (`git rev-parse HEAD`). Exit 0 + JSON banner.

**Step 2 — derive the closure from C1 (committed tree).**
```
bin/derive_checker_closure --ref "$(git rev-parse HEAD)" | LC_ALL=C sort > /tmp/derived-H.txt
```
- `--ref` = C1's SHA (or literally `HEAD`, identical here — both resolve through `rev-parse …^{commit}`).
- Precondition: **C1 exists and contains the modified `axiom_engine.nim`.** The deriver reads the committed tree only, so running this before Step 1 yields the *old* sha.
- Expected: exit 0, 880 lines, exactly one differing line — `src/cli/axiom_engine.nim` (membership unchanged; the new config/docs/test files are outside the closure — verified: the only `tests/` member is `tests/gateway/all_gateway_runner.nim`).

**Step 3 — edit the pin (one sha value).**
`config/trusted_writer_set.json` → `trustedCheckerTreeClosure` → `"src/cli/axiom_engine.nim"` at **:98-102**, with `"sha": "16a0167576afb3ed34f224c1ff95ad0c001b43b3"` at **:101**. Replace **only** that sha string with the sha from `/tmp/derived-H.txt`. Do not re-serialize the file — it carries full-line `//` JSONC comments; precedent: "Each old->new replaced exactly once in the JSONC (no re-serialization)" (`git show 1a18fbbf2`).

**Step 4 — debt regen (after C1, before C2).**
```
bin/debt_engine --regen-arch
bin/debt_engine --validate        # must exit 0
```
- Precondition: the `axiom_engine.nim` content on disk is final (regen hashes the working tree, so it is content-bound, not commit-bound).
- Must run **after Step 1** so that its output lands in commit #2 rather than being swept into C1 by `git add -u`; must run **before** `--validate`.
- Output: "Updated N entries in data/architecture_debt.json".

**Step 5 — optional local H2 preflight.**
```
nim c -r tools/ci/rotation_pin_anchor_check.nim -- \
  --derived-H /tmp/derived-H.txt \
  --pin-H config/trusted_writer_set.json \
  --pin-B <B-side checkout>/config/trusted_writer_set.json
```
Expect `H2 PASS code=OK`, exit 0 (`tools/ci/rotation_pin_anchor_check.nim:15-21, :184-205`). Note `--pin-B` defaults to the cwd's TWS (`:180-181`), which would compare H against H — pass the B-side file explicitly.

**Step 6 — COMMIT #2 (rotation).**
```
bin/axiom-gate commit --message \
  "rotation: re-anchor trustedCheckerTreeClosure for <subject> (<C1 short sha>)" \
  config/trusted_writer_set.json data/architecture_debt.json
```
- Precondition: the only dirty tracked files are the TWS and `data/architecture_debt.json` (the worktree is otherwise clean, so `git add -u` stages exactly these two).
- Output: commit **C2**, whose parent is C1. This mirrors the PR #938 precedent: `00ae16771` (rotation) ← `0ece5a53b` (feature), touching exactly `config/trusted_writer_set.json` + `data/architecture_debt.json`.

**Step 7 — verify PR-head equality (what the gate will check).**
```
bin/derive_checker_closure --ref "$(git rev-parse HEAD)" | LC_ALL=C sort > /tmp/derived-H2.txt
diff /tmp/derived-H.txt /tmp/derived-H2.txt   # must be empty
git show HEAD:config/trusted_writer_set.json   # must parse to the same 880-member map
```
This is valid because **`config/trusted_writer_set.json` and `data/architecture_debt.json` are not closure members** (verified empirically against the 880-member derived set). The gate does exactly this: `git show "$HEAD_SHA":config/trusted_writer_set.json` and compares line-set-wise at `src/cli/merge_cli.nim:1268` (Pass 2.75, the single policy deny site) via `src/core/policy/rotation_closure_facts.nim:141-163`.

---

## Failure modes the runbook must state

1. **Derive before committing** → the deriver sees the old blob → pin stays wrong → Pass 2.75 denies with `ROT_NEW_PIN` (`rotation_closure_facts.nim:161-163`).
2. **Regen / TWS edit before commit #1** → `git add -u` (`gateway.nim:342`) sweeps them into the feature commit → one commit, rotation shape destroyed.
3. **`--regen-arch` rewrites the whole file** via `pretty()` (`debt_engine.nim:1940`) — a large diff means the committed file wasn't `pretty()`-normalized; fix formatting, don't re-derive.
4. **`axiom-gate commit` runs `make test` + spec drift + the whole pre-commit suite** — expect minutes per commit.
5. **Do not change `trustedAdmissionWorkflowSha`** while re-anchoring: a closure-only re-anchor is explicitly "not a pin change" and passes the epoch transaction gate with a loud NOTE, no epoch catalog/manifest pairing needed (`tools/ci/epoch_transaction_gate.nim:663-679`); touching the pin value would trigger the G2a pairing obligation.
6. **Stale local binaries**: `bin/axiom-gate` on disk predates its source's last commit — rebuild all three before the run.

**Also note (out of the three tools' scope, but it will bite):** new files under `config/`, `docs/`, `tests/` are `PRODUCT` under `config/repository_surface.json` and normally need the 2-phase "register-ahead then body" convention (see the v83/v84 notes in `config/repository_surface.json:160` area); `config/trusted_writer_set.json` is a CONTROLLED/FROZEN authority surface (`:160`).