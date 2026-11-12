## Static Analysis Bridge — Thin Interface for tools/
import core/trusted/layer_declaration
axiomLayer "infrastructure"
import core/ast_hash
import core/boundary/coverage_bridge
import core/import_graph
import core/manifest_schema
import core/telemetry/trace_normalizer
export manifest_schema.ValidationResult, manifest_schema.validateManifest
export manifest_schema.PropertyKind, manifest_schema.FunctionAnnotation
export manifest_schema.ModuleEntry, manifest_schema.ValidProperties
export manifest_schema.MinModules, manifest_schema.MinFunctions
export ast_hash.computeAstHash
export import_graph.CoreDir, import_graph.buildImportGraph, import_graph.computeTopologicalLayers
export coverage_bridge.ModuleMetrics, coverage_bridge.calculatePriority
export trace_normalizer.normalizeTrace, trace_normalizer.detectProjectRoot, trace_normalizer.RawTrace, trace_normalizer.NormalizedTrace, trace_normalizer.`$`
