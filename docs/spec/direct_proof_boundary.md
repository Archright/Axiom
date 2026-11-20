# Direct Proof Boundary — per-construct status (SSOT)

**Status**: Normative boundary declaration (v1, 2026-11-19; revised after the translation-loss closure, #118)
**Created**: 2026-11-19
**Related**: [certification_continuity_contract.md](certification_continuity_contract.md) §2, [authority_contract.md](authority_contract.md) §1, [strict_completeness_binding.md](strict_completeness_binding.md) §9, [verification_density.md](verification_density.md), [productization_contract.md](productization_contract.md) §1, [adopted_model_observation_contract.md](adopted_model_observation_contract.md) (the adopted-model + stamped-observation shape for subjects outside this boundary)
**Scope**: the canonical Nim → IR → Lean direct-proof path. Rust/LLBC subjects are governed by [rust_certified_subset.md](rust_certified_subset.md) and are not widened here. This document does not classify SMT/CHC search outcomes; it classifies whether a direct Lean proof can exist.

## 1. Why this document exists

The certification scope is already bounded, but the bounds are stated at different altitudes:

- certificate scope: `docs/spec/certification_continuity_contract.md:50` defines "Certified subset of Nim"; `:61-64` states the certificate is about the declared subset's canonical AST; `:66-70` lists "Nim 언어 전체의 의미론" under what is **not** proved.
- product scope: `docs/spec/productization_contract.md:11` limits the subject to the Nim kernel scope plus the declared Rust subset; `:21` lists "broad AI-code verification guarantee" and "Race-Memory-Logic 전면 증명" as non-goals. The kernel predicate itself is `{.axiom.}` plus purity (`verification_density.md:9-12`).
- semantic authority: `docs/spec/authority_contract.md:26` places the denotation over the certified subset; `:38` says an operation outside the subset has no Certified proof and fails explicitly.
- completeness: `docs/spec/strict_completeness_binding.md:445-447` says the contract covers the bounded certified subset and does not widen extraction coverage.
- density: `docs/spec/verification_density.md:16-19` keeps the Rust subject on a separate scope lock; `:170-172` defines VKD as `|VKS ∩ certGreen| / |VKS|`.

None of these says what a specific construct's status is. This document supplies exactly that, so an unproved symbol is not read as a false one.

## 2. The rule

> **not directly provable ≠ refuted ≠ mathematically impossible.**

Reading:

- **not directly provable** describes Axiom's artifact: no non-empty denotation is emitted, so there is no direct proof and no disproof in this pipeline. It is not a statement about the construct's semantics.
- **refuted** describes a specific (subject, proposition) pair: replay evaluated the IR to a concrete value that violates the proposition. It is never inferred from a construct being unsupported.
- **mathematically impossible** is a semantic claim. Axiom does not make it here; the kernel checks the emitted proof term for the policy proposition, no more.

Status vocabulary (exactly one per construct):

| Status | Meaning |
|---|---|
| **directly provable** | An IR arm and a non-empty Lean denotation exist inside the bounded subset, so an obligation depending only on it can be rendered and kernel-checked. |
| **not directly provable** | No non-empty denotation exists: the construct is declared outside the subset, is replaced by a loss-marked placeholder, or is refused by the renderer. No verdict follows. |
| **incomplete** | An intended path exists but cannot produce complete evidence as written: an unreachable recognizer, a dropped region, or an untranslatable declaration kind. A coverage gap, not a semantic judgment. |
| **refuted** | A replayed counterexample evaluates the IR to a concrete value that violates the proposition. Only this status is a semantic verdict, and it is earned per obligation. |

The directly provable baseline is the expression subset with a non-empty lowering at `src/verification/obligation/canonical_verification.nim:186-259`: integer literals, parameters, `+ - * / mod`, `< <= > >= ==`, `and or`, `if`/`else`, and `not` on Bool, subject to the documented div/rem domain identities. The same function returns `""` for `irCall`, `irLet`, `irLoop`, `irRecCall`, `irCase`, casts, strings, and non-parameter variables (`:257-259`); those are outside the baseline even where an IR arm exists. Every construct below is outside that baseline.

## 3. Per-construct status

| Construct | Observation | Status |
|---|---|---|
| object constructor (`T(f: v)`, `nnkObjConstr`) | generic fallback: loss-marked placeholder, no arm | **not directly provable** |
| `template` definition | registrable as a subject, not IR-translatable | **incomplete** |
| `move(x)` | opaque call, rejected by the canonical renderer | **not directly provable** |
| `in` / `of` | infix to `boUnsupported`, loss-marked since #118, empty lowering | **not directly provable** |
| `..` / `..<` slice (`s[a..b]`) | index infix to `boUnsupported`, bracket is a rejected call | **not directly provable** |
| `..` / `..<` range-for, NimNode path | translated faithfully (`boLt` / `boLe`) since #118; no `irLoop` denotation exists | **not directly provable** — see §3.6 |
| `..` / `..<` range-for, Canon path | `ckForStmt` region drop; loop absent, loss recorded | **incomplete** |
| `shl` / `shr` | `spShiftUnsupported`, loss-marked since #118, empty lowering | **not directly provable** |
| any other infix (`boUnsupported`) | `else: boUnsupported`, loss-marked since #118 | **not directly provable** |

### 3.1 Object constructor

`convertExpr` has no `nnkObjConstr` arm; the generic unhandled-expression fallback calls `markLoss(ctx)` and returns `irLit(0)` (`src/core/trusted/ast_to_ir.nim:560-566`). The Canon mirror does the same (`:1183-1189`). `markLoss` sets `lossySeen` (`:104-107`), which becomes `translationLossFree=false` (`:1476`, `:1667`); fact injection rejects an unproven completeness gate (`src/verification/obligation/semantic_environment.nim:224`).

Not refuted: the zero is a marked placeholder, never the source value, and no evaluator path claims the constructor computes zero. The correct reading is "no artifact", not "false".

### 3.2 Template

`hasAxiomPragma` accepts `nnkTemplateDef` (`src/core/trusted/axiom_pragmas_macros.nim:13-24`), so a template can carry the `{.axiom.}` annotation. IR translation accepts only `nkProcDef` and `nkFuncDef` (`IrTranslatableDefKinds`, `src/infrastructure/external_ir_materializer.nim:92`); any other discovered declaration is reported as `moUnsupportedDeclKind` with a reason, never silently absent (`:208-221`).

A template call is expanded by the pinned frontend before extraction. The expansion can be directly provable if it stays inside the bounded subset; the definition itself has no IR, denotation, or theorem. Coverage is therefore partial: **incomplete**. If the expansion contains another construct from this table, that construct's row governs.

A template definition nested inside a body is not traversed as an expression (`traversesSubtreeAsExpression`, `src/core/trusted/ast_to_ir.nim:146-161`); the generic statement fallback records a region drop (`markRegionDrop`, `:1349-1362`; NimNode mirror `:1035-1040`) instead of a translation.

### 3.3 move

`move(x)` arrives as a call (measured with the pinned Nim 2.2.10: `Call Ident "move"`). `convertCall` has no move arm and preserves it as `irCall("move", args)` (`src/core/trusted/ast_to_ir.nim:492-515`; Canon mirror `:1106-1118`). The canonical lowering has no `irCall` arm and returns `""` (`src/verification/obligation/canonical_verification.nim:257-259`); `renderLeanForFuncDef` returns `""` when the body lowering is empty (`:481-509`).

`move` is not a layout intrinsic (`ast_to_ir.nim:377-392`), so conversion does not set the loss bit. Rejection happens at rendering, not conversion. This is one reason the loss bit is not a provability oracle (see §5).

### 3.4 in / of

Both arrive as infix (`nnkInfix`/`ckInfix`) and are converted through `convertBinOp`, which enumerates the supported operators and ends with `else: boUnsupported` (`ast_to_ir.nim:343-355`; expression arms `:534` and `:1142`). Since #118 the two infix arms pass the result through `checkedBinOp`, which marks a translation loss for `boUnsupported`/`boShl`/`boShr` (`:117-121`) — the op is kept unchanged, so the IR still spells the truth, but no loss-free claim can carry it. The materializer refuses a definition that claims loss-free translation while containing such a sentinel (`lossFreeTranslationContradictsBody`, `src/infrastructure/external_ir_materializer.nim:533-545`, refusal at `:714-716`).

`boUnsupported` has no Lean denotation: the canonical lowering returns `""` (`canonical_verification.nim:231`); the auxiliary name mapping calls it `UNSUPPORTED` (`src/core/trusted/ir_to_lean.nim:65`). No proof is emitted and no counterexample is claimed.

### 3.5 `..` / `..<` slice

`s[a..b]` and `s[a..<b]` arrive as `BracketExpr(seq, Infix(".."|"..<", ...))` (measured with Nim 2.2.10). `convertBracketExprCanon` keeps the index as the last child and builds `irCall("[]", [seqExpr, idxExpr])` (`ast_to_ir.nim:1080-1091`). The `..`/`..<` infix is `boUnsupported` and loss-marked (`:355`, `:117-121`), and every `irCall` is rejected by the canonical renderer (`canonical_verification.nim:257-259`). Status: **not directly provable**. The bracket arm exists for plain index access, not slice construction.

### 3.6 `..` / `..<` range-for

The NimNode range recognizer accepts the operator spellings `".."`, `"..<"`, `"<..<"` via `opStrVal` (`ast_to_ir.nim:799-801`) and builds the loop condition with `condOp = if rangeOp == "..": boLe else: boLt` (`:853`). Measured with the pinned compiler through `parseStringAST` (the spelling the Canon pipeline sees): untyped `0 ..< n` yields `Infix Ident "..<"`; no rewrite to `..` was reproduced on this toolchain. Both range spellings therefore translate.

The NimNode path has production callers, not test-only ones: `axiom_pragmas_macros.nim:687` and `:778` call `convertFuncDef(def)`. Both ranges are translated loss-free there — `0 ..< n` → `boLt`, `0 .. n` → `boLe` — as fixed by #118 and covered by `tests/trusted/test_ast_to_ir.nim` (Tests 7–8).

The Canon path used by the external materializer (`src/infrastructure/external_ir_materializer.nim:544` calls `axiomBodyCanon`) still drops every `ckForStmt` region without translating it (`markRegionDrop`, `ast_to_ir.nim:1341-1347`); the resulting definition is `translationLossFree=false`, and the region-drop warning is recorded rather than the loop being asserted. So for external subjects a range-for is **incomplete** — absent from the IR, not refuted. On the NimNode path the same source is translated faithfully, but an `irLoop` still has no arm in the canonical lowering (`canonical_verification.nim:257-259`), so no denotation is emitted: the construct is **not directly provable** there. The status is "translated honestly", not "proved".

### 3.7 shl / shr / unknown infix

`shl` maps to `boShl` and `shr` to `boShr`; every other infix falls to `boUnsupported` (`ast_to_ir.nim:355`). SemanticProfileV1 declares shifts unsupported (`spShiftUnsupported`, `src/core/trusted/semantic_profile.nim:51`, `:117`). Since #118 all three are loss-marked at the conversion boundary (`ast_to_ir.nim:117-121`) and the materializer refuses a loss-free claim that contains them. The canonical lowering returns `""` for all three (`canonical_verification.nim:231`); `irBinOpToLean` maps them to `UNSUPPORTED` (`ir_to_lean.nim:63-65`). Replay refuses them too: `none(ConcreteValue)` (`src/verification/counterexample_replay.nim:413-414`). Status: **not directly provable**, and not refutable through replay.

Renderer divergence, recorded not resolved: `irExprToLean` still spells shifts as `<<`/`>>` (`ir_to_lean.nim:226-227`). The canonical I6 obligation renderer is `renderLeanForFuncDef` via `lowerIRExprToLean` (`canonical_verification.nim:481-509`); this document claims no status from the auxiliary renderer, and any future obligation use of it must first reconcile the divergence.

## 4. Refuted is per obligation, not per construct

The replay evaluator assigns `none` to every refused operation (`counterexample_replay.nim:413-414`), so it cannot manufacture a refutation for an unsupported construct. Conversely, a supported construct is not automatically proved: proving requires an emitted theorem and kernel acceptance. Therefore:

- no row in §3 is "refuted";
- "refuted" is earned only by a concrete replay against a specific proposition;
- absence from the VKD numerator is not a refutation (see §5).

## 5. VKD is not the boundary oracle

`toEvidenceBundle` seeds `solverProved = z3Passed` and `translationProved = leanVerified` (`src/core/trusted/evidence_calculus.nim:86-93`). `admissibleEvidence` is exactly `solverProved and translationProved` (`:110-116`), and `isVkdAdmissible` invokes it (`src/core/proof/proof_integrity.nim:178-182`). No `translationLossFree` term appears in either predicate. VKD admits only `certGreen` (`verification_density.md:170-172`).

Consequences:

- a boundary construct keeps a VKS symbol out of the numerator (contribution 0); it never turns the symbol into refuted;
- a loss-free symbol is not automatically provable (`move` is loss-free at conversion and still unprovable);
- the loss bit measures translation fidelity; it is not a truth value. #118 makes it truthful at the conversion boundary; it does not make it an oracle.

## 6. Changing a status

Moving a construct to **directly provable** requires all four: an IR arm, a non-empty Lean denotation, a kernel-checkable obligation path, and a negative control updated with the change. A status change is a contract amendment, not a documentation cleanup. The product non-goals remain as ratified (`productization_contract.md:21`).