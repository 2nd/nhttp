import strtabs, net, times

const REASON_PHRASES = {
  100: "100 Continue\r\n",
  101: "101 Switching Protocols\r\n",
  200: "200 OK\r\n",
  201: "201 Created\r\n",
  202: "202 Accepted\r\n",
  203: "203 Non-Authoritative Information\r\n",
  204: "204 No Content\r\n",
  205: "205 Reset Content\r\n",
  206: "206 Partial Content\r\n",
  300: "300 Multiple Choices\r\n",
  301: "301 Moved Permanently\r\n",
  302: "302 Found\r\n",
  303: "303 See Other\r\n",
  304: "304 Not Modified\r\n",
  305: "305 Use Proxy\r\n",
  307: "307 Temporary Redirect\r\n",
  400: "400 Bad Request\r\n",
  401: "401 Unauthorized\r\n",
  402: "402 Payment Required\r\n",
  403: "403 Forbidden\r\n",
  404: "404 Not Found\r\n",
  405: "405 Method Not Allowed\r\n",
  406: "406 Not Acceptable\r\n",
  407: "407 Proxy Authentication Required\r\n",
  408: "408 Request Time-out\r\n",
  409: "409 Conflict\r\n",
  410: "410 Gone\r\n",
  411: "411 Length Required\r\n",
  412: "412 Precondition Failed\r\n",
  413: "413 Request Entity Too Large\r\n",
  414: "414 Request-URI Too Large\r\n",
  415: "415 Unsupported Media Type\r\n",
  416: "416 Requested range not satisfiable\r\n",
  417: "417 Expectation Failed\r\n",
  431: "431 Request Header Fields Too Large\r\n",
  500: "500 Internal Server Error\r\n",
  501: "501 Not Implemented\r\n",
  502: "502 Bad Gateway\r\n",
  503: "503 Service Unavailable\r\n",
  504: "504 Gateway Time-out\r\n",
  505: "505 HTTP Version not supported\r\n",
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
  r.s.send("HTTP/1.1 " & REASON_PHRASES[status], SAFE)
  for k, v in r.headers: r.s.send(k & ": " & v & "\r\n", SAFE)

  if not r.headers.hasKey("Content-Length") and not r.headers.hasKey("Transfer-Encoding"):
    r.chunked = true
    r.s.send("Transfer-Encoding: chunked\r\n", SAFE)

  if not r.headers.hasKey("Date"):
    r.s.send("Date: " & times.getTime().getGMTime().format("ddd, dd MMM yyyy HH:mm:ss") & " GMT\r\n", SAFE)

  r.s.send("\r\n")

proc write*(r: Response, data: string) {.inline.} =
  if not r.chunked:
    r.s.send(data, SAFE)
    return

  r.s.send(data.len.toHex(hexLength(data.len)) & "\r\n", SAFE)
  r.s.send(data, SAFE)
  r.s.send("\r\n", SAFE)

# Write the header and body in a single command
# Subsequent calls to any write overload will result in an invalid response
proc write*(r: Response, status: int, data: string) {.inline.} =
  r.headers["Content-Length"] = $data.len
  r.write(status)
  r.s.send(data, SAFE)
