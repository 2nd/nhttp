import unittest, nhttp, httpclient, strutils, tables, strtabs

# echo back the request to the response so that we can validate it
proc handler(req: nhttp.Request, res: nhttp.Response) =
  for k, v in req.headers: res.headers["x-" & k] = v
  res.write(200)
  res.write("path=" & req.uri.path & "\n")
  res.write("method=" & req.m & "\n")
  res.write("proto=" & req.proto & "\n")
  for k, v in req.query: res.write("q_" & k & "=" & v & "\n")

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

  test "single query":
    let res = httpclient.get("http://localhost:5802/spice/flow?a=1")
    let body = parse(res)
    check(body["q_a"] == "1")

  test "multiple query":
    let res = httpclient.get("http://localhost:5802/?over=9000&scared=yes")
    let body = parse(res)
    check(body["q_over"] == "9000")
    check(body["q_scared"] == "yes")

  test "encoded query":
    let res = httpclient.get("http://localhost:5802/?over=90%2000")
    let body = parse(res)
    check(body["q_over"] == "90 00")

  # not sure what this should be, but at least it doesn't crash
  test "invalid query":
    let res = httpclient.get("http://localhost:5802/?a=b=3&c=2")
    let body = parse(res)
    check(body["q_a"] == "b=3")
    check(body["q_c"] == "2")
