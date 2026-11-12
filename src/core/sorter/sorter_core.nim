import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Facade: re-exports sorter_core_index and sorter_core_algo for backward compatibility.
import core/sorter/sorter_core_index_base
import core/sorter/sorter_core_index_table
export sorter_core_index_base
export sorter_core_index_table
import core/sorter/sorter_core_ordinal_table
export sorter_core_ordinal_table
import core/sorter/sorter_core_algo
export sorter_core_algo

{.pop.}
