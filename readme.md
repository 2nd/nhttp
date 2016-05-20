# A Treaded HTTP Server for Nim

Nim's built-in HTTPServer is limited and being deprecated in favor of the async module. Unfortunately, Nim's async implementation doesn't [currently] work with threads.

This server is our stopgap until the async <-> thread issues are resolved.

## Usage

```
import nhttp, strtabs

proc handler(req: nhttp.Request, res: nhttp.Response) =
  res.headers["Content-Type"] = "application/json"
  res.write(200, "{....}")

var s = nhttp.Server(
  reuse: true,
  handler: handler,
  readTimeout: 10000,
)

# optionally hook into ctrl-c and gracefully close the socket
setControlCHook(proc() {.noconv.} = s.shutdown())

# blocks
s.listen(5701)
```
