# TODO: factor into socket family...?

class WebSocketStream extends EventStream

  # this is the primary interface.
  # connect :: (url, stream) -> Future[WebSocketStream]
  # the future returns once it has connected.
  @connect: (url, stream) ->
    if not stream?
      stream = new EventStream()
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

  @instance: () =>
    if not @singleton?
      @singleton = new BrowserEnvironment()
    return @singleton

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

class ElementModel

  ###
  @tag string
  @attributes Object<string, EventStream or string> or DictModel<string, EventStream or string>
  @children Array<ElementModel> or ListModel<ElementModel>
  ###
  constructor: (@tag, attributes, children) ->
    @el = document.createElement(@tag)
    # normalize children
    if children?
      if children.constructor == ListModel
        @children = children
      else if children.constructor == Array
        @children = new ListModel(children)
      else
        throw "children must be an array or a ListModel"
    else
      @children = new ListModel()
    # insert initial children
    for child in @children.list
      @el.appendChild(child.el)
    # bind children to element
    @children.additions.observe((evt) =>
      if evt.index == @el.childNodes.length
          @el.appendChild(evt.value.el)
        else
          @el.insertBefore(evt.value.el, @el.childNodes[evt.index])
    )
    @children.removals.observe((evt) =>
      @el.removeChild(evt.removed.el)
    )
    @children.mutations.observe((evt) =>
      @el.replaceChild(evt.new_value.el, evt.old_value.el)
    )
    # normalize attributes...
    if not attributes?
      attributes = {}
    @attributes = new DictModel()
    for k, v of attributes
      if v.constructor == EventStream
        @attributes.put(k, v)
      else if v.constructor == String
        @attributes.put(k, new EventStream(v))
      else
        throw "attribute value must be a string or an EventStream of strings"
    # binding event streams to attributes
    attr_bindings = {}
    bind_attr = (key, value_stream) =>
      @el.setAttribute(key, value_stream.value)
      attr_bindings[key] = value_stream.observe(
        (evt) => @el.setAttribute(key, evt),
        (err) => throw err,
        (reason) => @el.removeAttribute(key)
      )
    unbind_attr = (key) =>
      obs = attr_bindings[evt.key]
      if obs?
        obs.dispose()
        @el.removeAttribute(key)
      delete attr_bindings[evt.key]
    # set initial attributes
    for k, v of @attributes.dict
      bind_attr(k, v)
    # observe changes to the dict
    @attributes.puts.observe((evt) =>
      unbind_attr(evt.key)
      bind_attr(evt.key, evt.value)
    )
    @attributes.removals.observe((evt) =>
      unbind_attr(evt.key)
    )
    # initialize evt stream dict...
    @evt_streams = {}

  # TODO: some kind of magic key accessor would be cool.
  event_stream: (evt_name) ->
    if not @evt_streams[evt_name]?
      stream = BrowserEnvironment.instance().from_event(@el, evt_name)
      @evt_streams[evt_name] = stream
    return @evt_streams[evt_name]

  form_value: (events) ->
    if not @value
      streams = (@event_stream(evt) for evt in events)
      @value = EventStream.merge(streams, @el.value).map((evt) => @el.value)
    return @value

class TextNode

  constructor: (@val_stream) ->
    if typeof @val_stream == 'string'
      @val_stream = new EventStream(@val_stream)
    @el = document.createTextNode(@val_stream.value)
    @val_stream.observe((evt) =>
      @el.textContent = evt
    )
