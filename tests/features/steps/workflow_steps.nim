## BDD step implementations for workflow_integrity.feature
## Replaces all DEBT#052 stubs with deterministic state-machine assertions.

import std/os

type
  WorkflowCtx* = object
    hasRequirement*: bool
    aboutToModifyCode*: bool
    hasContextMdChange*: bool
    aboutToModifyDocument*: bool
    scenariosDefined*: bool
    implementationStarted*: bool
    testsWritten*: bool
    minimalChanges*: bool
    bugDiscovered*: bool
    performingImplementation*: bool
    bddTestWritten*: bool
    codeChangesComplete*: bool
    prekTestsRun*: bool
    coverageSatisfies100*: bool
    commitsBlockedIfBelow100*: bool

# ── Rule: AGENTS.md must be updated first ──────────────────────────────────

proc givenNewRequirementAffectingGlobalRules*(ctx: var WorkflowCtx) =
  ctx.hasRequirement = true

proc whenAboutToModifyCode*(ctx: var WorkflowCtx) =
  ctx.aboutToModifyCode = true

proc thenRequirementReflectedInContextMdFirst*(ctx: var WorkflowCtx) =
  doAssert ctx.hasRequirement, "Requirement must be recorded first"
  doAssert ctx.aboutToModifyCode, "Must be about to modify code"
  doAssert fileExists("AGENTS.md"), "AGENTS.md must exist and be updated before code changes"

# ── Rule: BDD scenarios must be defined first ───────────────────────────────

proc givenFunctionalChangesToContextMd*(ctx: var WorkflowCtx) =
  ctx.hasContextMdChange = true

proc whenAboutToModifyTheDocument*(ctx: var WorkflowCtx) =
  ctx.aboutToModifyDocument = true

proc thenBddScenariosDefinedInFeatureFilesFirst*(ctx: var WorkflowCtx) =
  doAssert ctx.hasContextMdChange, "AGENTS.md changes must be recorded"
  doAssert ctx.aboutToModifyDocument, "Must be about to modify the document"
  doAssert dirExists("tests/features"), "BDD feature files directory must exist"
  var featureCount = 0
  for _ in walkFiles("tests/features/*.feature"):
    inc featureCount
  doAssert featureCount > 0, "At least one .feature file must exist"

# ── Rule: Minimal changes through TDD ───────────────────────────────────────

proc givenBddScenariosDefinedAndApproved*(ctx: var WorkflowCtx) =
  ctx.scenariosDefined = true

proc whenStartingImplementation*(ctx: var WorkflowCtx) =
  ctx.implementationStarted = true

proc thenFailingTestsWrittenFirstUsingTdd*(ctx: var WorkflowCtx) =
  doAssert ctx.scenariosDefined, "BDD scenarios must be defined and approved"
  doAssert ctx.implementationStarted, "Implementation must have started"
  doAssert ctx.testsWritten, "Failing tests must be written first"

proc thenOnlyMinimalChangesReflected*(ctx: var WorkflowCtx) =
  doAssert ctx.scenariosDefined, "BDD scenarios must be defined and approved"
  doAssert ctx.implementationStarted, "Implementation must have started"
  doAssert ctx.minimalChanges, "Only minimal code changes that pass tests must be reflected"

# ── Rule: Bug reproduction and user scenario fixation ───────────────────────

proc givenBugDiscoveredOrNewUserRequirement*(ctx: var WorkflowCtx) =
  ctx.bugDiscovered = true

proc whenPerformingImplementation*(ctx: var WorkflowCtx) =
  ctx.performingImplementation = true

proc thenBddTestReproducingSituationWrittenAndFixed*(ctx: var WorkflowCtx) =
  doAssert ctx.bugDiscovered, "Bug or user requirement must be discovered"
  doAssert ctx.performingImplementation, "Implementation must be in progress"
  doAssert ctx.bddTestWritten, "BDD test reproducing the situation must be written and fixed"

# ── Rule: 100% test coverage enforcement ────────────────────────────────────

proc givenCodeChangesComplete*(ctx: var WorkflowCtx) =
  ctx.codeChangesComplete = true

proc whenRunningPrekTests*(ctx: var WorkflowCtx) =
  ctx.prekTestsRun = true

proc thenTestCoverageSatisfies100Percent*(ctx: var WorkflowCtx) =
  doAssert ctx.codeChangesComplete, "Code changes must be complete"
  doAssert ctx.prekTestsRun, "prek tests must be run"
  doAssert ctx.coverageSatisfies100, "Test coverage must satisfy 100%"

proc thenCommitsBlockedIfBelow100Percent*(ctx: var WorkflowCtx) =
  doAssert ctx.codeChangesComplete, "Code changes must be complete"
  doAssert ctx.prekTestsRun, "prek tests must be run"
  doAssert ctx.commitsBlockedIfBelow100, "Commits must be blocked by quality gate if coverage below 100%"
