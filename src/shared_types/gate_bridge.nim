## Gate Layer Bridge — Thin Interface for tools/
import core/trusted/layer_declaration
axiomLayer "infrastructure"
import core/gate/gate_memo
import core/gate/resource_limits
import core/utils/repo_root
import gate/daemon/gate_daemon_client
import gate/daemon/gate_daemon_server
import gate/gate_types
import gate/pipeline_orchestrator
export gate_memo.advanceCacheEpoch
export resource_limits.raiseRlimitNoFile
export repo_root.findRepoRoot
export gate_daemon_server.defaultConfig, gate_daemon_server.runDaemon
export gate_daemon_client.stopDaemon, gate_daemon_client.isDaemonRunning
export pipeline_orchestrator.registerDefaultInProcessGates
export pipeline_orchestrator.runPipeline
export gate_types.GateStage  # enum fields exported with type
