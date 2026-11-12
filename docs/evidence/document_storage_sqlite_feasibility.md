# Document Storage Strategy: SQLite Feasibility Analysis

> **Date**: 2026-06-03  
> **Trigger**: Comparative analysis with tinyhumansai/openhuman trending project  
> **Method**: Context7 MCP (`/sqlite/sqlite`, `/tinyhumansai/openhuman`), FetchURL (sqlite.org), WebSearch, local codebase audit  
> **Decision**: Retain Markdown as SSOT; do not migrate to SQLite.  
> **Reference**: AGENTS.md §0.2 (First-Principles), §1.1 (Language Ban), §2.8 (Git Workflow)

---

## 1. Executive Summary

This document records the exhaustive investigation into whether Axiom's markdown-based documentation system (intents, context, and records) should migrate to SQLite for long-term benefit. The conclusion, grounded in Context7 official documentation and Axiom's First-Principles (Ideal · Elegant · Fundamental · Deterministic), is **negative**: SQLite full migration is not advantageous. Axiom already follows the same Markdown-SSOT philosophy as the trending openhuman project.

---

## 2. Investigation Trigger

The investigation was initiated after observing tinyhumansai/openhuman (11,600+ GitHub stars, Product Hunt #1), which appeared to use a relational database for project context management. The core question: *If this is trending, should Axiom adopt a similar approach?*

---

## 3. openhuman Architecture Analysis (Context7 Evidence)

### 3.1 Misconception Correction

**openhuman did NOT replace Markdown with SQLite.** openhuman uses a **Dual-Storage (Hybrid)** architecture:

```
source adapters → canonicalize → chunker → content_store → store → score → summary trees → retrieval
                                    ↓                        ↓
                              atomic .md files          SQLite index
                              (wiki/ directory)         (memory_tree/chunks.db)
                                   ↑ SSOT                    ↑ .gitignore
```

### 3.2 Storage Layout

| Path | Content | Role |
|------|---------|------|
| `wiki/` | Markdown vault (Obsidian-compatible) | **Human-readable SSOT** |
| `memory_tree/chunks.db` | Chunks, scores, summaries, entity index, jobs, hotness | **SQLite derived index** (query/search) |

### 3.3 Public API

```typescript
// SSOT access (primary)
await aiReadMemoryFile('github/summary.md');
await aiWriteMemoryFile('notes/today.md', '# Notes\n- ...');

// Index query (internal/secondary)
await memoryQueryNamespace('github', 'query', 10);
await memoryGraphQuery('github', 'author', 'authored');
```

### 3.4 Why openhuman Needs SQLite

| openhuman Need | Solution | Axiom Situation |
|----------------|----------|-----------------|
| 118 integrations feeding unstructured data (email, chat, docs) | canonicalize → Markdown + chunking | Axiom docs are **already structured markdown** |
| 1 billion tokens of personal data | SQLite + FTS5 + vector search | Axiom is **1.9 MB (~0.5M tokens)** — `grep` is sufficient |
| Real-time semantic search / entity graph | `UnifiedMemory` (SQLite + vector + graph) | Agents read sequentially; no real-time search need |
| User edits Markdown vault directly | `wiki/` as Obsidian SSOT | Developers/agents edit `.md` directly |

**Key insight**: openhuman's SQLite layer is a **derived index** for fast search over massive unstructured ingestion. Axiom's documents are already structured, small (1/500th the scale), and consumed sequentially by agents.

---

## 4. First-Principles Evaluation

Applied per AGENTS.md §0.2.

| Principle | Markdown Retention | SQLite Migration | Winner |
|-----------|-------------------|------------------|--------|
| **Ideal** (compile-time prevention) | Neutral — runtime data | Neutral — runtime data | = |
| **Elegant** (language-native tools) | `cat`, `grep`, `diff`, `readFile` are native | Requires SQL bindings, schema knowledge | Markdown |
| **Fundamental** (no hardcoded exceptions) | Filesystem is SSOT, no exceptions | Schema migration, sync logic, dump pipelines required | Markdown |
| **Deterministic** (identical input → identical output) | UTF-8 text, byte-identical, `git diff` works | Binary instability (VACUUM, page allocation, WAL) | Markdown |

Additional factors:
- **Git workflow integration**: Native for markdown; destructive for SQLite (rebase-only policy §2.8).
- **Human-readable SSOT**: AGENTS.md is the "constitution"; a DB is an opaque blob.
- **Agent accessibility**: 7+ modules read `.md` via `ReadFile`/`cat`. SQL requires retraining toolchain.
- **Fallback protocol**: The verification history fallback SSOT must remain human-readable markdown.

---

## 5. SQLite Official Documentation (appfileformat.html)

SQLite lists 12 advantages as an application file format. Applicability to Axiom:

| # | Advantage | Axiom Applicability |
|---|-----------|---------------------|
| 01 | Simplified app development | ❌ `readFile` (1 line) → SQL+schema+N lines. Complexity increases. |
| 02 | Single-file documents | ⚠️ Would sacrifice per-file `git diff`/`blame`. |
| 03 | High-level query language | ✅ Potentially useful for `DEBT_REGISTRY` (621 rows). |
| 04 | Accessible content | ❌ Agents are optimized for markdown, not SQL. Fallback protocol requires markdown. |
| 05 | Cross-platform | 🟡 Markdown is equally cross-platform (UTF-8 text). |
| 06 | Atomic transactions | 🟡 Git commit already provides atomicity. |
| 07 | Incremental/continuous updates | ❌ 1.9 MB scale makes this irrelevant. |
| 08 | Easily extensible | ❌ Markdown adds files freely; SQLite requires schema migrations. |
| 09 | Performance | ❌ 1.9 MB loads faster into memory than SQL query overhead. |
| 10 | Concurrent multi-process use | 🟡 Read-only markdown has no conflicts; Git serializes writes. |
| 11 | Multiple programming languages | ❌ Axiom is Nim-only (Language Ban §1.1). |
| 12 | Better applications | 🟡 Hierarchical directories already express namespaces clearly. |

---

## 6. Comparative Matrix: openhuman vs. Axiom

| Dimension | openhuman | Axiom (Current) | If Axiom Adopted openhuman Pattern |
|-----------|-----------|-----------------|-----------------------------------|
| Data nature | Unstructured → needs canonicalization | Already structured markdown | No change needed |
| Data scale | 1 billion tokens | 1.9 MB (~0.5M tokens) | **1/500 scale** |
| SSOT | Markdown (`wiki/`) | Markdown (`docs/`) | **Identical pattern** |
| Search index | SQLite (`chunks.db`) + FTS5 + vector | None (`grep`) | Optional addition |
| Agent access | `aiReadMemoryFile('.md')` primary | `ReadFile('.md')` | Identical pattern |
| Git tracking | `.md` committed, `.db` in `.gitignore` | `.md` committed | Identical pattern |
| Human editing | Obsidian vault | VS Code / IDE | Identical pattern |

**Conclusion**: Axiom already follows the same Markdown-SSOT philosophy as openhuman. The difference is scale: openhuman needs SQLite for 1B tokens of unstructured data; Axiom does not for 1.9 MB of structured docs.

---

## 7. Risk Analysis: SQLite Full Migration

| Risk Area | Severity | Description |
|-----------|----------|-------------|
| Git workflow destruction | Critical | `git diff`, `blame`, PR reviews become binary/dump output. Conflicts with rebase-only policy. |
| Agent toolchain rewrite | Critical | 7+ modules and gate runners need SQL interface. Blast radius: 20+ files. |
| Deterministic diff loss | High | SQLite binary non-determinism breaks byte-level reproducibility. |
| Human-readable SSOT loss | High | Constitution (AGENTS.md) becomes opaque. |
| Schema migration burden | Medium | Free-form markdown → rigid `ALTER TABLE` cycles. |

---

## 8. Long-Term Scenarios

| Scenario | Markdown Handling | SQLite Handling | Verdict |
|----------|-------------------|-----------------|---------|
| 10× growth (19 MB, 1,050 files) | `grep`/`rg` still sufficient. Git diff/blame unaffected. | SQLite trivial for size, but Git issues remain. | Markdown wins |
| Relational query demand (e.g., DEBT dependency graph) | Manual parsing, limited. | SQL joins superior. | **Derived index** (not full migration) |
| Multi-agent concurrent writes | Git serializes; agents are read-mostly. | Transactions help, but conflicts with human-commit philosophy. | Markdown wins |

---

## 9. Decision Record

| Item | Value |
|------|-------|
| **Decision** | Retain Markdown as sole SSOT. Do not adopt SQLite for documentation storage. |
| **Rationale** | Scale (1.9 MB), First-Principles compatibility, Git workflow preservation, agent toolchain stability. |
| **openhuman insight** | openhuman also keeps Markdown as SSOT; SQLite is only a derived index. Axiom already follows the correct pattern without needing the index layer. |
| **Exception** | If structured query demand becomes frequent for specific files (e.g., `DEBT_REGISTRY.md`), a **build-time derived SQLite index** (`.gitignore`, deterministic regeneration) may be evaluated — identical to openhuman's `wiki/` + `chunks.db` pattern. |
| **Approved** | 2026-06-03 |

---

## 10. Evidence Registry

| Evidence | Source | Retrieval Method |
|----------|--------|------------------|
| SQLite Application File Format (12 advantages) | SQLite official docs | FetchURL: https://sqlite.org/appfileformat.html |
| SQLite JSON1/JSONB/FTS extensions | Context7 `/sqlite/sqlite` | `query-docs` |
| openhuman Memory Tree architecture | Context7 `/tinyhumansai/openhuman` | `query-docs` |
| openhuman dual-storage (`wiki/` + `chunks.db`) | Context7 `/tinyhumansai/openhuman` | `query-docs` |
| openhuman public API surface | Context7 `/tinyhumansai/openhuman` | `query-docs` |
| Axiom docs scale | Local measurement | `find` + `wc` + `du` |
| Agent markdown read patterns | Source audit | `grep` on `src/` |
| Axiom First-Principles | AGENTS.md §0.2 | `ReadFile` |
| Git rebase-only policy | AGENTS.md §2.8 | `ReadFile` |

---

*This document is the SSOT for the document storage strategy decision. If future scale or requirements change, revise via the architectural decision record process per AGENTS.md §2.1.*
