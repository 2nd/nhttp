import nhttp

var s = nhttp.Server(
  reuse: true,
  readTimeout: 5000,
  writeTimeout: 5000,
)
setControlCHook(proc() {.noconv.} = s.shutdown())
s.listen(5801)
