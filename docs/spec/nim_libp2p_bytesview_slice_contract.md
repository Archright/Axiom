# nim-libp2p BytesView.toOpenArray slice-length binding — Product Contract

> **Status**: Committed product contract — the external-subject spec overlay slice (`followup/libp2p-bytesview-slice`)
> **Created**: 2026-10-22 (v1.0.0) — **Re-adopted**: 2026-11-14 (v1.1.0 — law conformance over the FIXED tree)
> **AGENTS.md reference**: §0.12 (product contract precedes), §0.9 (theater prohibition), §0.3 (trust boundary), §0.2a (legislator LLM-only — not engaged here: the spec content is the investigation agent chain's adopted work product, not a legislator invariant), §4 (GUARDIAN)
> **Related**: [toml_d2_agent_binding_contract.md](./toml_d2_agent_binding_contract.md) (overlay / constructed-carrier / adoption-provenance precedent), [nim_stew_base36_sidecar_contract.md](./nim_stew_base36_sidecar_contract.md) (adoption + non-claims precedent), [authority_contract.md](./authority_contract.md), [obligation_semantics.md](./obligation_semantics.md), [counterexample_replay_adapter.md](./counterexample_replay_adapter.md)
> **Spec registry**: `SPEC-LIBP2P-BV-SLICE` — binding overlay `config/spec/nim_libp2p_bytesview_slice.json` (soExplicit), rule `external:libp2p/bytesview/slice-length-law` v`1.1.0`

---

## 1. Proposition — the slice-length law

**Subject**: `libp2p/utils/bytesview.nim` of an **unmodified** READ-ONLY clone of Archright/nim-libp2p (fork of status-im/nim-libp2p; local clone `<workspace>/nim-libp2p`) @ `d9e8769c3c989fc7dc78182b1358f60c85f14238` (branch `fix/bytesview-toopenarray-slice-bounds` — the one-line fix `v.rpos + e - b` → `v.rpos + e`). Subject pin: module blob sha256 `e5c73a4fc4b4f390a74a95078809639f4773510e029673c3fb7884d53f584c85` at the pin (measured from the fixed commit's blob; the git object ID `d9e8769c…:libp2p/utils/bytesview.nim` is a SHA-1 over the repository's object graph — a different hash kind, recorded separately in the run evidence). The v1.0.0 subject pin was status-im/nim-libp2p @ `a130a7f32219909bdcda14b7f1e64d0804fc832c` (origin `iftech/nim-libp2p`), blob sha256 `b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee` — the PRE-FIX bytes, kept as history (§8). Governed symbol: `toOpenArray` — a **template** (`:18-19`), not a materializable `func`. The subject tree is READ-ONLY at all times (Zero-Footprint Integrity): `git -C <subject> status --porcelain` must remain empty at every stage, and the replay harness is compiled OUT OF TREE.

**The math.** The FIXED template body is

```nim
libp2p/utils/bytesview.nim:18-19 (fix/bytesview-toopenarray-slice-bounds)
  template toOpenArray*(v: BytesView, b, e: int): openArray[byte] =
    v.data.toOpenArray(v.rpos + b, v.rpos + e)
```

`data` is a `seq[byte]` and the system `toOpenArray(x, first, last)` is INCLUSIVE. The template therefore materializes the inclusive interval `[rpos + b, rpos + e]`, whose length is

```
L_actual(b, e) = (rpos + e) - (rpos + b) + 1 = e - b + 1
L_incl(b, e)   = e - b + 1          # the inclusive view-relative law (Nim system semantics)
```

- `L_actual == L_incl` for **every** `b` — the FIXED template conforms to the adopted law exactly.
- `b = 0` → `L_actual = e + 1` — **byte-identical to the pre-fix arithmetic** (the fix changes only the `b > 0` paths), so the production call sites (noise.nim, all `b = 0`) are unaffected.
- **Historical (v1.0.0, PRE-FIX bytes)**: the body `v.data.toOpenArray(v.rpos + b, v.rpos + e - b)` materialized `[rpos + b, rpos + e - b]`, length `e - 2b + 1` — exactly `b` elements short of the law; pinned at `b = 1` the actual `e - 1` against the law `e` was violated for **every** `e` in the domain. That disproof is the preserved historical demonstration (§8); `b = 1, e = 3` → `2` observed where the law demanded `3`.

**Adopted claim (S1, v1.1.0 — law conformance)** — stated as **DATA** in the overlay's `canonicalSpecIR` (the engine hardcodes no law content; only the carrier/law NAMES are binding identities):

```
D                   = { e | (e ≥ 1) ∧ (e ≤ 5) }         # clauses 1-2
bvSliceLenLaw1(e)   == e          # clause 3 — the inclusive law at b = 1
bvSliceLenActual(e) == e          # clause 4 — the FIXED template's actual length at b = 1
bvSliceLenLaw0(e)   == (e + 1)    # clause 5 — the inclusive law at b = 0
bvSliceLenControl(e) == (e + 1)   # clause 6 — the FIXED template's actual length at b = 0

S1:      ∀ e ∈ D:  bvSliceLenActual(e)  == bvSliceLenLaw1(e)   # L_actual(1, e) == e — NO counterexample
control: ∀ e ∈ D:  bvSliceLenControl(e) == bvSliceLenLaw0(e)   # L_actual(0, e) == e + 1
```

The clause grammar is **CLOSED**: a definition body is `<var>`, `<var> + <INT>` or `<var> - <INT>` (optionally wrapped in one parenthesis pair), and a clause count other than the six above is rejected. An overlay that states a model or a law in any other shape states a DIFFERENT claim and is rejected fail-closed by the loader — the law is never approximated, and it is never read out of engine prose.

**specOrigin = soExplicit justification**: the claim's content is agent-authored (§8), so it has NO in-band authority in the subject tree or from any upstream document; the only origin that authorizes verification of an out-of-tree claim over a READ-ONLY subject is an explicit Axiom-owned adoption. The overlay is the single legitimate home of the claim, and the adoption act is user-approved (§8).

## 2. Rule authority — the justification chain

**(a) Nim official system documentation.** `system.toOpenArray` (Nim 2.2.10, `lib/system.nim:2982-2996`): "Returns a non-owning slice … of `x` from the element at index `first` to `last` **inclusive**", with the official runnable example `let s = @[0, 1, 2, 3, 4]; s.toOpenArray(1, 3).test` where `test` asserts `x == [1, 2, 3]` — three elements from a `(1, 3)` request. The inclusive reading is the language's, not an inference.

**(b) Production call sites.** `libp2p/protocols/secure/noise.nim:314` — `hs.re[0 .. Curve25519Key.high] = msg.toOpenArray(0, Curve25519Key.high)` — and `:333` — `hs.rs[0 .. Curve25519Key.high] = hs.ss.decryptAndHash(msg.toOpenArray(0, rsLen - 1))`. `msg` is a `BytesView` (`:390`, `:424`, `:439`), so both are calls of the very template under adjudication, with `b = 0`; the destinations are the 32-byte `Curve25519Key` (`libp2p/crypto/curve25519.nim:24`, `array[32, byte]`) and `rsLen` bytes (32, or 48 with a ChaChaPoly tag). Both therefore REQUIRE exactly `e - b + 1` bytes: under a half-open reading `msg.toOpenArray(0, rsLen - 1)` would hand `rsLen - 1` bytes to a 32-byte destination and under-fill the Noise handshake exercised by `tests/libp2p/protocols/test_noise.nim`.

**(c) The sibling idiom.** The `data` template (`libp2p/utils/bytesview.nim:21-22`) — `v.data.toOpenArray(v.rpos, v.data.len - 1)` — is the inclusive idiom on the same type: the window `[rpos, data.len-1]` written as an inclusive pair.

**(d) Parameter naming.** `b`/`e` are begin/end, inclusive — consistent with (a) and (c).

**(e) The repository's only b > 0 witness is NOT an independent oracle.** `tests/libp2p/utils/test_bytesview.nim:14` — `check @(b.toOpenArray(1, 3)) == @([byte 2, 3])` — and `:19` — `check @(b.toOpenArray(1, 3)) == @([byte 4, 5])`. Git blame: the template (`bytesview.nim:18-19`) AND both assertions were introduced by the SAME commit `aa1c33ffe92ff259c432d51612524179e8f767e3` (2025-07-07, vladopajic — "refactor(noise): reduce memory usage (#1497)", which added `libp2p/utils/bytesview.nim` and `tests/testbytesview.nim`; the test file was later moved to `tests/libp2p/utils/test_bytesview.nim` by `89cacd943`). It is a same-commit, same-author **behavior snapshot**, not an independent oracle: it records what the template did, it does not adjudicate what it should do. The snapshot's expectation coincides with the half-open reading ONLY at `b = 1` (`L_actual(1, e) = e - 1 = e - b`), where the implementation is not actually half-open either — it passes an inclusive interval whose upper bound was mis-derived by subtracting the start offset twice.

**Domain split (why this rule is a language-semantics rule, not a protocol rule).** Protocol-level behavior is judged against the libp2p specifications — NOT by this binding. This slice's rule is the **Nim language semantics** of the inclusive slice convention: within that domain the pinned carriers decide. Whether the subject should change is the subject maintainers' decision, not this contract's.

## 3. The two carriers and their grounding

Both carriers are **CONSTRUCTED IR** — the subject symbol is a template, so there is no materializable `func` body to carry; the carriers state the subject's index arithmetic as IR predicates over ONE model parameter (`e`), with the start offset `b` fixed per carrier.

**Defect-lane carrier `bvSliceLenActual`** — the FIXED template's actual length with `b` pinned at 1:

```
bytesview.nim:18-19 (FIXED), b = 1:  v.data.toOpenArray(v.rpos + 1, v.rpos + e)
length = (rpos + e) - (rpos + 1) + 1 = e
```

Model: `bvSliceLenActual(e) == e`; the law side is the overlay's `bvSliceLenLaw1(e) == e` (clause 3), so the obligation is `bvSliceLenActual(e) == bvSliceLenLaw1(e)` — the spliced claim reads `(e) == e`. **UNSAT expected — the law-conformance claim**: the obligation holds for every `e` in `D`, so the solver finds NO counterexample and no witness is ever selected or replayed. (The carrier's `kind` label stays `defect` — it is the lane's structural name, not a claim that a defect exists; v0.6.3's engine constants name the lane and hardcode no law content.) The v1.0.0 model over the PRE-FIX bytes was `e - 1`, spliced claim `(e - 1) == e` — SAT for every `e`; that generation is history (§8).

