# ADR-0050: English-only phase-1 authority records -- the three acts ratification does not perform

## Status

**Accepted in part, open in part (2026-11-23)** -- authority record for the four
questions that block issues #357, #358, #359 and #361 after
[ADR-0045](0045-english-only-canonical-main.md) is ratified.

- **Time and authority**: 2026-11-23, in-session. The deciding authority is the human
  Architect of this repository (the repository owner), who granted blanket approval
  for the English-only policy family in this session. There is no delegated decider
  and no second reviewer; no signature artifact is claimed. §a, §c and §d below are
  decisions of that authority as executed by the agent under the standing instruction.
- **Decision and effect**: §a records the AGENTS.md instruction and settles the
  `memoryPolicyMarkers` question; §c records the NLID detector pin; §d collapses #361
  into #373 and drafts the clause text. §b is **not decided**: the Korean locale
  (`data/i18n/ko.json`) is returned to the Architect as an open product decision, with
  the measured consequences listed so the decision can be made without re-measuring.
- **Boundary unchanged**: this ADR changes no code, no workflow, no gate, no policy
  file, and no locale asset. It does not translate AGENTS.md (§a records why, and the
  instruction to do so), it does not delete `data/i18n/ko.json` (§b), and it does not
  pin a detector in the policy (§c records the pin that implementation will bind).

## Date

2026-11-23

## 0. What this record is for

ADR-0045 was written, and never ratified. Its status was `Proposed` at
`docs/adr/0045-english-only-canonical-main.md:5` and
`docs/spec/english_only_policy.md:3` carried the same status, while ADR-0044 was
already `Accepted` -- which is why `script-scan` enforces a Unicode Script allowlist
today and nothing else of the English-only plan does. That single authority act is
what blocked #357, #358 and #359. It is performed in the same change as this ADR
(ADR-0045 and the policy move to `Accepted`).

Ratification is not implementation. Four questions remain that a ratified contract
cannot answer by itself, because each of them needs either a human instruction, a
measurement, or a product decision. This ADR records them in the only form that is
honest: as records, with the measurement behind each one cited to `path:line`.

## §a -- #357: the AGENTS.md self-reference and the `memoryPolicyMarkers` decision

### a.1 The clause is self-referential

`AGENTS.md:10-17` (§-1, `ABSOLUTE RULE`) states that the listed files are immutable
without the explicit approval of the human architect (`:12`), lists two entries
(`:14`, `:15`), and forbids an agent from modifying, bypassing, or invalidating them
without an explicit instruction (`:17`). One of the two entries is `AGENTS.md`
itself (`:15`).

The clause therefore has the shape of a lock whose key is inside the locked box: the
only place the permission could be written is the file that forbids amending it. This
is not a defect to be legislated away -- it is the intended shape, and it means the
permission must arrive as an *external* instruction from the named authority, recorded
outside the protected file. That is what a.2 does.

### a.2 The instruction

Recorded verbatim in substance, per AGENTS.md §-1, as instructed by the human
architect (repository owner) in the 2026-11-23 session:

> Per AGENTS.md §-1, the human architect (repository owner) instructs that `AGENTS.md`
> is translated to English under ADR-0045. The translation is a meaning-preserving
> rewrite; §-1 immutability continues to apply to the translated file, and its
> two-name list and prohibition text are unchanged in substance. This is a one-time,
> path-and-purpose-scoped instruction, not a general opening of §-1.

Three properties of that instruction are load-bearing and are recorded here so no
later reader can widen them:

1. **One path.** `AGENTS.md`. Not `docs/agents/**`, not `config.nims`, not the other
   §-1 entry.
2. **One purpose.** A meaning-preserving translation. Not a re-scoping of §-1, not a
   merge of the two entries, not a change to what is immutable.
3. **One time.** It authorizes one translation batch, and the batch carries a
   translation lineage record (`docs/spec/translation_lineage.md:11-23`, `:82-128`).
   After the batch lands, `AGENTS.md` is immutable again under the same clause, now
   reading in English.

The instruction does **not** authorize the translation in this change. See §a.4 and
Deliverable C in §Consequences: modifying `AGENTS.md` produces a `SURFACE_FORBIDDEN`
FROZEN verdict from `repository-surface`, which this workstream is required to keep
green, so the translation is not executed here. The instruction stands and is
executable by the batch that can keep that check green.

