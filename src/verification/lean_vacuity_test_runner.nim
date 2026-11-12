import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

## Test runner for ax_vacuity_check adversarial validation.
##
## Keeps all non-hermetic file I/O out of `tests/unit/` so that the unit test
## file itself remains hermetic and shallow. The runner is an I/O boundary and
## is allowed to create/remove temporary Lean artifacts and invoke the Lean
## compiler.

import std/os
import verification/lean_lsp_compiler
import core/trusted/axiom_pragmas
import core/trusted/stdlib_shield
import infrastructure/logging_facade

# axiomIoBoundary

const
  TestArtifactBase* = "tests/tmp/ax_vacuity_check_test"

type
  TestCaseKind* = enum
    tckCleanWithVacuity
    tckSorryInProof
    tckUnauthorizedAxiom
    tckCleanWithoutVacuity

func buildLeanSource(kind: TestCaseKind): string {.raises: [].} =
  var imports = "import Std\n"
  if kind in {tckCleanWithVacuity, tckSorryInProof, tckUnauthorizedAxiom}:
    imports.add("import ax_vacuity_check\n")

  var mainProof = ""
  case kind
  of tckCleanWithVacuity, tckCleanWithoutVacuity:
    mainProof = "  rfl"
  of tckSorryInProof:
    mainProof = "  sorry"
  of tckUnauthorizedAxiom:
    mainProof = "  exact (False.elim badAx)"

  var axiomDecl = ""
  if kind == tckUnauthorizedAxiom:
    axiomDecl = "axiom badAx : False\n\n"

  var vacuityTheorem = ""
  if kind in {tckCleanWithVacuity, tckSorryInProof, tckUnauthorizedAxiom}:
    vacuityTheorem = """

theorem test_safety_vacuity_check : True := by
  ax_vacuity_check test_safety
"""

  result = imports & """
namespace AdversarialTest

""" & axiomDecl & """
theorem test_safety : 1 = 1 := by
""" & mainProof & vacuityTheorem & """

end AdversarialTest
"""

proc cleanTestArtifacts*() {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let dir = parentDir(TestArtifactBase)
  if dirExists(dir):
    for kind in TestCaseKind:
      let base = TestArtifactBase & "_" & $kind
      try: safeRemoveFile(base & ".lean")
      except CatchableError as e:
        logWarn("lean_vacuity_test_runner", "cleanTestArtifacts remove " & base & ".lean failed: " & e.msg)
      try: safeRemoveFile(base & ".negative.lean")
      except CatchableError as e:
        logWarn("lean_vacuity_test_runner", "cleanTestArtifacts remove " & base & ".negative.lean failed: " & e.msg)

proc runVacuityCompilerCase*(kind: TestCaseKind): LeanCompilerResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let dir = parentDir(TestArtifactBase)
  if dir.len > 0 and not dirExists(dir):
    createDir(dir)
  let artifactPath = TestArtifactBase & "_" & $kind & ".lean"
  let source = buildLeanSource(kind)
  result = verifyGeneratedLeanSourceWithCompiler(source, artifactPath)

{.pop.}