**Control carrier `bvSliceLenControl`** — the same template with `b` pinned at 0:

```
bytesview.nim:18-19 (FIXED), b = 0:  v.data.toOpenArray(v.rpos, v.rpos + e)
length = (rpos + e) - rpos + 1 = e + 1
```

Model: `bvSliceLenControl(e) == (e + 1)`; the law side is `bvSliceLenLaw0(e) == (e + 1)` (clause 5), so the obligation is `bvSliceLenControl(e) == bvSliceLenLaw0(e)` — the spliced claim reads `(e + 1) == (e + 1)`. **UNSAT expected** — at `b = 0` the actual length equals the inclusive law `e - 0 + 1` exactly, and this is byte-identical to the pre-fix arithmetic (the fix changes only the `b > 0` paths).

**The honest limit**: the solver verifies the ADOPTED MODEL, not the subject. The subject's connection to a verdict is the stamped replay harness alone (§4) — the same model↔original gap the d2 lane documents. The carriers' `carriers` overlay block records the per-carrier grounding symbol (`toOpenArray`) and lines (`18-19` / `18-19, 21-22`).

### 3.1 Engine wiring — the `ax prove` lane

The overlay is wired into `ax prove` by the **bytesview slice lane** in `src/cli/axiom_engine.nim` (the toml d2-agent lane's pattern, with a stricter pin):

| Element | Binding | Contract |
|---|---|---|
| Overlay path | `NimLibp2pBytesviewSliceOverlayPath` = `config/spec/nim_libp2p_bytesview_slice.json` | Axiom-owned, Zero-Footprint, runtime root resolution — `AXIOM_ROOT` first, else `findRepoRoot` anchor walk (see note below) |
| Carrier names | `BvSliceLenDefectCarrierName` = `bvSliceLenActual`, `BvSliceLenControlCarrierName` = `bvSliceLenControl` | binding identities; the engine states no law content |
| Law names | `BvSliceLenDefectLawName` = `bvSliceLenLaw1`, `BvSliceLenControlLawName` = `bvSliceLenLaw0` | names only — the law BODIES come from `canonicalSpecIR` |
| Domain | `NimLibp2pBytesviewSliceDomain` | module, symbols, import path, blob digest, domain bounds, the two models and the two laws, the carriers' grounding, the rule id |
| Loader | `loadNimLibp2pBytesviewSliceOverlayDomain()` / `validateNimLibp2pBytesviewSliceOverlayNode()` | soExplicit authority path; every present-but-invalid shape fails closed |
| Subject pin | `verifyLibp2pBytesviewSubjectPin()` | **REAL** check: the governed module's bytes under the run's subject root must hash to `subject.blobSha256` (the d2 lane only format-checks the digest) |
| Presence | optional | an ABSENT overlay logs an explicit inert-binding line; a PRESENT-but-malformed overlay (or a pin mismatch) blocks the run (fail closed) |
| Eligibility | `overlayDeclaresLibp2pBytesviewSubject()` | module path + subject symbol **or** a constructed carrier name; inert for every other subject tree |
| Target routing | `libp2pBytesviewCarrierTargetRouting()` | `--target libp2p/utils/bytesview.nim::bvSliceLenActual` (canonical) **or** the bare `--target bvSliceLenActual` reaches the synthesizer (constructed IR has no subject-parse presence, so it resolves to zero frontier nodes otherwise; the bare name is unambiguous because the constructed carrier exists in exactly one module) |
| Carriers | `synthesizeNimLibp2pBytesviewSliceCandidate()` | one parameter `e`; body = the overlay's model; preconditions = the domain conjuncts `1 <= e ∧ e <= 5`; the claim `model == law` is β-spliced onto the `result` slot exactly once (free-variable guard fail-closed) |

**Overlay path root resolution (revised 2026-11-08, docs-first per AGENTS.md §0.5)**: the catalog path anchor is the **runtime root resolution** contract — `AXIOM_ROOT` env first, else the `findRepoRoot` anchor walk from the binary location (`.axiom_root`/`axiom.toml`, first anchor terminates) — per [productization_contract.md §1b](./productization_contract.md), [nim_effect_system_quirks.md](./nim_effect_system_quirks.md) §12 (`.axiom_root` declarative anchor), and Q-013 ([nim_2_2_10_stdlib_quirks.md](./nim_2_2_10_stdlib_quirks.md): the root-escape quirk — `AXIOM_ROOT` is the deterministic resolution; a tree-external anchor miss is a catalog read failure, fail-closed). Source-tree behavior is preserved unchanged: with `AXIOM_ROOT` unset and the binary inside the source tree, the anchor walk reproduces the same repo root the compile-time anchor (`repoRootConst()`, `src/core/utils/repo_root.nim`) baked in, so the Developer-source install surface is behavior-identical. Implementation lands in the follow-up rotation PR (closure-member files: [closure-fence-note.md](../guides/closure-fence-note.md), [rotation_preflight_prereg_2026-10-20.md](../evidence/rotation_preflight_prereg_2026-10-20.md)) — this revision documents the contract ahead of it.

The carrier pair is CONSTRUCTED IR — the subject symbol is a template, so no subject body is carried and the §2.1a extraction legs stay honestly unmeasured (EA legs empty, derivation digest recorded, the stamped harness template attached). The defect carrier is wave-faced under the examined symbol; the control carrier rides under its own name.

## 4. Replay mechanism — the ORIGINAL template decides

A confirmed disproof (SAT model → P4 → cvConfirmed → vsDisproved) is replayed against the ORIGINAL template through a stamped harness. Under the v1.1.0 law-conformance model **no counterexample exists, so this lane never fires in production** — it remains the anti-theater backstop: a future solver SAT against this overlay (e.g., a spec-injection regression) would still be replayed. The harness is compiled OUT OF TREE (scratch nimcache and outdir; the subject tree is never written to) and imports the subject module by path:

```nim
import libp2p/utils/bytesview

var bv = BytesView.init(@[byte 1, 2, 3, 4, 5, 6])
echo "AXIOM_REPLAY_BEGIN"
echo $(bv.toOpenArray(1, <lit>).len)
echo "AXIOM_REPLAY_END"
```

The `<lit>` slot is filled by the replay adapter with the solver's concrete `e`. Because `toOpenArray` is a **template**, the expansion happens in the harness's compilation unit but binds the template's SYMBOLS FROM THE DEFINING MODULE (`libp2p/utils/bytesview`) — the arithmetic observed is therefore the subject's own arithmetic, not a re-implementation. The echoed integer is the ORIGINAL template's actual length at the pinned instance; the replay postcondition (`result == e` — the defect carrier's law side `bvSliceLenLaw1(e)`, taken from the overlay) is evaluated concretely on that observation, so **the observation — not the model — decides the agreement**. A subject that returned the law's own value would CONTRADICT the solver model (`rvDisagree`) — the pipeline cannot report a disproof it did not observe.