### a.3 The `memoryPolicyMarkers` question -- decision: option (A), retain and translate

The AGENTS.md translation cannot be a pure prose edit, because two Korean strings in
AGENTS.md are assertion tokens read by code:

- `src/core/ast_lint/axiom_ast_lint.nim:145-161` is a `static:` block that reads
  `AGENTS.md` (`:148`), requires two literals verbatim (`:157`), and `doAssert false`
  when one is absent (`:161`).
- The same two literals are mirrored in policy at
  `src/gate/architecture_policy.lock:164-169` (`[memory_policy_markers]`, literals at
  `:168-169`).
- `tools/generate_agents_docs.nim:119-130` projects that section into
  `docs/agents/memory_policy.md`, whose `:7-8` carries the literals.

**Decision: (A) retain the check and translate the literals in all three places.**

Measured, for each option:

**(A) Retain and translate.** The three edits are legal under the surface policy,
measured path by path:

| path | class | source |
|---|---|---|
| `src/core/ast_lint/axiom_ast_lint.nim` | `PRODUCT` (`src/core/**`, MODIFY PASS) | `config/repository_surface.json:20` |
| `src/gate/architecture_policy.lock` | `CONTROLLED` (MODIFY PASS) | `config/repository_surface.json:288` in the CONTROLLED list opened at `:49`; the conflict with the `src/gate/**` FROZEN glob (`:325`) is the registered `gate-infra` carve-out at `:431` |
| `docs/agents/memory_policy.md` | unlisted -> `defaultClass: PRODUCT` (MODIFY PASS) | `config/repository_surface.json:330` |

So (A) is green on every path it touches. Its cost is one extra file per location and
a regeneration step (`tools/generate_agents_docs.nim` has no Makefile target; the
regeneration is a manual run recorded in the batch).

**(B) Retire the check.** Measured, the check guarantees nothing today:

- `axiom_ast_lint` appears in **zero** Makefile targets and **zero** `.github/**`
  files (measured across `Makefile`, `.github/workflows/**`,
  `.github/actions/**`). The only source-level mentions are its own file, the data
  inventories under `data/**` and `src/generated/**`, and one comment.
- Its only importer is `src/core/trusted/compile_time_manifest.nim:23`. That module's
  only importer is the forwarding stub `src/core/compile_time_manifest.nim:11`, and
  the stub has **zero** importers. No build entry point (`src/bin/ax.nim:9-10`,
  `src/bin/run_gate.nim:5`) reaches the module, so the `static:` block at
  `axiom_ast_lint.nim:145` is compiled by nothing that runs.
- `memoryPolicyMarkers` is parsed at `src/core/policy/parse_helpers.nim:80`, typed at
  `src/core/policy/architecture_policy_types.nim:75`, and registered with
  `informational: true` at `src/core/policy/parsers/parse_meta.nim:80-85`. No
  validator consumes it.

**(C) Wire it first, then translate.** This needs a new Makefile target, a CI job, and
a registration of the check's authority. ADR-0045 (f)
(`docs/adr/0045-english-only-canonical-main.md:113-122`) forbids a new required check
and a new producer identity; Phase 0 adds no gate dimension. (C) is a separate
workstream and is rejected here on scope, not on merit.

**Why (A).** Four reasons, in order of weight:

1. The marker is the machine binding of a HARD RULE (AGENTS.md §0.4c, `:44-49`, with
   the literals quoted at `:46-47`). Retiring it while the rule stays in the
   constitution produces exactly the shape AGENTS.md §0.9 names (`:74-76`): a rule
   that appears to be enforced and is not. §0.9 also requires that discovered theater
   be **registered** in `data/debt_registry.json` (prefix `Theater/`, source
   `theater_audit`) rather than quietly patched -- so (B) is not the cheap option it
   looks like; it is a constitutional edit plus a ledger registration.
2. (B) costs zero enforcement *today* (measured above), which cuts both ways: nothing
   is gained by deleting it now, and the deletion would have to be undone the moment
   anyone reconnects the one-line import. (A) leaves the check correct for that day at
   the price of a mechanical three-file edit.
3. Every path (A) touches is PASS under the surface policy -- the lock file included,
   because its FROZEN conflict is already a registered carve-out
   (`config/repository_surface.json:431`). There is no policy cost to (A), while
   (B) needs a debt-registry entry and (C) needs a gate registration.
