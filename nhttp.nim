import os, net, nativesockets, threadpool, times, strtabs, tables, strutils, uri

const SAFE = {net.SocketFlag.SafeDisconn}

var
  # The maximum number of request headers we'll accept
  MAX_REQUEST_HEADERS*: int = 20

type
  Handler = proc(req: Request, res: Response)

  Server* = object
    s: net.Socket
    reuse*: bool
    handler*: Handler
    readTimeout*: int

  Socket = object
    s: net.Socket
    handler: Handler
    readTimeout: int

  Request* = ref object
    m*: string     # method is a reserved word, (dealwithit)
    body*: string
    uri*: uri.Uri
    proto*: string
    query*: strtabs.StringTableRef
    headers*: strtabs.StringTableRef

  Response* = ref object
    chunked: bool
    s*: net.Socket
    wroteHeaders: bool
    headers*: strtabs.StringTableRef

proc error(args: varargs[string]) {.gcsafe.}
proc error(label: string, e: ref Exception) {.gcsafe.}
proc readLine(socket: Socket): TaintedString {.gcsafe, inline.}

include response, request

proc initSocket(server: Server): Socket =
  result.s = new(net.Socket)
  result.handler = server.handler
  result.readTimeout = server.readTimeout

proc valid(socket: Socket): bool {.inline.} =
  socket.s.getFd() != nativesockets.osInvalidSocket

proc readLine(socket: Socket): TaintedString =
  result = TaintedString""
  socket.s.readLine(result, socket.readTimeout, SAFE)

proc trySendError(socket: Socket, code: int) =
  discard socket.s.trySend("HTTP/1.1 " & REASON_PHRASES[code] & "Connection: Close\r\nContent-Length: 0\r\n\r\n")

proc handle(socket: Socket) {.gcsafe.} =
  try:
    socket.s.getFd().setSockOptInt(6, 1, 1) # tcp_nodelay
    while true:
      let r = readRequest(socket)
      if r.req == nil:
        if r.code != 0: socket.trySendError(r.code)
        return

      let req = r.req
      let res = newResponse(socket.s)
      socket.handler(req, res)
      if res.chunked: res.s.send("0\r\n\r\n")
      if req.headers.getOrDefault("Connection").toLower() == "close":
        return

  except net.TimeoutError: discard
  except:
    error("unhandled", getCurrentException())
    socket.trySendError(500)
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