The fixture binds the domain: `BytesView.init(@[byte 1, 2, 3, 4, 5, 6])` with `rpos = 0` — a view-relative inclusive window `[1..e]` is valid up to `e = 5`, and the control's `b = 0` window `[0..e]` up to `e = 5` (6 bytes).

Observed on the pinned FIXED subject (2026-11-13, out-of-tree scratch compile, Nim 2.2.10): `b = 1` → lengths `1, 2, 3, 4, 5` for `e = 1..5` (= `e`, the law); `b = 0` → `2, 3, 4, 5, 6` (= `e + 1`, **byte-identical to the pre-fix observation**). Historical (2026-10-22, PRE-FIX pinned subject): `b = 1` → `0, 1, 2, 3, 4` (= `e - 1`, the defect); `b = 0` → `2, 3, 4, 5, 6`.

Subject integrity folds (exact commit, tree Merkle, module sha256 pre/post, porcelain check, GateEnvLock triple) are unchanged — the replay never writes into the subject tree.

## 5. Control semantics — the injection guard

`bvSliceLenControl` is a **solver-level injection guard, not a subject observation**. It rides the same solver machinery as the defect carrier and is expected **UNSAT**: the model `e + 1` and the law `e + 1` agree for every `e`. A control SAT would indict the SPEC INJECTION (β-splice mis-binding, lost precondition, stale body marshaling) — not the subject — and fails the run closed. The control is never executed against the subject (§7).

