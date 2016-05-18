import strtabs, cgi, uri, parseutils

proc parseQuery(query: string): strtabs.StringTableRef =
  result = strtabs.newStringTable(strtabs.modeCaseInsensitive)
  var position = 0
  while position < query.len:
    let start = position
    position += query.skipUntil('=', position)
    let i1 = query.skipUntil('&', position)
    result[query.substr(start, position-1)] = cgi.decodeUrl(query.substr(position+1, position+i1-1))
    position += i1 + 1

proc readRequest(socket: Socket): tuple[req: Request, code: int] =
  let requestLine = socket.readLine()
  if requestLine.len == 0:
    return (nil, 0)

  var headers = strtabs.newStringTable(strtabs.modeCaseInsensitive)
  for i in 0..MAX_REQUEST_HEADERS:
    let header = socket.readLine()
    if header == "\c\L": break
    if header.len == 0: return
    var name: string
    let index = header.parseUntil(name, ':')
    let position =  header.skipWhitespace(index + 1)
    headers[name] = header.substr(index + 1 + position)

  if headers.len > MAX_REQUEST_HEADERS:
    return (nil, 431)

  var m: string
  let start = requestLine.parseUntil(m, ' ') + 1
  var stop = requestLine.len - 1
  for i in countdown(stop, start):
    if requestLine[i] == ' ': stop = i; break

  var req = new(Request)
  req.m = m
  req.headers = headers
  req.proto = requestLine.substr(stop+1)
  req.uri = uri.parseUri(requestLine.substr(start, stop-1))
  req.query = parseQuery(req.uri.query)

  if m != "POST" and m != "PUT":
    return (req, 0)

  var unread = 0
  if headers.getOrDefault("Content-Length").parseInt(unread) == 0:
    return (nil, 411)

  var position = 0
  var body = newString(unread)
  body.setLen(0)
  while unread > 0:
    var buffer = newString(if unread > 8192: 8192 else: unread)
    let read = socket.s.recv(cstring(buffer), buffer.len, socket.readTimeout)

    if read <= 0:
      return (nil, 0)

    if read == buffer.len:
      body.add(buffer)
    else:
      copyMem(addr body[position], addr buffer[0], read)

    position += read
    unread -= read

  req.body = body

  (req, 0)