4. The translation is not executed in this change, so the decision must be the one a
   later batch can execute without asking again. (A) is that decision; it leaves no
   unresolved policy question behind.

**The honesty clause for (A).** The check is dead (measured in (B)), so translating
its tokens produces a green that nothing observes. The batch that executes (A) MUST
therefore carry two pieces of evidence, not one:

- a positive run (`nim c -r` over a module that imports
  `core/compile_time_manifest`) proving the translated literals satisfy the block;
- a mutation run proving the block still fails when a marker is removed.

Without both, (A) would be theater of a subtler kind: an assertion rewritten with
nobody watching whether it still asserts.

**Recorded finding, registered as a follow-up.** The dead check is a §0.9 finding and
its registration in `data/debt_registry.json` is required. It is **not** performed
here: debt-registry entries carry schema and `contentHash` obligations and
`debt-registry-gate` is a required context, so a hand-written entry is a separate
gated act with its own verification. This ADR is the discovery record; the
registration is the follow-up.

### a.4 Will `make check-repository-surface` fail, and is it required?

**Expected verdict: FAIL, with `SURFACE_FORBIDDEN` on a FROZEN MODIFY.** Measured:

- `AGENTS.md` is in the `FROZEN` list (`config/repository_surface.json:315-328`, entry
  at `:316`) and `FROZEN.MODIFY` is `FAIL` (`:342-346`). The verdict is computed
  against the **base** policy at `merge-base(origin/main, HEAD)`
  (`config/repository_surface.json:361`, `Makefile:611-621`), so the PR cannot relax
  its own rule.
- The `selfAmendment` exception cannot clear it: `allowedPaths` holds exactly four
  paths (`config/repository_surface.json:353-360`) and `AGENTS.md` is not one of them.
  The guard's exception conditions (a)-(d) require every FROZEN violation path to be
  in that list (`tools/surface_guard.nim:556-589`).
- `frozenExceptions` (`config/repository_surface.json:374-441`) registers 8 groups and
  116 exact paths; **none** is `AGENTS.md`.

**Is it required?** Measured, `repository-surface` is **not** one of the seven
contexts the live ruleset requires (ruleset `27097366`:
`admission-check`, `bsec-integrity`, `debt-registry-gate`, `generation-acceptance`,
`axiom-operational-slice`, `publication-integrity`, `readiness-verdict`).
`config/policy/merge_admission.json:4` (v1.5.0 clause) records
`repository_surface.yml` as "by contract NOT a required check", and `Makefile:600-611`
documents the target as an advisory report that does not block merge.

So the honest answer is two-part: **the check is expected to fail, and it is not a
merge-required check** -- but it is a visible red on the PR, it is named in this
workstream's required-check constraint set, and a FAIL there is indistinguishable to a
reviewer from a real boundary violation. That is why AGENTS.md is not translated in
this change (§Consequences). The translation is executable through one of two
pre-existing lanes, neither of which this record chooses: a registered
`frozenExceptions` carve-out for the single path `AGENTS.md` (a policy PR first,
base-policy binding means the body PR follows), or an operator-authorized break-glass
landing. Both are authority acts above this ADR.

## §b -- #358: the Korean locale -- OPEN DECISION, returned to the Architect

**Not decided here.** `data/i18n/ko.json` is not modified and not deleted by this
change, and no code that reads it is touched.

The contract already places this outside repository hygiene.
`docs/adr/0045-english-only-canonical-main.md:142-146` (j) keeps `data/i18n/ko.json`
as an exact-path exemption for `script-scan` that is *counted, not exempted* under the
English-only terminal criteria, and `docs/spec/english_only_policy.md:166-170` says
its removal "is a separate product decision". It is a shipped product feature: a
`locale == "ko"` branch renders localized gate labels and descriptions
(`src/ui/notion_semantic_mapper.nim:62-71`). Removing a shipped feature on a "no
caller passes it today" argument is a product decision, and AGENTS.md §0.12 (`:98-104`)
forbids starting that work without a committed contract. It is therefore returned.

### b.1 Consequences, measured

The sibling triage reported these; every one was re-verified in this worktree at
`origin/main` = `5b14bbfc`.

