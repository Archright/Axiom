## test_trusted_writer_set_gate.nim — job-level effective-permission contract
## for tools/ci/trusted_writer_set_gate.nim (DEBT#557).
##
## The gate's pure half (scanWorkflow / judge) is imported directly — no
## subprocess, no fixture tree, no git. The cases pin the semantics that the
## bash scanner could not express:
##
##   * a job-level `permissions:` block REPLACES the workflow block (a job
##     that names only `contents: read` is not a writer even when the workflow
##     block says `write`);
##   * a job block that omits `contents` grants `none` (GitHub semantics);
##   * flow-style maps (`permissions: {contents: write}`) are read, not
##     skipped — a silent skip would be a fail-open;
##   * a workflow with no permissions block anywhere is UNPROVABLE, so only the
##     explicitly known instances pass (R4);
##   * delta mode (base vs head) flags a job that gained write (R2), and a
##     declared `trustedWriterJobs` set must match exactly (R3).

import std/[strutils, unittest]

import ../../tools/ci/trusted_writer_set_gate

const
  WriterPath = ".github/workflows/certificate-mint.yml"
  AdmissionSha = "13bd4e55e9bf8a531d9d608c13d3fc2657478998"

  TopWrite =
    "name: mint\n" &
    "on: workflow_call\n" &
    "permissions:\n" &
    "  contents: write\n" &
    "jobs:\n" &
    "  publish:\n" &
    "    runs-on: ubuntu-latest\n" &
    "    steps:\n" &
    "      - run: echo\n"

  TopReadJobWrite =
    "name: gate\n" &
    "on: pull_request\n" &
    "permissions:\n" &
    "  contents: read\n" &
    "jobs:\n" &
    "  mint-publish:\n" &
    "    permissions:\n" &
    "      contents: write\n" &
    "    runs-on: ubuntu-latest\n"

  TopRead =
    "name: gate\n" &
    "on: pull_request\n" &
    "permissions:\n" &
    "  contents: read\n" &
    "jobs:\n" &
    "  check:\n" &
    "    runs-on: ubuntu-latest\n"

  JobReadOnly =
    "name: gate\n" &
    "on: pull_request\n" &
    "permissions:\n" &
    "  contents: write\n" &
    "jobs:\n" &
    "  narrowed:\n" &
    "    permissions:\n" &
    "      contents: read\n" &
    "    runs-on: ubuntu-latest\n"

  JobMapWithoutContents =
    "name: gate\n" &
    "on: pull_request\n" &
    "permissions:\n" &
    "  contents: write\n" &
    "jobs:\n" &
    "  narrowed:\n" &
    "    permissions:\n" &
    "      id-token: write\n" &
    "    runs-on: ubuntu-latest\n"

  TopWriteAll =
    "name: gate\n" &
    "on: push\n" &
    "permissions: write-all\n" &
    "jobs:\n" &
    "  j:\n" &
    "    runs-on: ubuntu-latest\n"

  TopFlowWrite =
    "name: gate\n" &
    "on: push\n" &
    "permissions: {contents: write, id-token: read}\n" &
    "jobs:\n" &
    "  j:\n" &
    "    runs-on: ubuntu-latest\n"

  JobFlowWrite =
    "name: gate\n" &
    "on: push\n" &
    "permissions:\n" &
    "  contents: read\n" &
    "jobs:\n" &
    "  j:\n" &
    "    permissions: {contents: write}\n" &
    "    runs-on: ubuntu-latest\n"

  NoPermissions =
    "name: reusable\n" &
    "on: workflow_call\n" &
    "jobs:\n" &
    "  j:\n" &
    "    runs-on: ubuntu-latest\n"

func declaredSet(jobs: seq[string] = @[]): DeclaredWriterSet =
  DeclaredWriterSet(writerWorkflow: WriterPath, admissionSha: AdmissionSha,
                    writerJobs: jobs)

func scanOf(path, src: string): WorkflowScan =
  scanWorkflow(path, src)

