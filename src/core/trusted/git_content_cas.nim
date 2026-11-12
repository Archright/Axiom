## src/core/trusted/git_content_cas.nim — content-addressable git storage for string payloads
##
## Promotes a string payload into the repository's git object store and returns
## the object id `git hash-object -w --stdin` reports. The id is a pure function
## of the content, so two equal payloads always produce one object.
##
## This capability lives in src/ rather than tools/ so that both the promotion
## tool and the tests can reach it without crossing the tools→core boundary
## (tools/check_imports_ast.nim forbids importing `tools/` from anywhere else).

import std/[osproc, streams, strutils]
# axiomIoBoundary

proc promoteContentToGitCAS*(content: string): string {.raises: [OSError, IOError, ValueError].} =
  ## Writes `content` into the git object store and returns its object id.
  ## Raises OSError/IOError when git is unavailable or exits non-zero, so callers
  ## decide their own failure policy instead of this module terminating the process.
  let process = startProcess("git", args = ["hash-object", "-w", "--stdin"],
                             options = {poUsePath})
  try:
    process.inputStream.write(content)
    process.inputStream.flush()
    process.inputStream.close()

    let output = process.outputStream.readAll().strip()
    let exitCode = process.waitForExit()
    process.close()
    if exitCode != 0:
      raise newException(OSError, "git hash-object failed with exit " & $exitCode)
    return output
  except IOError as e:
    if process != nil:
      process.close()
    raise newException(OSError, "git hash-object failed: " & e.msg)
  except ValueError as e:
    if process != nil:
      process.close()
    raise newException(OSError, "git hash-object failed: " & e.msg)
  except OSError:
    if process != nil:
      process.close()
    raise