| fact | measurement |
|---|---|
| sole `exemptPaths` entry for `script-scan` | `compliance/policy/script-scan-policy.yml:39-41` (`exemptPaths:` at `:39`, the single `path: "data/i18n/ko.json"` entry at `:40-41`) |
| closure input for the B-layer cache key | `.github/actions/setup-axiom-toolchain/action.yml:324` (`data/i18n/ko.json` inside the closure-input list `:316-329`) |
| the key itself | `b_identity` is the sorted digest of the closure lines (`action.yml:340-346`); `b_key` at `:352` |
| fail-closed behaviour | `action.yml:327`: `[ -f "$f" ] \|\| { echo "AXIOM_CACHE_KEYGEN: FAIL -- closure input $f absent from tree $src (fail-closed)"; exit 1; }` |
| compile-time consumer | `src/ui/notion_semantic_mapper.nim:29` (`staticRead("../../data/i18n/ko.json")`), rendering branch at `:62-71` |
| closure/witness input | `src/verification/semantic_set_derivation.nim:278` (`ComputedStaticReadTargets`) |
| witness path | `src/verification/judgment_cas.nim:817-836` (`judgmentWitnessPaths`, which appends `ComputedStaticReadTargets` at `:835-836`) |
| test pins | `tests/ci/test_b_cache_anchor.nim:507`; `tests/ci/test_publication_gate_tools.nim:632`, `:729`, `:739`; `tests/ci/test_english_audit_inventory.nim:12`, `:80`, `:117`, `:136` |

Two consequences are stronger than the triage's summary and are recorded because they
change the shape of the decision:

1. **Deletion is a hard CI break, not a cache-key move.** Because the closure list is
   fail-closed (`action.yml:327`), a tree without `data/i18n/ko.json` fails
   `AXIOM_CACHE_KEYGEN` outright on the next key computation. Removing the file
   therefore requires editing the closure list in the same coherent generation, which
   makes it a CI epoch transition under AGENTS.md §2.5 (`:150-156`) and
   `docs/agents/ci_epoch_cutover.md` -- not a cache-key change.
2. **`AGENTS.md` is the cheap half of the same question, measured.** `AGENTS.md` enters
   the closure as a *presence bit* (`nonempty  AGENTS.md`, `action.yml:330-332`), not
   as a digest, so translating its content does not move the B-layer key at all. That
   asymmetry is why §a's translation has no CI-epoch cost while §b's deletion does.

### b.2 What the Architect is being asked

Not "should the file go": that answer needs a product contract (the locale is a
shipped surface), a metric consequence (`koreanLocaleAssets` is one of the four
terminal counters, `docs/spec/english_only_policy.md:149-170`), a CI epoch cutover
record, and an edit to the closure list and the exemption list -- three of which are
trust-surface or gate-relevant files. The question is:

> Is the Korean locale a supported product surface in v1, or is it retired? If it is
> retired: which release boundary does it retire at, and does the epoch cutover land
> as its own generation transition?

Nothing in this ADR answers it. `data/i18n/ko.json` stays exactly as it is.

## §c -- #359: the NLID detector pin

ADR-0045 already decides the semantics: (d) two modes and one ratchet (`:100-105`),
(e) the same seam, the same context name (`:107-111`), (f) no new check and no ruleset
change (`:113-122`), (g) NLID is required before "English-only" may be claimed
(`:124-130`), (h) UNKNOWN is blocking (`:132-135`), (i) exact paths only (`:137-140`).
`docs/spec/english_only_policy.md:186-202` (§9) adds the pin field set: `name`,
`version`, `sha256`, `modelSha256` -- "a version string alone is not a pin".

What no code can settle is **which detector is pinned**. This section records that
choice, the licence basis for it, and the trade-off accepted.

### c.1 The pin

