# Landing Script-Scan Quirk (Unicode Script allowlist over the landing diff)

> The landing-only `script-scan` dimension fails any landing diff that ADDS a Unicode code point outside {ASCII, Latin, Greek, Common, Inherited}, so Korean (Hangul) prose added under any scanned path can block `publication-integrity` even when the same file already contains Korean lines on the base.

## Scope

- Job: `script-scan` in `.github/workflows/publication-integrity.yml`.
- Venue: `merge_group`, `schedule`, and `workflow_dispatch` only. The `pull_request` venue is preflight and runs `{secret-scan}` only, so a branch can look green before landing and still fail here.
- Base: `github.event.merge_group.base_sha` on `merge_group`; otherwise `HEAD~1`. Head: `github.sha`.
- Mechanics: the job compiles `tools/ci/publication_script_eval.nim` (with the lockfile-pinned `checksums` package) and evaluates `compliance/policy/script-scan-policy.yml`.
- Verdict set: PASS / FAIL / UNKNOWN (exit 0 / 1 / 2). UNKNOWN is blocking, never a pass.

## The rule

The policy claim: "the landing diff introduces no Unicode code point whose Script property is outside {ASCII range, Latin, Greek, Common, Inherited}, except exact-path product i18n exemptions".

Consequences:

- Korean (Hangul) text on a line you ADD to any scanned path (`docs/**`, `data/**`, and every other text path in the landing diff) produces a violation and fails the landing check.
- Pre-existing Korean lines already on the base are not part of the diff and do not fail.
- Editing an existing non-Latin line emits it as a newly added line and fails.
- The only exact-path exemption declared today is `data/i18n/ko.json`.
- Common/Inherited punctuation is allowed, including U+2014 em dash, U+3002, U+3001, U+30FC, and emoji.

The detector is `[^\x00-\x7F\p{Latin}\p{Greek}\p{Common}\p{Inherited}]`, evaluated by the default ripgrep engine (Unicode 15.0) over the collected added lines.

## Deterministic local preflight (NON-AUTHORITATIVE)

This command mirrors the CI evaluation. It is a convenience only: the CI `script-scan` job remains the single authority, and a local PASS does not by itself prove the landing check will pass.

```bash
CHECKSUMS_VER="$(jq -r '.packages.checksums.version // empty' nimble.lock)"
CHECKSUMS_SHA1="$(jq -r '.packages.checksums.checksums.sha1 // empty' nimble.lock)"
[ -n "$CHECKSUMS_VER" ] && [ -n "$CHECKSUMS_SHA1" ] || { echo "FATAL: cannot resolve checksums pin from nimble.lock" >&2; exit 1; }

nim c --hints:off --warnings:off \
  --skipParentCfg --skipProjCfg --skipUserCfg --noNimblePath \
  --path:. --path:src \
  --path:"$HOME/.nimble/pkgs2/checksums-${CHECKSUMS_VER}-${CHECKSUMS_SHA1}" \
  --nimcache:build/nimcache/vsi_script_eval \
  -o:build/vsi_script_eval tools/ci/publication_script_eval.nim

./build/vsi_script_eval \
  --policy compliance/policy/script-scan-policy.yml \
  --rg <ripgrep-14.1.0> \
  --head "$(git rev-parse HEAD)" \
  --base "$(git merge-base origin/main HEAD)" \
  --repo-root . \
  --out /tmp/report_script_scan.json
```

- `--rg <ripgrep-14.1.0>` is a placeholder: substitute the path to a binary whose `rg --version` reports 14.1.0. CI pins the 14.1.0 musl release artifact and verifies its sha256 `f84757b07f425fe5cf11d87df6644691c644a5cd2348a2c670894272999d3ba7` before extraction.
- The base above is the merge-base of `origin/main` and `HEAD`, matching the landing intent. The evaluator fails closed if the base is not an ancestor of head or if `merge-base(base, head)` differs from the declared base.
- The workflow fails closed when the lockfile-pinned package is missing at `$HOME/.nimble/pkgs2/checksums-${CHECKSUMS_VER}-${CHECKSUMS_SHA1}` (it requires `checksums/sha2.nim` there).
- `--head` must be a 40-hex commit. Passing the literal string `HEAD` yields UNKNOWN (exit 2, "head is not a 40-hex commit sha"); measured 2026-11-21 with the evaluator built at `be6c14c`. Use `git rev-parse HEAD` as above.
- Exit 0 = PASS, 1 = FAIL, 2 = UNKNOWN. Treat UNKNOWN as blocking.

## Recorded incidents

Facts only, no attribution.

### PR #323 - merge group d8dc2527c89edaa71f5a996ebe4c2ff12a78f0f0 - run 44894338989

- `publication-integrity` failed at the landing venue.
- `script-scan` reported 318 violations in `docs/agents/axiom_admission_verifier_ops.md` and 428 in `data/ci_optimization/app_verdict_attribution_2026-11-21/summary.json` (746 rows in total, per the fix commit message).
- Fixed by commit `25e3681d` (ASCII rewrite of the added prose only; pre-existing Korean lines were left untouched); the landed branch carries the rebased equivalent `9cb9e449` (identical patch-id). Landed as merge commit `572c0a4b`.

