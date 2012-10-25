# TODO: factor out stuff specific to client side?
# TODO: factor out datastructures?
# TODO: DictModel, ElementModel...

class EventStream

  @constant: (val) ->
    new EventStream(val)

  @from_event: (element, event_name) ->
    source = new EventStream()
    element.addEventListener event_name, (event) ->
      source.trigger_event(event)
    return source

  # TODO: kinda crappy how similar these are...
  @from_form_value: (element, event_name) ->
    signal = new EventStream(element.value)
    element.addEventListener event_name, (event) ->
      signal.trigger_event(element.value)
    return signal

  @merge: (streams, initial_value) ->
    merged = new EventStream()
    if initial_value
      merged.value = initial_value
    reasons = []
    for stream in streams
      stream.observe(
        (event) -> merged.trigger_event(event),
        (error) -> merged.trigger_error(error),
        ((reason) ->
          reasons.push(reason)
          if reasons.length == streams.length
            merged.trigger_close(reasons)
        )
      )
    return merged

  @derived: (streams, func) ->
    merged = EventStream.merge(streams)
    compute = ->
      values = (s.value for s in streams)
      return func.apply(null, values)
    derived = new EventStream(compute())
    merged.observe(
      ((event) ->
        derived.trigger_event(compute())
      )
    )
    return derived

  @now: (sample_rate) ->
    ticker = new Ticker(sample_rate)
    now_signal = ticker.map((evt) -> new Date())
    now_signal.value = new Date()
    now_signal.ticker = ticker # TODO meh
    return now_signal

  constructor: (initial_value) ->
    @observers = []
    @closed = false
    @value = initial_value # optional

  toString: ->
    return "#<EventStream>"

  add_observer: (observer) ->
    @observers.push(observer)

  remove_observer: (observer) ->
    ind = @observers.indexOf(observer)
    if ind == -1
      return null
    else
      return @observers.splice(ind, 1)[0]

  trigger_event: (event) ->
    if not @closed
      @value = event
      for observer in @observers
        observer.on_event(event)

  trigger_error: (error) ->
    if not @closed
      for observer in @observers
        observer.on_error(error)

  # TODO: make close state actually mean something (?)
  trigger_close: (reason) ->
    @closed = true
    for observer in @observers
      observer.on_close(reason)

  observe: (event_cb, error_cb, close_cb) ->
    observer = new Observer(this, event_cb, error_cb, close_cb)
    this.add_observer(observer)
    return observer

  map: (func, initial) ->
    if initial
      mapped = new EventStream(initial)
    else if typeof this.value != 'undefined'
      mapped = new EventStream(func(this.value))
    else
      mapped = new EventStream()
    this.observe(
      ((event) ->
        mapped.value = func(event)
        mapped.trigger_event(mapped.value)),
      (error) -> mapped.trigger_error(error)
      (reason) -> mapped.trigger_close(reason))
    return mapped

  filter: (func) ->
    if typeof this.value != 'undefined'
      filtered = new EventStream(this.value)
    else
      filtered = new EventStream()
    this.observe(
      (event) -> if func(event) then filtered.trigger_event(event),
      (error) -> filtered.trigger_error(error),
      (reason) -> filtered.trigger_close(reason)
    )
    return filtered

  fold: (initial, func) ->
    signal = new EventStream(initial)
    this.observe(
      (event) -> signal.trigger_event(func(signal.value, event)),
      (error) -> signal.trigger_error(error),
      (reason) -> signal.trigger_close(reason)
    )
    return signal

  distinct: ->
    dist = new EventStream(this.value)
    last_evt = this.value
    this.observe(
      ((event) ->
        if event != last_evt
          last_evt = event
          dist.trigger_event(event)),
      (error) -> dist.trigger_error(error),
      (reason) -> dist.trigger_close(close)
    )
    return dist

  throttle: (interval) ->
    last_time = new Date().getTime()
    throttled = new EventStream(this.value)
    this.observe(
      ((evt) ->
        now = new Date().getTime()
        if now >= last_time + interval
          last_time = now
          throttled.trigger_event(evt)
      ),
      (error) -> throttled.trigger_error(error),
      (reason) -> throttled.trigger_close(reason)
    )
    return throttled

  log: (name) ->
    repr = if name then name else this.toString()
    if typeof this.value != 'undefined'
      console.log("#{repr}:initial: #{this.value}")
    return this.observe(
      (event) -> console.log("#{repr}:event: #{event}"),
      (error) -> console.log("#{repr}:error: #{error}"),
      (reason) -> console.log("#{repr}:close: #{reason}")
    )

  bind_value: (object, attr_name) ->
    closed = false
    closed_reason = null
    if this.value
      object[attr_name] = this.value
    this.observe(
      ((event) -> if not closed
        object[attr_name] = event.toString()),
      (error) -> throw error,
      ((reason) ->
        closed = true
        closed_reason = reason)
    )


class Ticker extends EventStream

  constructor: (@interval) ->
    super()
    @tick_num = 0
    @closed = false
    @paused = new EventStream(false)
    this.tick()

  toString: ->
    return "#<Ticker>"

  tick: ->
    if not @closed and not @paused.value
      this.trigger_event(@tick_num)
      @tick_num += 1
      setTimeout((() => this.tick()), @interval)

  togglePaused: ->
    @paused.trigger_event(!@paused.value)
    if not @paused.value
      this.tick()

  trigger_close: () ->
    closed = true
    super.trigger_close()

