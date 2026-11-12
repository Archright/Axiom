# PR #938 / #911 / #912 / #947 — exact commit sequence and rotation ordering

## 1. PR #938 — "feat(engine): generic sidecar adapter…"

Merged 2026-10-19T07:30:22Z, merge commit `00bb8334c312736922a3a41fb4033b6da755eb1d`, branch `followup/sidecar-adoption-binding`, base `main` (parent `c795307a0`).

**It is three commits, not two** — contract → feature → rotation:

| # | sha | subject | files |
|---|---|---|---|
| 1 | `88e82fc24da87e73619bfc3e21190d26cd37fa02` | `docs(contract): SPEC-B36-SIDECAR — 해시 바운드 채택 사이드카 계약 채택` | `A config/spec/nim_stew_base36_sidecar.json` (+55)<br>`A docs/spec/nim_stew_base36_sidecar_contract.md` (+88) |
| 2 | `0ece5a53b815d373a020aee28d3ff8013bde1494` | `feat(engine): generic sidecar adapter — closed-grammar external proposition with hash-bound adoption; original-body carry + plain replay` | **`M src/cli/axiom_engine.nim`** (+676/−4)<br>`A tests/unit/test_sidecar_binding.nim` (+606) |
| 3 | `00ae167712ee1b854c222474b4ee59ccdfc8c68e` | `rotation: re-anchor trustedCheckerTreeClosure for the sidecar adapter (9c8919eb8)` | **`M config/trusted_writer_set.json`** (+1/−1)<br>**`M data/architecture_debt.json`** (+2/−2) |

- `src/cli/axiom_engine.nim` → **commit 2** (the feature commit)
- `config/trusted_writer_set.json` → **commit 3** (the rotation commit)
- `data/architecture_debt.json` → **commit 3** (the rotation commit)

Rotation commit message, verbatim:

```
rotation: re-anchor trustedCheckerTreeClosure for the sidecar adapter (9c8919eb8)

src/cli/axiom_engine.nim closure member re-anchored for the SPEC-B36-SIDECAR
engine slice; architecture_debt.json canonical/raw hashes regenerated
(bin/debt_engine --regen-arch, --validate all-pass). pin==derived verified:
derive_checker_closure on the branch tree == trustedCheckerTreeClosure
(876 members, one sha change).
```

Note the subject carries the **new blob sha** (`9c8919eb8`) and the body says "on the **branch tree**" — i.e. the derivation ran against a committed branch state, not the working tree.

## 2. The exact TWS diff shape (rotation commit of #938)

`config/trusted_writer_set.json`, JSON path `trustedCheckerTreeClosure` → key `src/cli/axiom_engine.nim`, at line ~97:

```diff
@@ -97,7 +97,7 @@
   },
   "src/cli/axiom_engine.nim": {
     "mode": "100644",
-    "sha": "2b2b0d6962c892fe8cc240abcb13f110dec38567",
+    "sha": "9c8919eb8a6141322b8c9fa62f50743a1fd1cebd",
     "type": "blob"
   },
```

One line changed, one member, 40-hex, `type: blob`. **It is a git blob sha, not a content/tree closure hash** — verified:

- `git rev-parse 0ece5a53:src/cli/axiom_engine.nim` → `9c8919eb8a6141322b8c9fa62f50743a1fd1cebd` (the NEW pin)
- `git rev-parse 88e82fc2:src/cli/axiom_engine.nim` → `2b2b0d6962c892fe8cc240abcb13f110dec38567` (the OLD pin)
- `git cat-file -t` on both → `blob`
- ADR-0025 §6 states the same contract: `trustedCheckerTreeClosure` is `{path: {mode,type,sha}}`, "**`git ls-tree` 산출; contents API `.sha` 금지**"

`data/architecture_debt.json` (rotation commit), the `src/cli/axiom_engine.nim` entry only:

```diff
       "canonicalHashAlgorithm": "nim-pnode-canonical-v2",
-      "canonicalSyntaxHash": "sha256:v2:nim-pnode-canonical-v2:c89f1761aa031ec4d515c27ec7df442c9bd4183e03e8730cfc7f1d07256635c5",
+      "canonicalSyntaxHash": "sha256:v2:nim-pnode-canonical-v2:163ffc4e4993e359ab2a9c8d3d809203a04207cdad47f7a68b39358dc0585219",
       "count": 1,
       "file": "src/cli/axiom_engine.nim",
       "firstSeen": "2026-06-18T13:27:57Z",
       "lastSeen": "2026-08-13T00:00:00Z",
-      "rawContentHash": "sha256:75acab0356b806c1c8c7a656f64c67f6cf3bfc055100d58fff36c352b986fe02"
+      "rawContentHash": "sha256:8b5b7ee819574f3323592238608900113aef3534e864094a9ea75710ff193a1b"
```