## 6. Acceptance criteria (v1.1.0 — law conformance)

The slice is accepted only when the run produces ALL of the following, observed mechanically:

1. **Exit code 0** (`CliOutcome SUCCESS` — "verification ran; no failures"). **This is NOT a serialized `PROVED` verdict**: v0.6.3 structurally cannot serialize a positive proposition verdict (`NOT_DISPROVED` is unreachable in the display layer — the documented serialization gap); the run verdict spelling for this outcome is `INCONCLUSIVE`.
2. **No counterexample for `bvSliceLenActual`** — the spliced obligation `(e) == e` is UNSAT over the domain; the carrier obligations (3/3) pass with the counterexample gone.
3. **Control UNSAT** — `certZ3Candidate` carries NO counterexample for `bvSliceLenControl` (unchanged from v1.0.0).
4. **Two cold runs agree**: identical `canonicalRunDigest` AND payload-level equality. The local pre-verification observed this twice (canonical run digest `ac22df50bfb4e8607c43e4683914d326bdc9aa08f4f2324929c65a275b1642c9`, two cold runs, 2026-11-13).
5. **Subject pins verified** — the run's subject tree hashes to `subject.blobSha256` `e5c73a4f…` at the recorded module path (intake subject-pin check); `replay.subjectGitRef == d9e8769c3c989fc7dc78182b1358f60c85f14238` and `replay.moduleSha256AfterRun == e5c73a4f…` on any fired replay.
6. **Subject pins identical pre/post** — git OID `HEAD`/`tree` unchanged and the module's file sha256 unchanged across the run (`worktreeStable == true`).
7. **Determinism scope** — the runs are the same FIXED environment (Nim 2.2.10 toolchain + the local nimble `pkgs2` store); the run records the engine build identity under test.

