## IO Utility Bridge — Thin Interface for tools/
## AGENTS.md §0.4b: shared_types is the sole tools/→src/ gateway
import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
import core/json/std_redirect
import core/io/io_utils
import core/io/file_utils
import core/json/json_utils
export io_utils.writeFileOpt
export file_utils.readFileSafe, file_utils.writeFileSafe
export json_utils.writePrettyJsonFile, json_utils.readJsonFile, json_utils.parseJsonOpt
{.pop.}
