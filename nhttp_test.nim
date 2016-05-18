import unittest, nhttp, httpclient, strutils, tables, strtabs

# echo back the request to the response so that we can validate it
proc handler(req: nhttp.Request, res: nhttp.Response) =
  for k, v in req.headers: res.headers["x-" & k] = v
  res.write(200)
  res.write("path=" & req.path & "\n")
  res.write("method=" & req.m & "\n")
  res.write("proto=" & req.proto & "\n")

var s = nhttp.Server(
  reuse: true,
  handler: handler,
  readTimeout: 1000,
)

proc listen(s: ptr nhttp.Server) = s[].listen(5802)
var ts: Thread[ptr nhttp.Server]
ts.createThread(listen, addr s)

proc parse(res: httpclient.Response): Table[string, string] =
  result = initTable[string, string]()
  for line in res.body.splitLines():
    let index = line.find('=')
    result[line.substr(0, index-1)] = line.substr(index+1)

suite "nhttp":

  test "get request":
    let res = httpclient.get("http://localhost:5802/spice/flow")
    let body = parse(res)
    check(body["path"] == "/spice/flow")
    check(body["method"] == "GET")
    check(body["proto"] == "HTTP/1.1")
    check(res.headers["Transfer-Encoding"] == "chunked")
    check(res.headers["x-Host"] == "localhost:5802")