**Historical (v1.0.0 acceptance, satisfied 2026-10-22 — the preserved disproof demonstration)**: exit code 1 (`VERIFICATION_FAILURE`); a `[ce-replay]` line reporting the replay AGREED; a `PROPOSITION_DISPROVED` payload (17 records) pinning `replay.subjectGitRef == a130a7f3…` and `replay.moduleSha256 == b205c969…`; control UNSAT; two cold runs identical (`canonicalRunDigest` + payload equality); subject pins identical pre/post.

## 7. Non-claims

- NOT a claim that the inclusive law holds or fails for any `(b, e)` outside the pinned carriers (`b` fixed per carrier, `e` within `1..5`).
- NOT a claim about the subject's `b = 0` runtime behavior — the control is a solver-level injection guard; the subject is never executed for it.
- NOT a claim that the pipeline extracted or verified the original template body — the model is CONSTRUCTED IR; the subject connection is the stamped replay harness observation only.
- NOT a general theorem about `BytesView.toOpenArray` for arbitrary `b` and `e`.
- NOT a formal `PROVED` verdict in the engine's verdict vocabulary — v0.6.3 structurally cannot serialize one (`NOT_DISPROVED` unreachable, the documented serialization gap); the v1.1.0 claim is law conformance WITHIN the pinned carriers (the absence of a counterexample over the pinned domain).
- NOT a claim that nim-libp2p was modified or annotated in-tree by the verification (Zero-Footprint) — the fix belongs to the subject fork's `fix/bytesview-toopenarray-slice-bounds` commit, and the fix decision belongs to the subject's maintainers.
- NOT a claim about nim-libp2p's overall correctness, safety, or memory safety.
- NOT a fully-autonomous proposition discovery — the rule's justification (Nim official inclusive `toOpenArray` semantics + production call-site requirements) was established by external investigation and adopted by an explicit user-approved act.

