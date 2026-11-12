import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

type
  StageKind* = enum
    skPreCommit = "pre-commit"
    skPrePush = "pre-push"
    skManual = "manual"
    skCI = "ci"

  LayerKind* = enum
    lkMeta = "meta"
    lkFunctional = "functional"

  WeightKind* = enum
    wkLight = "light"
    wkMedium = "medium"
    wkHeavy = "heavy"

  CategoryKind* = enum
    ckTheorem = "theorem"
    ckRule = "rule"
    ckPolicy = "policy"
    ckValidation = "validation"

  SeverityKind* = enum
    svWarn = "warn"
    svError = "error"

  ExecutionModeKind* = enum
    emAOT = "aot"
    emInterpreted = "interpreted"

  HermeticityKind* = enum
    hkHermetic = "hermetic"
    hkTransient = "transient"

  TopologyEntry* = object
    id*: string
    name*: string
    layer*: LayerKind
    entry*: string
    stages*: seq[StageKind]
    filesPattern*: string
    passFilenames*: bool
    weight*: WeightKind
    category*: CategoryKind
    argsTemplate*: seq[string]
    after*: seq[string]
    tier*: int
    severity*: SeverityKind
    executionMode*: ExecutionModeKind
    hermeticity*: HermeticityKind
    priority*: int
    alwaysRun*: bool
    depsDirs*: seq[string]
    timeoutSeconds*: int

  TopologyGateEntry* = object
    id*: string
    path*: string

  ManifestRegistryEntry* = object
    id*: string
    entry*: string

func initTopologyEntry*(
  id, name: string;
  layer: LayerKind;
  entry: string;
  stages: seq[StageKind];
  passFilenames: bool;
  weight: WeightKind;
  category: CategoryKind;
  filesPattern: string = "";
  argsTemplate: seq[string] = @[];
  after: seq[string] = @[];
  tier: int = 1;
  severity: SeverityKind = svError;
  executionMode: ExecutionModeKind = emAOT;
  hermeticity: HermeticityKind = hkHermetic;
  priority: int = 0;
  alwaysRun: bool = false;
  depsDirs: seq[string] = @[];
  timeoutSeconds: int = 0
): TopologyEntry {.raises: [].} =
  TopologyEntry(
    id: id, name: name, layer: layer, entry: entry,
    stages: stages, passFilenames: passFilenames, weight: weight,
    category: category, filesPattern: filesPattern,
    argsTemplate: argsTemplate, after: after, tier: tier,
    severity: severity, executionMode: executionMode,
    hermeticity: hermeticity, priority: priority,
    alwaysRun: alwaysRun, depsDirs: depsDirs,
    timeoutSeconds: timeoutSeconds
  )

{.pop.}