class ElemDimensions extends EventStream

  constructor: (@elem) ->
    super()
    this.value = this.get_dimensions()
    EventStream.from_event(window, 'resize').observe(
      (evt) => this.trigger_event(this.get_dimensions())
    )

  get_dimensions: () ->
    {
      width: @elem.offsetWidth,
      height: @elem.offsetHeight
    }

class Observer

  constructor: (@event_stream, @event_cb, @error_cb, @close_cb) ->

  toString: ->
      return "#<Observer>"

  on_event: (event) ->
    @event_cb(event)

  on_error: (error) ->
    if typeof @error_cb != 'undefined'
      @error_cb(error)
    else
      console.error(reason)

  on_close: (reason) ->
    if typeof @close_cb != 'undefined'
      @close_cb(reason)

class ListModel

  # TODO: changes stream, length

  constructor: ->
    @list = []
    @additions = new EventStream()
    @removals = new EventStream()
    @mutations = new EventStream()
    incrs = @additions.map((evt) -> 1)
    decrs = @removals.map((evt) -> -1)
    @length = EventStream.merge([incrs, decrs]).fold(0, (length, evt) -> length + evt)
    @empty = @length.map((l) -> l == 0)

  get: (index) ->
    if index < 0
      @list[@list.length+index]
    else
      @list[index]

  add: (index, value) ->
    @list.splice(index, 0, value)
    @additions.trigger_event(
      index: index
      value: value
    )

  append: (value) ->
    this.add(@list.length, value)

  remove: (index) ->
    removed = @list.splice(index, 1)[0]
    @removals.trigger_event(
      index: index
      removed: removed
    )
    return removed

  mutate: (index, value) ->
    old_value = @list_index
    @list[index] = value
    @mutations.trigger_event(
      index: index
      old_value: old_value
      new_value: value
    )

  destroy: ->
    @additions.trigger_close()
    @removals.trigger_close()
    @mutations.trigger_close()

  map: (func) ->
    mapped = new ListModel()
    @additions.observe(
      (evt) -> mapped.add(evt.index, func(evt.index, evt.value))
    )
    @removals.observe(
      (evt) -> mapped.remove(evt.index)
    )
    @mutations.observe(
      (evt) -> mapped.mutate(evt.index, func(evt.index, evt.new_value))
    )
    for item in this.list
      mapped.append(item)
    return mapped

  bind_as_child_nodes: (parent) ->
    this.removals.observe(
      (evt) -> parent.removeChild(evt.removed)
    )
    this.mutations.observe(
      (evt) -> parent.replaceChild(evt.new_value, evt.old_value)
    )
    this.additions.observe(
      ((evt) ->
        if evt.index == parent.childNodes.length
          parent.appendChild(evt.value)
        else
          parent.insertBefore(evt.value, parent.childNodes[evt.index])
      )
    )

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

class LongPollingSocketStream extends SocketStream

  constructor: -> console.error('not implemented!')

# singleton
class DebugView

  @initialize: (container) ->
    DebugView.instance = new DebugView(container)

  @show: (name, event_stream) ->
    DebugView.instance.show(name, event_stream)

  @show_list: (name, list_model) ->
    DebugView.instance.show_list(name, list_model)

  @play_pause: (now_signal) ->
    DebugView.instance.play_pause(now_signal)

  constructor: (@container) ->

  show: (name, signal) ->
    li = document.createElement('li')
    li.innerText = "#{name}: "
    span = document.createElement('span')
    signal.bind_value(span, 'innerText')
    li.appendChild(span)
    @container.appendChild(li)

  show_list: (name, list_model) ->
    li = document.createElement('li')
    li.innerText = "#{name}: "
    els = document.createElement('ul')
    list_model.map(
      ((index, item) ->
        el = document.createElement('li')
        el.innerText = item.toString()
        return el)
    ).bind_as_child_nodes(els)
    li.appendChild(els)
    @container.appendChild(li)

  play_pause: (now_signal) ->
    li = document.createElement('li')
    button = document.createElement('button')
    now_signal.ticker.paused.map((paused) -> if paused then 'Play' else 'Pause').bind_value(button, 'innerText')
    EventStream.from_event(button, 'click').observe((click) -> now_signal.ticker.togglePaused())
    li.appendChild(button)
    @container.appendChild(li)

class Util

  @clamp = ((in_min, in_max, out_min, out_max) ->
    in_delta = in_max - in_min
    out_delta = out_max - out_min
    multiplier = out_delta / in_delta
    return (val) ->
      out_min + (val-in_min) * multiplier)

  # key_func :: object -> comparable object
  @partition_ordered_list = (list_model, key_func, divider) ->
    below = new ListModel()
    above = new ListModel()
    list_model.additions.observe((evt) ->
      above.append(evt.value)
    )
    divider.observe((evt) ->
      while above.list.length > 0 and key_func(above.get(0)) < evt
        removed = above.remove(0)
        below.append(removed)
    )
    return [below, above]

# TODO: what's the right way to do this?
window.EventStream = EventStream
window.Observer = Observer
window.Ticker = Ticker
window.ListModel = ListModel
window.SocketStream = SocketStream
window.WebSocketStream = WebSocketStream
window.LongPollingSocketStream = LongPollingSocketStream
window.DebugView = DebugView
window.ElemDimensions = ElemDimensions
window.Util = Util
