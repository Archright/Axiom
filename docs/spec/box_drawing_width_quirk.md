# Box-Drawing Character Width Quirk

**Discovered:** 2026-07-20 during `ax report` UX overhaul

## Summary

Box-drawing characters (U+2500-U+257F: ─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼) are **half-width** (display width 1) in standard Linux terminals, despite being 3-byte UTF-8 sequences (E2 94 XX).

## Evidence

```
$ nim c -r test.nim  # repeat("─", 60) output
┌────────────────────────────────────────────────────────────┐
→ Terminal width = 62 (1 + 60×1 + 1), NOT 124 (2 + 60×2 + 2)
```

## Impact

Adding U+2500-U+257F to a `displayWidth` fullwidth range (alongside CJK 0x3000-0x9FFF) causes all box rendering to **double-count** character widths, breaking layout alignment.

## Correct Behavior

- `displayWidth("─")` = 1 (half-width)
- `displayWidth("│")` = 1 (half-width)
- `displayWidth("가")` = 1 (Korean Hangul, half-width)
- `displayWidth("Ａ")` = 2 (Fullwidth Latin, 0xFF01-0xFF5E)

## Rule

Box-drawing characters MUST NOT be included in fullwidth detection ranges. Use byte-length (`.len`) for box rendering arithmetic when all characters in the box are ASCII or half-width.
