import strtabs, net

const REASON_PHRASES = {
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
  431: " Request Header Fields Too Large\r\n",
  500: " Internal Server Error\r\n",
  501: " Not Implemented\r\n",
  502: " Bad Gateway\r\n",
  503: " Service Unavailable\r\n",
  504: " Gateway Time-out\r\n",
  505: " HTTP Version not supported\r\n",
}.toTable()

proc hexLength(value: int): int =
  if value == 0: return 1
  var n = value
  while n > 0:
    n = n shr 4
    result += 1

proc newResponse(socket: net.Socket): Response =
  new(result)
  result.s = socket
  result.headers = strtabs.newStringTable(strtabs.modeCaseInsensitive)

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
