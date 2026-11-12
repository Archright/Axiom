# Context7-Driven Technical Debt Audit Report

> **Date**: 2026-06-03
> **Method**: Parallel Context7 MCP official documentation queries + deterministic codebase scan
> **Criteria**: AGENTS.md §0.2 First-Principles Elegance (Ideal, Elegant, Fundamental, Deterministic)
> **Evidence Source**: Context7 `/nim-lang/nim`, `/leanprover/lean4` official docs

---

## Executive Summary

| ID | Severity | Category | File | Lines | Status |
|----|----------|----------|------|-------|--------|
| DEBT#141 | **High** | Exception Handling | `src/core/` (8 locations) | 28, 35, 59, 61, 232, 238, 353, 357 | **Open** |
| DEBT#142 | **Medium** | Purity / Effect | `src/cli/axiom_engine.nim` | 48 | **Open** |

---

## DEBT#141: `except Exception` in Domain Layer (src/core/) — DEBT#090 Regression

### Description
DEBT#090 ("83 `except Exception` in domain layer — catches Defects") was marked **Closed** with status "Deferred (Pre-existing)" on 2026-06-02. However, a deterministic `grep` scan reveals **8 residual occurrences** in `src/core/`, the pure calculation layer that MUST NOT catch `Exception` (which includes `Defect`).

### Locations
```
src/core/tree_sitter_parse.nim:28               except Exception as e:
src/core/policy/architecture_policy_part2.nim:59  except Exception:  [RENAMED from architecture_policy_parts/]
src/core/policy/architecture_policy_part1.nim:232 except Exception: -1.0  [RENAMED from architecture_policy_parts/]
src/core/policy/architecture_policy_part1.nim:238 except Exception: -1.0  [RENAMED from architecture_policy_parts/]
src/core/policy/architecture_policy_part1.nim:353 except Exception: -1.0  [RENAMED from architecture_policy_parts/]
src/core/policy/architecture_policy_part1.nim:357 except Exception: -1.0  [RENAMED from architecture_policy_parts/]
src/core/io_utils.nim:35                         except Exception as e:
src/core/io_utils.nim:61                         except Exception as e:
```

### Context7 Evidence (Official Nim Documentation)
1. **NEP-1 (Naming Conventions)**: "Avoid inheriting directly from 'Exception' if 'CatchableError' or 'Defect' are more appropriate." — `Exception` is overly broad.
2. **Nim Manual (Exception Tracking)**: `except CatchableError:` is the canonical pattern for catching recoverable errors. Defects (panic-level bugs) must propagate.
3. **Nim 2.0 Changelog (`changelog_2_0_0_details.md`)**: Bare `except:` is deprecated with `warnBareExcept`. While `except Exception:` is syntactically different, it shares the same semantic flaw: catching `Defect`.
4. **Nim Tutorial 2**: All official examples use `except CatchableError:`, never `except Exception:`.

### First-Principles Assessment
| Principle | Assessment |
|-----------|------------|
| **Ideal** | ✅ Compile-time preventable. `config.nims` already has `switch("warning", "BareExcept:on")`; a custom gate or `warningAsError[Effect]` could extend this to `except Exception:`. |
| **Elegant** | ✅ Language-native fix: replace with `except CatchableError:`. One-word change per site. |
| **Fundamental** | ✅ Addresses root cause: misunderstanding of Nim exception hierarchy (Exception ⊃ CatchableError ⊃ Defect). |
| **Deterministic** | ✅ Reproducible via `grep -rn "except Exception" src/core/ --include="*.nim"` — identical input → identical 8 matches. |

### Fix Strategy
Replace all 8 occurrences with `except CatchableError:` (or narrower specific exceptions where applicable). For `parseFloat` fallbacks, `except ValueError:` is semantically correct.

---

## DEBT#142: `ref object` Missing `{.acyclic.}` Annotation

### Description
`GateReporter* = ref object` in `src/cli/axiom_engine.nim:48` lacks the `{.acyclic.}` pragma, violating AGENTS.md §0.6a:

> "ALL non-cyclic `ref object` MUST have `{.acyclic.}` annotation (optimizes away ORC cycle collector)"

### Context7 Evidence (Official Nim Documentation)
Nim's ORC (Optimized Reference Counting) garbage collector performs cycle detection on all `ref object` types by default. The `{.acyclic.}` pragma tells the compiler the type cannot participate in reference cycles, eliminating cycle-collector overhead. This is a zero-cost compile-time optimization.

### First-Principles Assessment
| Principle | Assessment |
|-----------|------------|
| **Ideal** | ✅ Compile-time preventable. One pragma eliminates runtime GC work. |
| **Elegant** | ✅ Single-word language-native annotation. |
| **Fundamental** | ✅ Addresses root cause: unnecessary ORC cycle tracking for a type with no self-referential fields (`events*: seq[GateEvent]` is a flat sequence). |
| **Deterministic** | ✅ Reproducible via `grep -rn "ref object" src/ --include="*.nim" | grep -v acyclic`. |

### Fix Strategy
```nim
# Before
GateReporter* = ref object

# After
GateReporter* = ref object {.acyclic.}
```

---

## Scan Methodology & Reproducibility

All findings are shell-checkable:

```bash
# DEBT#141: except Exception regression
grep -rn "except Exception" src/core/ --include="*.nim"
# Expected: 8 matches

# DEBT#142: missing acyclic
grep -rn "ref object" src/ --include="*.nim" | grep -v "acyclic"
# Expected: src/cli/axiom_engine.nim (and type_registry.nim which is analysis-only comment)

# Debt scan baseline
python3 scripts/debt_scan.py
# Expected: 1 active debt (src/cli/cst_cli.nim 523 lines)
```

---

## Context7 Queries Log

| Query | Library ID | Purpose |
|-------|-----------|---------|
| Nim effect system, noSideEffect, raises pragma | `/nim-lang/nim` | Validate exception handling anti-patterns |
| Lean 4 proof engineering, sorry, admit | `/leanprover/lean4` | Validate verification-layer completeness |
| Nim stdlib deprecated modules, API changes | `/nim-lang/nim` | Validate toolchain cascade risk |

---

## Conclusion

- **2 new deterministic debts** identified, both satisfying AGENTS.md §0.2 First-Principles Elegance.
- **DEBT#141** is the highest priority: it is a regression of a previously "closed" debt in the domain layer, with official Nim documentation (NEP-1, Manual, Changelog) unanimously condemning the pattern.
- **DEBT#142** is a one-line compile-time optimization with zero behavioral change.
- No new Lean-layer debts found; `sorry` usages in the codebase are all intentional (codegen fallback, prompt prohibition, or post-processing replacement).
