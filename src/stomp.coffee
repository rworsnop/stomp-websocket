###
Copyright (C) 2010 Jeff Mesnil -- http://jmesnil.net/
Copyright (C) 2012 FuseSource, Inc. -- http://fusesource.com
###

Stomp =

  Headers: {
    CONTENT_LENGTH : 'content-length',
    ACCEPT_VERSION : 'accept-version',
    VERSION        : 'version'
  }
  Versions: {
    VERSION_1_0 : '1.0',
    VERSION_1_1 : '1.1',

    supportedVersions : -> Stomp.Versions.VERSION_1_0 + ',' + Stomp.Versions.VERSION_1_1
  }

  frame: (command, headers=[], body='') ->
    command: command
    headers: headers
    body: body
    id: headers.id
    receipt: headers.receipt
    transaction: headers.transaction
    destination: headers.destination
    subscription: headers.subscription
    error: null
    toString: ->
      lines = [command]
      for own name, value of headers
        lines.push("#{name}:#{value}")
      lines.push('\n'+body)
      return lines.join('\n')
  
  unmarshal: (data) ->
    divider = data.search(/\n\n/)
    headerLines = data.substring(0, divider).split('\n')
    command = headerLines.shift()
    headers = {}
    body = ''
    trim = (str) ->
      str.replace(/^\s+/g,'').replace(/\s+$/g,'')

    # Parse headers
    line = idx = null
    for i in [0...headerLines.length]
      line = headerLines[i]
      idx = line.indexOf(':')
      headers[trim(line.substring(0, idx))] = trim(line.substring(idx + 1))

    if (headers[Stomp.Headers.CONTENT_LENGTH])
      len = parseInt(headers[Stomp.Headers.CONTENT_LENGTH])
      start = divider + 2
      body = (''+ data).substring(start, start + len)
    else
      # Parse body, stopping at the first \0 found.
      chr = null;
      for i in [(divider + 2)...data.length]
        chr = data.charAt(i)
        if chr is '\x00'
          break
        body += chr

    return Stomp.frame(command, headers, body)
  
  marshal: (command, headers, body) ->
    Stomp.frame(command, headers, body).toString() + '\x00'
  
  client: (url) ->
    new Client url
  
class Client
  constructor: (@url) ->
    # used to index subscribers
    @counter = 0 
    @connected = false
    # subscription callbacks indexed by subscriber's ID
    @subscriptions = {};
  
  _transmit: (command, headers, body) ->
    out = Stomp.marshal(command, headers, body)
    @debug?(">>> " + out)
    @ws.send(out)
  
  connect: (login_, passcode_, connectCallback, errorCallback) ->
    @debug?("Opening Web Socket...")
    klass = WebSocketStompMock or WebSocket
    @ws = new klass(@url)
    @ws.binaryType = "arraybuffer"
    @ws.onmessage = (evt) =>
      data = if evt.data instanceof ArrayBuffer
        view = new Uint8Array( evt.data )
        @debug?('--- got data length: ' + view.length)
        data = ""
        for i in view
          data += String.fromCharCode(i)
        data
      else
        evt.data
      @debug?('<<< ' + data)
      frame = Stomp.unmarshal(data)
      if frame.command is "CONNECTED" and connectCallback
        @connected = true
        connectCallback(frame)
      else if frame.command is "MESSAGE"
        onreceive = @subscriptions[frame.headers.subscription]
        onreceive?(frame)
      #else if frame.command is "RECEIPT"
      #  @onreceipt?(frame)
      #else if frame.command is "ERROR"
      #  @onerror?(frame)
    @ws.onclose   = =>
      msg = "Whoops! Lost connection to " + @url
      @debug?(msg)
      errorCallback?(msg)
    @ws.onopen    = =>
      @debug?('Web Socket Opened...')
      headers = {
         login: login_,
         passcode: passcode_,
      }
      headers[Stomp.Headers.ACCEPT_VERSION] = Stomp.Versions.supportedVersions()
      @_transmit("CONNECT", headers)
    @connectCallback = connectCallback
  
  disconnect: (disconnectCallback) ->
    @_transmit("DISCONNECT")
    @ws.close()
    @connected = false
    disconnectCallback?()
  
  send: (destination, headers={}, body='') ->
    headers.destination = destination
    @_transmit("SEND", headers, body)
  
  subscribe: (destination, callback, headers={}) ->
    id = "sub-" + @counter++
    headers.destination = destination
    headers.id = id
    @subscriptions[id] = callback
    @_transmit("SUBSCRIBE", headers)
    return id
  
  unsubscribe: (id, headers={}) ->
    headers.id = id
    delete @subscriptions[id]
    @_transmit("UNSUBSCRIBE", headers)
  
  begin: (transaction, headers={}) ->
    headers.transaction = transaction
    @_transmit("BEGIN", headers)
  
  commit: (transaction, headers={}) ->
    headers.transaction = transaction
    @_transmit("COMMIT", headers)
  
  abort: (transaction, headers={}) ->
    headers.transaction = transaction
    @_transmit("ABORT", headers)
  
  ack: (message_id, subscription, headers={}) ->
    headers["message-id"] = message_id
    headers["subscription"] = subscription
    @_transmit("ACK", headers)
  
  nack: (message_id, subscription, headers={}) ->
    headers["message-id"] = message_id
    headers["subscription"] = subscription
    @_transmit("NACK", headers)

if window?
  window.Stomp = Stomp
else
  exports.Stomp = Stomp
  WebSocketStompMock = require('./test/server.mock.js').StompServerMock