`sha256:`-prefixed, produced by `debt_engine --regen-arch` — a *different* hash family from the git blob sha in TWS.

## 3. PR #911 (toml d2-agent) and PR #912 (NORMAL pair)

**#911** — merged 2026-10-17T16:02:02Z, merge `d4b2a0e921a24cd71b6e8f883e0d978a480189cc`, branch `followup/d2-agent-rotation`. **2 commits**:

1. `2353f68fe2bbb52bd0a7ed0182d9ce905fd2b874` — `feat(engine): p0d2g toml d2-agent binding — carrier synthesis, original-code replay, presence-optional overlay`
   - `M src/cli/axiom_engine.nim` (+663), `M src/verification/counterexample_replay.nim` (+77/−5), `M src/verification/obligation/canonical_verification.nim` (+9)
2. `3e16eb167c65e0b4613608717d54887b4d24674c` — **the TWS re-anchor commit**:
   `fix(trust): 회전 — 클로저 멤버 3경로 재앵커(deriver 유도 sha) + architecture_debt 재생 (p0d2g 엔진 확정, 2353f68fe)`
   - `M config/trusted_writer_set.json` (3 members: `axiom_engine.nim`, `counterexample_replay.nim`, `canonical_verification.nim`, each +1/−1)
   - `M data/architecture_debt.json` (2 entries)

The 3 re-anchored members are exactly the 3 closure members the feature commit touched, and the message names the feature sha `2353f68fe` — same "rotation commit references the feature commit" shape as #938.

**#912** — merged 2026-10-18T01:56:25Z, merge `8279713eb35a03a2dc8f3bf26cfc0fddad92f819`, branch `followup/d2-agent-records`. **1 commit** `9775389e2dcaa0d163ee253b0a606ba11e0113f6` — `docs(experiments): p0d2g agent vertical slice — overlay, contract, records, 4-axis acceptance harness, unit tests (NORMAL pair of #911)`. 29 files, **all ADDED**: `config/spec/toml_d2_agent_spec.json`, `docs/spec/toml_d2_agent_binding_contract.md`, 23 files under `experiments/act2-wp-toml-b1-input-integrity/p0d2g/`, `tests/unit/test_toml_d2_agent_binding.nim`. **No TWS, no architecture_debt** → NORMAL class (no closure member touched). #911/#912 are the same d2 work split into a ROTATION-class PR and a NORMAL-class PR.

## 4. PR #947 (docs-only evidence PR)

Merged 2026-10-19T10:05:13Z, merge `8d9281b8e56a7363f1229795f8ac9f025a3dcbcb`, branch `followup/sidecar-e2e-records`. **1 commit** `7f125bc0a413e40a6901e4e8c40f87ae77dcb051` — `docs(experiments): sidecar-adoption e2e — frozen records, blind discovery raw, adoption evolution, verdict table`. 13 files, **all under `experiments/sidecar-adoption-e2e/`** — `.gitignore`, `ACCEPTANCE.md`, `FREEZE.md`, `INTEGRITY.md`, `discovery/agentA1_raw.md`, `discovery/agentA2_raw.md`, and `runs/` (d1/d2 stderr+stdout, pre/post subject-tree sha256 manifests, unsupported_tests.log). **No `docs/evidence/` files** — those went to `experiments/`. It is the evidence record for the #938 slice: `FREEZE.md` pins HEAD = `00bb8334c…` (the #938 merge); `ACCEPTANCE.md` records the landing of #938 and #943 (`a292f0596`, which re-adopted the blind agent's inferred law into `config/spec/nim_stew_base36_sidecar.json` + the contract + `tests/unit/test_sidecar_binding.nim`).

## 5. The operation order — settled by evidence, not inference

**a) The tooling makes rotation-before-feature impossible.** `tools/ci/derive_checker_closure.nim` header: "**워킹 트리를 읽지 않고 오직 `git ls-tree <ref>` / `git show <ref>:<path>` 로만 H를 분석한다**" — it takes `--ref <git-ref>` or `--tree <git-tree-oid>` and never reads the working tree. Since the TWS value *is* the git blob sha of the post-change file, the new pin can only be produced from a **committed tree** containing the feature change. A working-tree derivation is not possible by construction.

**b) Empirically reproduced with the repo's own binary** (read-only; the tool contains no write calls):

