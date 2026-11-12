import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

type
  ErrorKind* = enum
    ekParse       ## 파서 에러
    ekIO          ## I/O 에러
    ekTimeout     ## 타임아웃
    ekValidation  ## 검증 에러
    ekHash        ## 해시 에러
    ekZ3          ## Z3 에러
    ekGate        ## 게이트 에러

  AxiomError* = object
    kind*: ErrorKind
    message*: string
    file*: string       ## 에러 발생 파일 (선택)
    line*: int          ## 에러 발생 라인 (선택)
    retryable*: bool    ## 재시도 가능 여부
# ───────────────────────────────────────────────
func newAxiomError*(kind: ErrorKind; msg: string;
                    file: string = ""; line: int = 0;
                    retryable: bool = false): AxiomError {.raises: [].} =
  AxiomError(kind: kind, message: msg, file: file, line: line, retryable: retryable)
func isRetryable*(err: AxiomError): bool {.raises: [].} =
  err.retryable
func isKind*(err: AxiomError; kind: ErrorKind): bool {.raises: [].} =
  err.kind == kind
func kind*(err: AxiomError): ErrorKind {.raises: [].} =
  err.kind
func message*(err: AxiomError): string {.raises: [].} =
  err.message
func toAxiomError*(msg: string; kind: ErrorKind = ekValidation): AxiomError {.raises: [].} =
  ## Convert a plain string error to an AxiomError (legacy bridge).
  newAxiomError(kind, msg)
func toMessage*(err: AxiomError): string {.raises: [].} =
  ## Extract the plain-text message from a structured error.
  err.message
func parseError*(msg: string): AxiomError {.raises: [].} =
  newAxiomError(ekParse, msg)
func ioError*(msg: string; retryable: bool = true): AxiomError {.raises: [].} =
  newAxiomError(ekIO, msg, retryable=retryable)
func timeoutError*(timeoutMs: int): AxiomError {.raises: [].} =
  newAxiomError(ekTimeout, "Timeout after " & $timeoutMs & "ms",
                retryable=true)
func hashError*(msg: string): AxiomError {.raises: [].} =
  newAxiomError(ekHash, msg)
func z3Error*(msg: string): AxiomError {.raises: [].} =
  newAxiomError(ekZ3, msg)
func gateError*(msg: string): AxiomError {.raises: [].} =
  newAxiomError(ekGate, msg)
proc `$`*(err: AxiomError): string {.raises: [].} =
  result = "[" & $err.kind & "] " & err.message
  if err.file.len > 0:
    result &= " (" & err.file
    if err.line > 0:
      result &= ":" & $err.line
    result &= ")"
  if err.retryable:
    result &= " [retryable]"

{.pop.}
