## DEBT#287 negative fixture — unknown-layer import.
##
## Sandbox layout (scanned only when AXIOM_ROOT points at this directory):
## src/mystery/ maps to no registered layer in inferLayer, so the layer
## enforcement gate must FAIL closed on this file instead of silently
## skipping it. Never imported by anything; not part of the real src/ tree.
##
## nim-check: skip — fixture payload for check-layer-negative, deliberately
## never compiled (its import does not resolve outside the sandbox).
import core/types