| field | value | basis |
|---|---|---|
| `name` | `franc-min` | npm package identity |
| `version` | `6.2.0` | resolved from the registry, 2026-11-23 |
| `sha256` (artifact) | `82417c7fe3778988b00b1b0c4db783b583ce9c8321dd7279f7a7f67709686654` -- **to be bound in the policy file at implementation; measured this session, not yet a binding pin** | sha256 of the pinned tarball `franc-min-6.2.0.tgz` (55,071 bytes, unpacked 126,936 bytes) |
| `modelSha256` | `8a9e225daa848446d520eefa658cae854bc945a6ae871547603f46f8323f148c` -- **to be bound at implementation** | sha256 of `package/data.js` (102,603 bytes): the trigram profile table, which is the model. The artifact digest and the model digest answer different questions, exactly as `docs/spec/english_only_policy.md:195-198` requires |
| transitive pins | `trigram-utils@2.0.1` (MIT, tarball sha256 `3390b247fcb2dc1589ee3fa714986bce010af465446299746ee9928094bee8e6`), `n-gram@2.0.2` (MIT, `05cf48444f90a33bac1750cf30f18dbafd975b8006d6c6496acccf93571df504`), `collapse-white-space@2.1.0` (MIT, `7e2300655decce051cf4c8ece8cf997ed0c16ce6eb3cec975529d12cfa211d5e`) | measured 2026-11-23; the closure is four packages, all MIT, both leaves dependency-free |
| licence | MIT | `package.json` `"license": "MIT"`; MIT is already a declared licence of this repository (`LICENSES/MIT.txt`, alongside `Apache-2.0.txt`, `CC-BY-4.0.txt`, `Zlib.txt`; the product licence itself is `LicenseRef-Axiom-SAL-1.0`, `axiom.nimble:4`) |
| `glossarySha256` | **to be filled at implementation** -- it binds the glossary revision the first batch reviews against (`docs/spec/translation_lineage.md:69`, `:123-128`); the literal `declared-unavailable` is not acceptable for a glossary | `docs/spec/translation_lineage.md:43` |
| acceptance corpus | `tests/fixtures/english_only/nlid_acceptance_corpus.json` (new) with the labelled inventory `tests/fixtures/english_only/nlid_acceptance_corpus.inventory.json` | labels: `en` (expected PASS), `non-en` (expected FAIL), `ambiguous` (expected UNKNOWN). Stored with `\uXXXX` escapes so the corpus does not itself add disallowed code points to the judged tree under today's `script-scan` -- a dependency on the escape gap that #359 closes, recorded here so it is not discovered later as a surprise |

The four "to be bound" cells are deliberate. `docs/spec/english_only_policy.md:199-200`
says a missing pin is UNKNOWN and never a pass, so writing a digest into a prose ADR
and calling it a pin would violate (h). The values are measured and reproducible; the
*binding* is a policy-file edit that lands with the implementation.

### c.2 Licence check, and why the obvious candidate was rejected

The pin must be licence-compatible with Axiom. The repository declares four licences
(`LICENSES/Apache-2.0.txt`, `CC-BY-4.0.txt`, `MIT.txt`, `Zlib.txt`); anything else
needs a new licence declaration, which is a provenance act, not a detector choice.

- `franc-min` 6.2.0 and its whole closure are **MIT** -- compatible without a new
  declaration.
