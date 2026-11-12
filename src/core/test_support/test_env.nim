import core/trusted/layer_declaration
axiomLayer "domain"
import ../sync/sync_process_runner
import ../sync/sync_process_types
import core/axiom_pragmas
type
  FileReader* = proc(path: string): string
    ## Injectable file reader interface for test isolation.
    ## Production: reads real files. Test: returns canned content.

  Logger* = proc(level: string; msg: string)
    ## Injectable logger interface for test observation.
    ## Production: writes to stdout. Test: silent or captured.

  TestEnv* = object
    processRunner*: ProcessRunner
    fileReader*: FileReader
    logger*: Logger
proc newTestEnv*(): TestEnv {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Create a TestEnv with real (production) implementations.
  ## Use for integration tests that need actual I/O.
  let fr: FileReader = proc(path: string): string = readFile(path)
  let lg: Logger = proc(level, msg: string) = echo "[" & level & "] " & msg
  TestEnv(
    processRunner: defaultProcessRunner,
    fileReader: fr,
    logger: lg
  )
func newMockTestEnv*(): TestEnv {.raises: [].}=
  ## Create a TestEnv with mock implementations (zero I/O).
  ## Use for unit tests that must not touch real resources.
  let mockRunner: ProcessRunner = proc(cmd: string, args: seq[string], input: string): ManagedProcessResult =
    ManagedProcessResult(output: "mock", exitCode: 0, timedOut: false)
  let fr: FileReader = proc(path: string): string = "mock content"
  let lg: Logger = proc(level, msg: string) = discard
  TestEnv(
    processRunner: mockRunner,
    fileReader: fr,
    logger: lg
  )
