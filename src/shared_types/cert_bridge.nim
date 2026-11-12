## Certificate/Asset Generation Bridge — Thin Interface for tools/
import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
import core/asset_collector
import core/symbol_graph/global_symbol_graph_builder_part2
import core/symbol_graph/global_symbol_graph_query
import verification/cert_builder
import verification/lean_spec_generator
import core/spec/spec_generator_main
export asset_collector.collectFunctions, asset_collector.FunctionRef
export asset_collector.normalizeIdentForFilename
export cert_builder.loadExistingGreenKeys, cert_builder.writeCertificates
export lean_spec_generator.writeMissingList, lean_spec_generator.writeLeanSpec
export global_symbol_graph_builder_part2.buildGlobalSymbolGraph
export global_symbol_graph_query.graphHash
export spec_generator_main.generateTypeMappingCertificates
{.pop.}