### PR #325 - merge group 9e29841c5cf00a74bcf3176819c0afd8f0d834b4 - run 44896706396

- `publication-integrity` failed on `data/ci_optimization/merge_queue_concurrency_2026-11-21_after_n10/summary.json`, which carried 135 Hangul-bearing added lines.
- Fixed by commit `deca31a`. Landed as merge commit `bb77bd75`.

## Contributor rule of thumb

- Any line you add under a scanned path must be ASCII, Latin, Greek, Common, or Inherited script.
- To quote non-Latin text, use ASCII escapes (`\uXXXX` in JSON, HTML numeric entities) or keep the text in an exact-path exempt resource. The policy's declared limitations state that Unicode escapes and numeric entities are ASCII and are not detected.
- Do not "fix" a pre-existing non-Latin line unless you intend to rewrite it in ASCII: the edit makes it an added line and the same rule applies.

## Related SSOT

- [compliance/policy/script-scan-policy.yml](../../compliance/policy/script-scan-policy.yml)
- [.github/workflows/publication-integrity.yml](../../.github/workflows/publication-integrity.yml)
- [tools/ci/publication_script_eval.nim](../../tools/ci/publication_script_eval.nim)
- [docs/spec/ci_provider_failover_quirks.md](ci_provider_failover_quirks.md)

## Undeclared leak classes (audit 2026-11-22)

The detector `[^\x00-\x7F\p{Latin}\p{Greek}\p{Common}\p{Inherited}]` is a negated Unicode class: it can match only code points that DECODE to a script outside the allowlist, so a payload is invisible when the bytes are not valid UTF-8, when the characters are Script=Common or Inherited despite being invisible or lookalike, or when the non-Latin text is carried in ASCII. Rows are detector-level for the pinned ripgrep 14.1.0; "where declared" cites `declaredLimitations` in `compliance/policy/script-scan-policy.yml`.

| leak class | example | detected? | where declared |
|---|---|---|---|
| Non-UTF-8 encodings | Japanese prose in EUC-JP, Shift-JIS, CP932, ISO-2022-JP, UTF-16LE without BOM | per 10 strings: UTF-8 10/10, EUC-JP 7/10, Shift-JIS 4/10, CP932 4/10, ISO-2022-JP 0/10, UTF-16LE 0/10; the non-zero non-UTF-8 counts are accidental byte coincidences | partial: "Non-UTF-8 text is UNKNOWN" covers only the lines `isValidUtf8` sees |
| UTF-16LE with BOM | leading `FF FE` | yes: ripgrep BOM-sniffs and transcodes | `declaredLimitations` (same entry) |
| Invisible Common/Inherited | tag characters U+E0000-U+E007F, U+202E, U+200D, U+200B, U+00AD | no | undeclared |
| Common-script alphanumerics | U+1D400-U+1D7FF (e.g. U+1D407 MATHEMATICAL BOLD CAPITAL H), U+2460-U+24FF (e.g. U+24B6 CIRCLED LATIN CAPITAL LETTER A) | no | undeclared |
| Fullwidth Latin | U+FF21-U+FF3A | no (Script=Latin) | undeclared |
| Percent-encoded UTF-8 | `%ED%95%9C%EA%B8%80` (decodes to Hangul) | no (ASCII on the wire) | undeclared |
| HTML numeric entities, `\uXXXX` escapes | `&#54620;`, `&#xD55C;` | no (ASCII on the wire) | `declaredLimitations`: "HTML numeric entities and Unicode escapes are ASCII" |
| Greek prose | U+03C0, U+0394, U+03A9, U+03B1, U+03A3 | no by design: the allowlist exists so mathematical notation does not produce false positives | `declaredLimitations`: "Greek prose is not detected" |

Consequences:

- A tag-character sequence can carry hidden ASCII text that renders as nothing, and bidi/format controls can reorder a line without adding a visible non-Latin code point.
- The evaluator is not fail-open on tool errors: `publication_script_eval.nim` maps `ripgrep` exit code 2 to UNKNOWN in the `else: unknowns.add("ripgrep exited ...")` branch, and UNKNOWN blocks. The shell idiom `if rg -q ...; then fail; fi` WOULD be fail-open because it reads exit 2 as "no match"; the `script-scan` job runs the Nim evaluator, not that idiom.
- Invalid UTF-8 on added lines is already fail-closed (`isValidUtf8` -> UNKNOWN), so the measured non-UTF-8 residual is limited to paths that are transcoded or skipped (binary-sniffed, submodule, quoted path) before the scan.
- The normative limitations list is `declaredLimitations` in `compliance/policy/script-scan-policy.yml`, a merge-admission trust-surface path; this document records the gap only, and the amendment belongs to issue #359 ([english-only] Extend publication-integrity: tree mode, NLID dimension, escape decoding, NEG-SKIP-01).
