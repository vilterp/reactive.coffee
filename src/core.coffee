class EventStream

  @constant: (val) ->
    new EventStream(val)

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

# singleton
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

class Ticker extends EventStream

  # @interval: interval in milliseconds
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