- **Rejected: fastText `lid.176.ftz`.** It is the tempting pick: one ~0.9 MB single
  file, a real statistical model, no neural weights. But the fastText *code* being MIT
  (its README's Licence section says "fastText is MIT-licensed") does not license the
  *model*: the published `lid.*` models are reported under **CC BY-SA 3.0**, a
  ShareAlike term that is neither among the four declared licences nor
  ShareAlike-compatible with a permissive distribution. Naming it as the pin would put
  a share-alike obligation on an artifact Axiom redistributes. Rejected on
  contamination risk. (The model licence page could not be fetched in this session --
  see §Declared limitations.)
- **Rejected: CLD3 / `lingua` (neural).** A 50-100 MB weights class violates
  Zero-Footprint (AGENTS.md §0.1, `:30`), and the policy forbids a per-run download
  (`docs/spec/english_only_policy.md:195-198`).
- **Rejected: Python `langdetect`.** Apache-2.0 is compatible, but its detector is
  non-deterministic unless `DetectorFactory.seed` is pinned, and AGENTS.md §0.2
  (`:32-34`) requires determinism; a statistical model whose answer depends on
  process-local RNG state is the wrong object to build a blocking verdict on.

### c.3 The trade-off accepted

`franc-min` is a trigram + script frequency detector. Against a neural classifier it
is worse on two classes that matter:

1. **Short strings.** Below roughly a sentence there is not enough trigram mass; the
   library exposes a minimum-length option and returns `und` when its distance metric
   has no winner. The wrapper MUST treat both `und` and an input below the declared
   minimum as **UNKNOWN**, never as `en`.
2. **Close Latin-script pairs.** Dutch/Afrikaans, Danish/Norwegian, Spanish/Portuguese
   are the classic confusions; a trigram model separates them less reliably than a
   contextual model.

The price is therefore paid in **more UNKNOWNs**, early, on short and closely-related
inputs -- each of which blocks (`docs/spec/english_only_policy.md:204-220`, §10). That
is the direction ADR-0045 (h) requires: blocking on ambiguity, never passing on a
guess. The alternative direction -- a more accurate large model -- buys fewer UNKNOWNs
with a 50-100 MB artifact, a network fetch, and a licence question, and it is rejected
for those three reasons, not for accuracy.

A second accepted cost: `franc-min` is JavaScript. It runs on the Node runtime the
Actions platform already provides, so no toolchain is added to the Nim build and
nothing enters the shipped CLI binary (Zero-Footprint), but the detector is a separate
process at the I/O boundary, not a linked Nim library. That is compatible with the
policy's "deterministic, offline, no network call" requirement
(`docs/spec/english_only_policy.md:195-198`) and incompatible with calling it part of
the product.

### c.4 Landing lane, measured

- `tools/ci/publication_script_eval.nim` and `tools/ci/publication_report.nim` are
  both in the 39-path `trustSurface` (`config/policy/merge_admission.json:111-112`;
  `len(trustSurface) == 39` measured). A PR touching either is
  `TRUST_SURFACE_MODIFIED`, auto-merge is denied, and it lands through the audited
  break-glass lane (MUST-T2) -- the same clause ADR-0045 (f) states at `:113-122`.
- Adding a **7th report dimension** (beyond the six `publication-integrity`
  dimensions) most likely needs an explicit `trustSurface` registration. The v1.20.0
  clause (`config/policy/merge_admission.json:4`) registered the eight
  `publication_*.nim` evaluators as **literal paths**, not globs, and states that a
  future evaluator addition requires explicit registration, because the ghost-authority
  leg of `tools/ci/proof_unit_consistency_gate.nim` verifies that every `trustSurface`
  path exists. The English-only dimension is therefore a two-step landing: register the
  evaluator paths (policy PR), then add the dimension (body PR).
- Neither step is performed here. §c records the pin; the implementation is a separate
  break-glass workstream.

## §d -- #361 dedupe: the conversation-language clause belongs to #373

`docs/spec/english_only_policy.md:53-58` already delegates the conversation surface to
the contributor contract: PR titles, bodies, issues, reviews and commit messages are
"governed by the contributor contract (issue #373; the root `CONTRIBUTING.md` awaits
the audited trust-surface lane)". That parenthetical is a forward reference to a file
that does not exist -- the root has no `CONTRIBUTING.md` and `docs/` has none either
(measured). Two more measurements fix where the clause can live:

- `.github/ISSUE_TEMPLATE/` does not exist, so there is no template to carry an
  issue-side instruction.
- `.github/pull_request_template.md:1-25` exists and carries no language instruction
  at all.

And `.github/**` is FROZEN (`config/repository_surface.json:322`) and a trust-surface
entry for the workflows it names, so editing a template there is a boundary act.

**Recorded decision.** The conversation-language clause belongs in the root
`CONTRIBUTING.md`, which is #373's deliverable. #361 therefore has **no independent
artifact**: closing it as a duplicate of #373 (or folding its text into #373) is the
correct disposition, and it is not a code or policy change. This ADR does not close
#361 and does not create `CONTRIBUTING.md` -- both are outside this change's authority.

### d.1 The clause text, for #373 to adopt verbatim

```markdown
## Language

Axiom's repository text is English single-source
([ADR-0045](docs/adr/0045-english-only-canonical-main.md);
[`docs/spec/english_only_policy.md`](docs/spec/english_only_policy.md)). The rule does
not stop at the tree: it governs the conversation surface too.

- Write pull request titles and bodies, commit messages, issue reports, review
  comments, and design discussion in English.
- Korean, or any other language, is fine in a quoted log line, a user-supplied
  reproduction, or a citation whose wording must stay verbatim. Say why in one
  sentence when you do it.
- No repository-side gate reads the conversation surface, so this is an obligation on
  you, not a check you can pass. A non-English contribution is not "green because
  nothing flagged it".
- A change that translates repository text additionally needs a translation lineage
  record ([`docs/spec/translation_lineage.md`](docs/spec/translation_lineage.md)).
  That is a separate obligation from writing in English.
```

Two properties of that text are deliberate: it states the obligation without
pretending a gate enforces it (AGENTS.md §0.9), and the exemption it grants is narrow
and reasoned rather than an escape hatch (ADR-0045 (i), exact paths only).