## 8. Adoption record and version history

**v1.0.0 (2026-10-22) — the disproof generation.**
- **Content authorship**: the investigation agent chain (contradiction-candidate survey → fact re-verification → two critique rounds). **No human authored the content; this contract claims no human authorship of it.**
- **Authority for verifying against it**: the explicit adoption act — the user-approved mission (plan `archangel-cable-plastic-man` v3, 2026-10-22) plus the committed overlay and contract. The overlay's `claimOwnership.provenance` records the same split (content = agent chain; authority = adoption). **Authorship confers NO authority.**
- **Outcome**: DISPROVED over the PRE-FIX subject (status-im/nim-libp2p @ `a130a7f3…`, blob `b205c969…`), counterexample `(b = 1, e = 4)` — observed length `3` against the law's `4`; reproduced by the live campaign (run 43363278211) and by the local negative control (exit 1, twice). This demonstration is preserved as history: the disproof motivated the subject-side fix.

**v1.1.0 (2026-11-14, this re-adoption) — the law-conformance generation.**
- **Act**: the user-approved re-adoption (PR `readopt/spec-bv-slice-v1-1-0`) — the SAME adopted law, re-adopted as a no-counterexample proposition over the FIXED subject tree Archright/nim-libp2p @ `d9e8769c…` (blob `e5c73a4f…`). The subject pin and the defect-lane model are the only semantic deltas; the law clauses, the control, the domain, and the replay fixture are carried verbatim.
- **Content authorship**: the law content is inherited verbatim from the v1.0.0 adopted work product (the original agent chain); the v1.1.0 delta (pin + model) was authored by the re-adoption agent chain. Authorship confers NO authority; the authority is this committed overlay + contract, user-approved via the PR landing.
- **Pre-verification evidence (2026-11-13, local, v0.6.3 release bundle, integrity-verified)**: two cold `ax prove` runs over the FIXED checkout with the re-pinned overlay — CLI exit 0 both times, identical canonical run digest (`ac22df50…`), carrier obligations 3/3 passing with the counterexample gone; the master negative control reproduced the v1.0.0 disproof (exit 1, twice); the shipped v1.0.0 overlay over the FIXED tree was rejected fail-closed (exit 2, subject pin mismatch) — proving the pin binds the generation. Direct out-of-tree harness observation on the FIXED bytes: `b = 1` → `1, 2, 3, 4, 5` (= `e`); `b = 0` → `2, 3, 4, 5, 6` (= `e + 1`, unchanged).
- **Raw outputs**: the v1.0.0 investigation chain's outputs are preserved verbatim under `experiments/nim-libp2p-bytesview-slice-e2e/discovery/` at the evidence PR; the pre-verification session evidence is cited in the re-adoption PR body.

**Spec registry**: `SPEC-LIBP2P-BV-SLICE` — binding overlay `config/spec/nim_libp2p_bytesview_slice.json` (`soExplicit`), rule `external:libp2p/bytesview/slice-length-law` v`1.1.0`.
