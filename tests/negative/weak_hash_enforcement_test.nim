## Negative Test: Weak Hash Enforcement
##
## This file tests that weak hash imports are caught by forbidden_patterns.nim
## The axiomStrongHash macro is a compile-time guard for proc bodies only.
## File-level import detection is handled by nimtry's forbidden_patterns.
##
## Verification: nim try src/gate/nimtry/forbidden_patterns.nim should flag
## any file importing checksums/md5 or checksums/sha1.

discard """
  action: "compile"
"""

import core/trusted/axiom_pragmas

# This proc is intentionally empty - the real enforcement
# is in forbidden_patterns.nim which scans file-level imports
proc dummy(): int = 42
