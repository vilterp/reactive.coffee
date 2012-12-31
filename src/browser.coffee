# TODO: factor into socket family...?

class WebSocketStream extends EventStream

  # this is the primary interface.
  # connect :: (url, stream) -> Future[WebSocketStream]
  # the future returns once it has connected.
  @connect: (url, stream) ->
    open_socket = new Future()
    socket = new WebSocket(url)
    socket.addEventListener('open', () ->
      open_socket.trigger_event(new WebSocketStream(socket, stream))
    )
    socket.addEventListener('close', (evt) ->
      open_socket.trigger_error(evt)
    )
    return open_socket

  # private constructor
  constructor: (@socket, @stream) ->
    super()
    if @socket.readyState != WebSocket.OPEN
      throw 'invalid argument'
    # send stream's messages over the socket
    @stream.observe(
      ((evt) =>
        if not @closed
          @socket.send(evt)
        else
          throw "can't send data over a closed websocket"
      ),
      ((err) =>
        throw {
          msg: 'tried to send error over websocket',
          err: err 
        }
      ),
      (close) => @socket.close()
    )
    # react to events coming over the socket
    @socket.addEventListener('message', (evt) =>
      @trigger_event(evt.data)
    )
    @socket.addEventListener('close', (evt) =>
      @trigger_close(evt)
    )
    @socket.addEventListener('error', (evt) =>
      @trigger_error(evt)
    )

  close: (reason) ->
    @socket.close()
    @trigger_close(reason)

class ElemDimensions extends EventStream

  constructor: (@elem) ->
    super()
    this.value = this.get_dimensions()
    EventStream.from_event(window, 'resize').observe(
      (evt) => this.trigger_event(this.get_dimensions())
    )

  get_dimensions: () ->
    width: @elem.offsetWidth,
    height: @elem.offsetHeight


class BrowserEnvironment extends Environment

  constructor: () ->
    super(window.location.href)
    window.addEventListener('unload', (evt) =>
      @do_shutdown()
    )

  bind_value: (stream, object, attr_name) ->
    closed = false
    closed_reason = null
    if stream.value?
      object[attr_name] = stream.value
    stream.observe(
      ((event) -> if not closed
        object[attr_name] = event.toString()),
      (error) -> throw error,
      ((reason) ->
        closed = true
        closed_reason = reason)
    )

  from_event: (element, event_name) ->
    source = new EventStream()
    element.addEventListener(event_name, (event) ->
      source.trigger_event(event)
    )
    return source

  from_form_value: (element, event_names) ->
    streams = (@from_event(element, event_name) for event_name in event_names)
    return EventStream.merge(streams, element.value).map((evt) -> element.value)
