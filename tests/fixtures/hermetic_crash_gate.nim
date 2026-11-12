proc abort() {.importc, header: "<stdlib.h>".}
when isMainModule:
  abort()