## Consequences

- **ADR-0045 and its policy are `Accepted`, and nothing activated.** The next reader
  of `docs/adr/0045-english-only-canonical-main.md` sees a ratified contract; the
  enforcement surface is byte-identical to before this change.
- **#357 is recorded, not closed.** The instruction is written, executable, and
  scoped; the translation itself is blocked by a FROZEN verdict on `AGENTS.md`
  (§a.4) and is deliberately not rushed: a 204-line meaning-preserving rewrite that
  changes agent behaviour by accident is a worse outcome than a recorded instruction.
- **#358 is returned, not absorbed.** The Korean locale is a product surface; the
  decision is the Architect's, and the consequence table in §b.1 exists so it can be
  made in one sitting.
- **#359 has a pin and a trade-off.** The detector is small, MIT, offline, and
  deliberately less accurate than a neural model, with UNKNOWN as the compensating
  mechanism rather than a better guess.
- **#361 collapses into #373**, with the clause text drafted so #373 needs no writing
  round-trip.
- **`docs/spec/translation_lineage.md` stays `Proposed`.** The ratification act named
  two documents (ADR-0045 and `english_only_policy.md`) and this ADR does not widen
  it. The lineage spec is referenced as normative by an `Accepted` ADR while itself
  remaining `Proposed`; that asymmetry is recorded here as a follow-up rather than
  silently fixed.
- **One §0.9 finding is open.** `axiom_ast_lint`'s memory-policy block is dead code in
  the build graph (§a.3 (B)). Its registration in `data/debt_registry.json` is a
  required follow-up and is not performed here.

## Declared limitations

- The fastText model licence was not re-read from its publisher in this session (no
  HTTP access to the model page); the rejection in §c.2 rests on the reported CC BY-SA
  3.0 terms and on the fact that the model licence is *not* the tool licence. If the
  report is wrong, the rejection still holds for a different reason: a model whose
  licence differs from its tool's licence must be read before it is named, and that
  reading is the implementation step.
- The detector's accuracy is not measured here. No corpus has been run; §c records
  what will be pinned, not what it will find.
- The `franc-min` digests in §c.1 are measurements of artifacts fetched on 2026-11-23.
  They are reproducible (`https://registry.npmjs.org/franc-min/-/franc-min-6.2.0.tgz`)
  but they are not pins until the policy file carries them.
- §b's consequence table is a set of citations, not an impact analysis. It does not
  answer whether any external consumer uses the Korean locale, because that fact is
  not in this repository.
- Nothing in this ADR is a claim about the current tree's language. The tree is
  measured elsewhere (`docs/reports/english_audit_inventory_be7db250.json`), and one
  UNKNOWN or one non-English finding blocks the claim
  (`docs/spec/english_only_policy.md:204-220`).

## References

- [ADR-0045](0045-english-only-canonical-main.md) -- the ratified contract this record
  serves.
- [`docs/spec/english_only_policy.md`](../spec/english_only_policy.md) -- scope, modes,
  metrics, terminal criteria, detector pinning, UNKNOWN semantics.
- [`docs/spec/translation_lineage.md`](../spec/translation_lineage.md) -- the batch
  manifest that any AGENTS.md translation batch must carry.
- [ADR-0044](0044-unicode-script-allowlist-admission.md) -- the Script allowlist; not
  an English-only guarantee.
- `docs/adr/0040-resid22-observation-window-reevaluation-decision-request.md` -- the
  status vocabulary this ADR's Status section follows (time and authority, decision and
  effect, boundary unchanged).
- `config/repository_surface.json` -- FROZEN class and verdict block (`:315-328`,
  `:342-346`), `selfAmendment.allowedPaths` (`:353-360`), `frozenExceptions`
  (`:374-441`), base-policy binding (`:361`).
- `config/policy/merge_admission.json` -- the 39-path `trustSurface` (`:111-112`) and
  the v1.5.0 / v1.20.0 clauses that decide what is a required check and what must be
  registered explicitly.
- `config/policy/trust_surface_manifest.json` -- the 18 paths whose blob equality gates
  `admission-check`; `AGENTS.md` is not among them.
- `src/core/ast_lint/axiom_ast_lint.nim:145-161` -- the memory-policy assertion block.
- Issues #357, #358, #359, #361, #373 -- the tracked questions this record answers or
  returns.