| ref | derived `src/cli/axiom_engine.nim` | TWS pin | derived == pin? |
|---|---|---|---|
| `88e82fc2` (pre-feature) | `2b2b0d69…` | `2b2b0d69…` | ✅ 876 == 876 |
| `0ece5a53` (feature) | `9c8919eb8…` | `2b2b0d69…` (stale) | ❌ **one sha apart** |
| `00ae1677` (rotation) | `9c8919eb8…` | `9c8919eb8…` | ✅ 876 == 876 |

Same shape for #911: derived@`2353f68f` differs from the pin in exactly the 3 members the feature touched; derived@`3e16eb16` == pin exactly. This also shows the intermediate feature commit is *deliberately not landable alone* (derived ≠ pin = `ROT_NEW_PIN`) — the rotation commit is what makes the branch head admissible.

**c) The sanctioned procedure as documented.** ADR-0025 §7 "rotation lifecycle — 신뢰 교체 절차 하나", step 1: "**in-PR closure pin 원자 갱신** — ROTATION PR이 `old pin == derived(B)`(genesis 1회 허용) ∧ `new pin == derived(H)`를 기계 판정으로 만족". The prereg verification plans state the operational recipe verbatim (e.g. `docs/evidence/rotation_allowlist_guard_confirmation_prereg_2026-10-19.md` §3, identically `rotation_allowlist_replay_evidence_prereg_2026-10-19.md` §3):

```
1. agent_preflight PASS
2. bin/nimtry src/ exit 0
3. 커밋 후 `derive_checker_closure --ref HEAD` 출력의 라인 집합 == config/trusted_writer_set.json `trustedCheckerTreeClosure`(멤버십 불변·blob 등식)
4. tools/ci/verify_trusted_writer_set.sh PASS
5. bin/debt_engine --validate PASS
```

and §2 of the same documents: "본 회전은 **멤버십 불변** 조건의 내용 재앵커다: ④ `line-set(pin@H) == set(derived H)`는 유도값(`tools/ci/derive_checker_closure --ref H`) 기준으로만 갱신한다 — **추측 해시 금지**"; `data/architecture_debt.json`: "`debt_engine --regen-arch`로 변경 멤버 해시만 갱신".

Step 3's "**커밋 후**" (after the commit) is the decisive phrase: the sanctioned order is *commit first, then derive, then commit the pin rotation*.

**d) Where the runbook is / isn't.** `docs/agents/rules_workflow.md` contains **no** rotation guidance (grep for rotat/회전/re-anchor/재앵커/trusted_writer_set → zero hits). The runbook lives in ADR-0025 §6/§7 + `docs/evidence/rotation_allowlist_*_prereg_*.md`. Also note #938 needed **no** prereg: its rotation touched only the pin path itself and `data/architecture_debt.json`, which is already in `RotationAllowlistExtra` (`src/cli/merge_cli.nim:267`) — no new companion path, so no enumeration extension was required.

**e) Precedent scan (244 rotation-class commits since 2026-09-20):** every commit touching `config/trusted_writer_set.json` **follows** the commit that changed the closure member content — no counter-example of rotation-before-feature. Examples: `00ae16771`←`0ece5a53b`; `3e16eb167`←`2353f68fe`; `bb26ebb4a`←`52abab1bb`; `f1cec75d2`←`60717df13`; `1a18fbbf2`←`5b6754613`; `c84016cf1`←`c31bc944f`; `3a0dc3ad0`←`af579664c`; `f3c0d065b`←`d3652f91d`; `18ef823a0`←`bdd118843`.

**Inferred canonical order for #938 (the only one the tooling permits):**

1. commit `88e82fc2` — contract + sidecar spec (docs/config, non-closure)
2. commit `0ece5a53` — feature: `src/cli/axiom_engine.nim` + `tests/unit/test_sidecar_binding.nim` (creates the ROTATION-class delta; tree is now pin-inconsistent by design)
3. derive `tools/ci/derive_checker_closure --ref <feature commit / branch head>` → 876-member line set carrying the new blob sha
4. edit `config/trusted_writer_set.json` (one member sha) → `bin/debt_engine --regen-arch` → `data/architecture_debt.json` (2 hashes)
5. commit `00ae1677` — rotation (TWS + arch debt only)
6. merge `00bb8334c`

**Answer to the runbook ambiguity: the feature commit must exist before the rotation commit, and the TWS re-anchor necessarily lands in the rotation commit that follows it — the pin value is the git blob sha of the *committed* post-feature file, so it cannot be derived from an uncommitted working tree.**