suite "trusted_writer_set_gate — scan semantics":
  test "top-level contents: write marks the workflow writer":
    let s = scanOf(WriterPath, TopWrite)
    check s.errors.len == 0
    check s.isTopWriter
    check s.jobs.len == 1
    check s.effectiveContents(s.jobs[0]) == cpWrite

  test "job-level block replaces the workflow block (narrowing)":
    let s = scanOf(".github/workflows/gate.yml", JobReadOnly)
    check s.isTopWriter
    check s.effectiveContents(s.jobs[0]) == cpRead

  test "job block without contents grants none":
    let s = scanOf(".github/workflows/gate.yml", JobMapWithoutContents)
    check s.effectiveContents(s.jobs[0]) == cpNone

  test "job-level write is observed under a read-only workflow":
    let s = scanOf(".github/workflows/gate.yml", TopReadJobWrite)
    check not s.isTopWriter
    check s.effectiveContents(s.jobs[0]) == cpWrite
    check jobWriters(@[s]) == @[".github/workflows/gate.yml#mint-publish"]

  test "write-all and flow-style maps are parsed, not skipped":
    check scanOf(".github/workflows/a.yml", TopWriteAll).isTopWriter
    check scanOf(".github/workflows/b.yml", TopFlowWrite).isTopWriter
    let flowJob = scanOf(".github/workflows/c.yml", JobFlowWrite)
    check not flowJob.isTopWriter
    check flowJob.effectiveContents(flowJob.jobs[0]) == cpWrite

  test "unparsable permissions scalar is an error, not a silent pass":
    let s = scanOf(".github/workflows/d.yml",
                   "permissions: contents\njobs:\n  j:\n    runs-on: x\n")
    check s.errors.len > 0

suite "trusted_writer_set_gate — judgment":
  test "R1: exactly the declared top-level writer passes":
    let v = judge(@[scanOf(WriterPath, TopWrite)], declaredSet(), @[], false)
    check v.ok
    check v.topWriters == @[WriterPath]

  test "R1: an extra top-level writer fails":
    let v = judge(@[scanOf(WriterPath, TopWrite),
                    scanOf(".github/workflows/evil.yml", TopWrite)],
                  declaredSet(), @[], false)
    check not v.ok
    check "tws_top_writer_unexpected:.github/workflows/evil.yml" in v.reasons

  test "R1: a missing declared writer fails":
    let v = judge(@[scanOf(".github/workflows/gate.yml", TopRead)],
                  declaredSet(), @[], false)
    check not v.ok
    check "tws_declared_writer_not_observed:" & WriterPath in v.reasons

  test "R2: a job that gains write relative to base fails":
    let base = @[scanOf(".github/workflows/gate.yml", TopRead)]
    let head = @[scanOf(".github/workflows/gate.yml", TopReadJobWrite),
                 scanOf(WriterPath, TopWrite)]
    let v = judge(head, declaredSet(), base, true)
    check not v.ok
    check "tws_job_level_write_added:.github/workflows/gate.yml#mint-publish" in v.reasons

  test "R2: pre-existing job-level writers are accepted":
    let tree = @[scanOf(WriterPath, TopWrite),
                 scanOf(".github/workflows/gate.yml", TopReadJobWrite)]
    let v = judge(tree, declaredSet(), tree, true)
    check v.ok

  test "R3: declared job set must match exactly":
    let tree = @[scanOf(WriterPath, TopWrite)]
    let exact = judge(tree, declaredSet(@[WriterPath & "#publish"]), @[], false)
    check exact.ok
    let missing = judge(tree, declaredSet(@[WriterPath & "#other"]), @[], false)
    check not missing.ok
    check "tws_job_not_declared:" & WriterPath & "#publish" in missing.reasons
    check "tws_declared_job_not_observed:" & WriterPath & "#other" in missing.reasons

  test "R4: a new unconstrained workflow fails, a known one is a note":
    let unknown = judge(@[scanOf(WriterPath, TopWrite),
                          scanOf(".github/workflows/evil.yml", NoPermissions)],
                        declaredSet(), @[], false)
    check not unknown.ok
    check "tws_unconstrained_workflow:.github/workflows/evil.yml" in unknown.reasons

    let known = judge(@[scanOf(WriterPath, TopWrite),
                        scanOf(".github/workflows/byo-agent.yml", NoPermissions)],
                      declaredSet(), @[], false)
    check known.ok
    var sawKnown = false
    for note in known.notes:
      if "byo-agent.yml" in note:
        sawKnown = true
    check sawKnown