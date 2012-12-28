class SocketStream extends EventStream

  constructor: -> super()

class WebSocketStream extends SocketStream

  constructor: (@url) ->
    super()
    @socket = new WebSocket(@url)
    @socket.addEventListener('message',
      (evt) => this.trigger_event(evt.data)
    )
    @socket.addEventListener('error',
      (evt) => this.trigger_error(evt) # can't find exactly what this object will be
    )
    @socket.addEventListener('close',
      (evt) =>
        console.log('websocket closed!')
        this.trigger_close(evt) # CloseEvent contains reason information
    )

  send: (data) ->
    @socket.send(data)

  close: () ->
    @socket.close()

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

class ESWindow

  # TODO: hm, this is a little janky
  constructor: (@window) ->
    @load = this.from_event(@window, 'load')
    @unload = this.from_event(@window, 'unload')

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
    element.addEventListener event_name, (event) ->
      source.trigger_event(event)
    return source

  from_form_value: (element, event_names) ->
    streams = (eswindow.from_event(element, event_name) for event_name in event_names)
    return EventStream.merge(streams, element.value).map((evt) -> element.value)

Debuggee.initialize('ws://localhost:8000/debuggee', window.location.href) # TODO: uh, yeah. coffeescript compile arguments for dev/prod?
eswindow = new ESWindow(window)
eswindow.unload.observe((evt) ->
  Debuggee.shutdown()
)
