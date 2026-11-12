# nim-check: skip
# Deliberate COMPILE-FAILURE probe (B1-EXTENSION Task 2). It records which
# same-class field-name pairs Nim 2.2.10 accepts in ONE object type:
#   T1: `Foo` + `foo`   (differ only by case)   -> ACCEPTED (control)
#   T2: `fooBar` + `foo_bar` (underscore variant) -> "attempt to redefine" (REJECTED)
#   T3: `ABC` + `abc`   (differ only by case)   -> ACCEPTED (control)
# The compiler stops at the first error, so T2's line is the recorded verdict;
# T1/T3 being reachable-and-accepted is implied by the error landing at T2.
# This asymmetry is what makes the case-insensitive mis-targeting experiment
# (p2_case_modes.nim, type `pair`) declarable at all. This file is compiled by
# repro.sh purely to record the compiler's verdict; it is never executed and
# must not resolve any imports (none are present).

type
  T1 = object
    Foo: string
    foo: string

type
  T2 = object
    fooBar: string
    foo_bar: string

type
  T3 = object
    ABC: string
    abc: string
