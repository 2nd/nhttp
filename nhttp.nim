import os, net, nativesockets, threadpool, times, strtabs, parseutils, tables, strutils, uri, cgi

const SAFE = {net.SocketFlag.SafeDisconn}

var
  MAX_REQUEST_HEADERS*: int = 20

var REASON_PHRASES* = {
  100: " Continue\r\n",
  101: " Switching Protocols\r\n",
  200: " OK\r\n",
  201: " Created\r\n",
  202: " Accepted\r\n",
  203: " Non-Authoritative Information\r\n",
  204: " No Content\r\n",
  205: " Reset Content\r\n",
  206: " Partial Content\r\n",
  300: " Multiple Choices\r\n",
  301: " Moved Permanently\r\n",
  302: " Found\r\n",
  303: " See Other\r\n",
  304: " Not Modified\r\n",
  305: " Use Proxy\r\n",
  307: " Temporary Redirect\r\n",
  400: " Bad Request\r\n",
  401: " Unauthorized\r\n",
  402: " Payment Required\r\n",
  403: " Forbidden\r\n",
  404: " Not Found\r\n",
  405: " Method Not Allowed\r\n",
  406: " Not Acceptable\r\n",
  407: " Proxy Authentication Required\r\n",
  408: " Request Time-out\r\n",
  409: " Conflict\r\n",
  410: " Gone\r\n",
  411: " Length Required\r\n",
  412: " Precondition Failed\r\n",
  413: " Request Entity Too Large\r\n",
  414: " Request-URI Too Large\r\n",
  415: " Unsupported Media Type\r\n",
  416: " Requested range not satisfiable\r\n",
  417: " Expectation Failed\r\n",
  500: " Internal Server Error\r\n",
  501: " Not Implemented\r\n",
  502: " Bad Gateway\r\n",
  503: " Service Unavailable\r\n",
  504: " Gateway Time-out\r\n",
  505: " HTTP Version not supported\r\n",
}.toTable()

type
  Handler = proc(req: Request, res: Response)

  Server* = object
    s: net.Socket
    reuse*: bool
    handler*: Handler
    readTimeout*: int

  Request* = ref object
    m*: string     # method is a reserved word, (dealwithit)
    body: string
    uri*: uri.Uri
    proto*: string
    query*: strtabs.StringTableRef
    headers*: strtabs.StringTableRef

  Response* = ref object
    chunked: bool
    s*: net.Socket
    wroteHeaders: bool
    headers*: strtabs.StringTableRef

  Socket = object
    s: net.Socket
    handler: Handler
    readTimeout: int

proc error(args: varargs[string]) {.gcsafe.}
proc error(label: string, e: ref Exception) {.gcsafe.}

proc hexLength(value: int): int =
  if value == 0: return 1
  var n = value
  while n > 0:
    n = n shr 4
    result += 1

proc parseQuery(query: string): strtabs.StringTableRef =
  result = strtabs.newStringTable(strtabs.modeCaseInsensitive)
  var position = 0
  while position < query.len:
    let start = position
    position += query.skipUntil('=', position)
    let i1 = query.skipUntil('&', position)
    result[query.substr(start, position-1)] = cgi.decodeUrl(query.substr(position+1, position+i1-1))
    position += i1 + 1

proc write*(r: Response, status: int) =
  r.s.send("HTTP/1.1 " & $status & REASON_PHRASES[status], SAFE)
  for k, v in r.headers: r.s.send(k & ":" & v & "\r\n", SAFE)

  if not r.headers.hasKey("Content-Length") and not r.headers.hasKey("Transfer-Encoding"):
    r.chunked = true
    r.s.send("Transfer-Encoding: chunked\r\n", SAFE)

  r.s.send("\r\n")

proc write*(r: Response, data: string) {.inline.} =
  if not r.chunked:
    r.s.send(data, SAFE)
    return

  r.s.send(data.len.toHex(hexLength(data.len)) & "\r\n", SAFE)
  r.s.send(data, SAFE)
  r.s.send("\r\n", SAFE)

proc initSocket(server: Server): Socket =
  result.s = new(net.Socket)
  result.handler = server.handler
  result.readTimeout = server.readTimeout

proc valid(socket: Socket): bool {.inline.} =
  socket.s.getFd() != nativesockets.osInvalidSocket

proc readLine(socket: Socket): TaintedString {.inline.} =
  result = TaintedString""
  socket.s.readLine(result, socket.readTimeout, SAFE)

proc handle(socket: Socket) {.gcsafe.} =
  try:
    socket.s.getFd().setSockOptInt(6, 1, 1) # tcp_nodelay
    let requestLine = socket.readLine()
    if requestLine.len == 0: return  # client disconnected

    var headers = strtabs.newStringTable(strtabs.modeCaseInsensitive)
    for i in 0..<MAX_REQUEST_HEADERS:
      let header = socket.readLine()
      if header == "\c\L": break
      if header.len == 0: return
      var name: string
      let index = header.parseUntil(name, ':')
      let position =  header.skipWhitespace(index + 1)
      headers[name] = header.substr(index + 1 + position)

    var m: string
    let start = requestLine.parseUntil(m, ' ') + 1
    var stop = requestLine.len - 1
    for i in countdown(stop, start):
      if requestLine[i] == ' ': stop = i; break

    let req = new(Request)
    req.m = m
    req.headers = headers
    req.proto = requestLine.substr(stop+1)
    req.uri = uri.parseUri(requestLine.substr(start, stop-1))
    req.query = parseQuery(req.uri.query)

    let res = new(Response)
    res.s = socket.s
    res.headers = strtabs.newStringTable(strtabs.modeCaseInsensitive)
    socket.handler(req, res)
    if res.chunked: res.s.send("0\r\n\r\n")

  except:
    error("unhandled", getCurrentException())
    discard socket.s.trySend("HTTP/1.0 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n")
  finally:
    socket.s.close()

proc shutdown*(server: var Server) =
  if server.s != nil:
    server.s.close()
    server.s = nil

proc listen*(server: var Server, port: int) =
  if server.readTimeout < 1: server.readTimeout = 10000

  let listener = net.newSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP, buffered = false)
  server.s = listener

  if server.reuse: listener.setSockOpt(net.OptReuseAddr, true)
  listener.bindAddr(Port(port))
  listener.listen()

  while true:
    try:
      var socket = initSocket(server)
      listener.accept(socket.s, SAFE)
      if not socket.valid(): continue
      spawn socket.handle()
    except:
      if server.s == nil: return
      error("accept", getCurrentException())

proc error(args: varargs[string]) =
  write(stderr, "[error] ")
  writeLine(stderr, $times.getTime())
  for arg in args: writeLine(stderr, arg)

proc error(label: string, e: ref Exception) =
  error(label, getCurrentExceptionMsg(), e.getStackTrace())
