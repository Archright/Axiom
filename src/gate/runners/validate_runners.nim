import core/trusted/layer_declaration
axiomLayer "gate"
import infrastructure/logger
import std/[os, strutils]
import core/axiom_pragmas
# axiomIoBoundary

const
  GatewayDir = "tests/gateway"
  FeaturesDir = "tests/features"

type
  RunnerClass = enum
    rcStub, rcReal, rcPartial, rcEmpty, rcError

  FeatureInfo = object
    name: string
    path: string
    tag: string  # "@manual", "@executable", or ""
    runnerPath: string
    runnerClass: RunnerClass

proc classifyRunner(filepath: string): RunnerClass {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [].} =
  try:
    let content = readFile(filepath)
    let discardCount = content.count("discard")
    let hasCheck = "check" in content or "doAssert" in content or "assert" in content
    let hasSuite = "suite " in content
    if not hasCheck and discardCount > 0:
      return rcStub
    if hasCheck and hasSuite:
      return rcReal
    if hasCheck:
      return rcPartial
    return rcEmpty
  except CatchableError:
    return rcError

proc findFeatureTag(featurePath: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [].} =
  try:
    let content = readFile(featurePath)
    for line in content.splitLines:
      let stripped = line.strip
      if stripped.startsWith("Feature:"):
        break
      if "@manual" in stripped:
        return "@manual"
      if "@executable" in stripped:
        return "@executable"
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  result = ""  # default = @executable

proc findRunner(featureName: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [].} =
  let gatewayRunner = GatewayDir / (featureName & "_feature_test.nim")
  if fileExists(gatewayRunner):
    return gatewayRunner
  # NOTE: tests/auto_generated/ directory was removed. Only gateway runners are checked.
  result = ""

proc main()  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [ref OSError].} =
  let args = commandLineParams()
  let report = args.contains("--report")
  let promote = args.contains("--promote-real")
  let dryRun = args.contains("--dry-run") or not promote

  if not dirExists(FeaturesDir):
    logger.info "Features directory not found: " & FeaturesDir
    quit(1)

  var features: seq[FeatureInfo] = @[]
  for path in walkDirRec(FeaturesDir):
    try:
      if not path.endsWith(".feature"):
        continue
      let name = extractFilename(path).changeFileExt("")
      let tag = findFeatureTag(path)
      let runner = findRunner(name)
      let runnerClass = if runner.len > 0: classifyRunner(runner) else: rcEmpty
      features.add(FeatureInfo(
        name: name, path: path, tag: tag,
        runnerPath: runner, runnerClass: runnerClass
      ))
    except CatchableError as e:
      logger.warn("Skipping feature path: " & path & " (" & e.msg & ")")
    except ref OSError as e:
      logger.warn("Skipping feature path: " & path & " (" & e.msg & ")")

  var manualWithReal: seq[FeatureInfo] = @[]
  var manualWithStub: seq[FeatureInfo] = @[]
  var manualWithoutRunner: seq[FeatureInfo] = @[]
  var executableWithoutRunner: seq[FeatureInfo] = @[]
  var executableWithRunner: seq[FeatureInfo] = @[]

  for f in features:
    if f.tag == "@manual":
      if f.runnerPath.len > 0:
        if f.runnerClass == rcReal:
          manualWithReal.add(f)
        else:
          manualWithStub.add(f)
      else:
        manualWithoutRunner.add(f)
    else:
      if f.runnerPath.len > 0:
        executableWithRunner.add(f)
      else:
        executableWithoutRunner.add(f)

  logger.info("=== Runner Validation Report ===")
  logger.info("Total features: " & $features.len & "\n")

  logger.info("@manual features:")
  logger.info "  With REAL runner (promotable):  " & $manualWithReal.len
  logger.info "  With STUB runner (not ready):   " & $manualWithStub.len
  logger.info "  Without runner:                 " & $manualWithoutRunner.len
  logger.info("\n@executable features:")
  logger.info "  With runner:                    " & $executableWithRunner.len
  logger.info "  Without runner:                 " & $executableWithoutRunner.len

  if report:
    if manualWithReal.len > 0:
      logger.info("\n=== Promotable @manual features (" & $manualWithReal.len & ") ===")
      for f in manualWithReal:
        logger.info "  " & f.name & " → " & f.runnerPath

    if executableWithoutRunner.len > 0:
      logger.info("\n=== @executable without runner (" & $executableWithoutRunner.len & ") ===")
      for f in executableWithoutRunner:
        logger.info "  " & f.name

  if promote and manualWithReal.len > 0:
    logger.info("\n=== Promoting " & $manualWithReal.len & " features ===")
    var promoted = 0
    for f in manualWithReal:
      try:
        let content = readFile(f.path)
        let newContent = content.multiReplace(("@manual\n", ""), ("@manual", ""))
        if dryRun:
          logger.info "  DRY-RUN: Would promote " & f.name
        else:
          writeFile(f.path, newContent)
          logger.info "  ✅ Promoted: " & f.name
          inc promoted
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
    if not dryRun:
      logger.info("\nPromoted " & $promoted & " features from @manual to @executable")

when isMainModule:
  main()
