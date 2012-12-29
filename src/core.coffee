if require?
  dbg = require('./debuggee')
  require('lodash')

Debuggee = if dbg? then dbg.Debuggee else Debuggee

class EventStream

  @constant: (val) ->
    new EventStream(val)

  @merge: (streams, initial_value) ->
    merged = new EventStream()
    if initial_value?
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

  ###
  e.g.
  EventStream.multiplex({
    'additions': additions,
    'deletions': deletions,
    ...
  }); 
      => a stream with events:
    {name: 'additions', body: ...}
    {name: 'deletions', body: ...}
  ###
  @multiplex: (streams) ->
    transformed = []
    # TODO: refactor with map() or something
    for name, stream of streams
      # add name
      with_name = stream.map((evt) =>
        obj = {}
        obj[stream_key] = name
        obj[body_key] = evt
        return obj
      )
      # add errors and closes
      errors_included = new EventStream()
      with_name.observe(
        (evt) -> errors_included.trigger_event(evt),
        ((err) ->
          errors_included.trigger_event(
            stream_name: name
            error:       err
          )
        ),
        ((reason) ->
          errors_included.trigger_event(
            stream_name: name
            close:       reason
          )
        )
      )
      # add
      transformed.push(errors_included)
    return EventStream.merge(transformed)

  ###
  Given a multiplexed stream, demultiplex it into a dictionary
  where the keys are names of streams and the values are streams.
  ###
  # TODO: initial values not dropped.
  # TODO: refactor -- this is not very elegant.
  @demultiplex: (stream, expected_keys) ->
    demultiplexed = {}
    for key in expected_keys
      demultiplexed[key] = new EventStream()
    stream.observe(
      ((evt) => demultiplexed[evt[name_key]].trigger_event(evt[body_key])),
    )
    # take care of error and close events
    retval = {}
    for key in expected_keys
      es = new EventStream()
      demultiplexed[key].observe((evt) ->
        if evt.close?
          es.trigger_close(evt.close)
        else if evt.error?
          es.trigger_error(evt.error)
        else if evt.body?
          es.trigger_event(evt.body)
      )
      retval[key] = es
    return retval

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
    # all event streams created before debuggee is initialized are excluded
    @debug_excluded = not Debuggee.is_initialized
    if not @debug_excluded
      Debuggee.instance().new_streams.trigger_event(this)

  toString: ->
    return "#<EventStream>"

  add_observer: (observer) ->
    @observers.push(observer)
    if not @debug_excluded
      Debuggee.instance().new_observers.trigger_event(
        stream: this
        observer: observer
      )

  trigger_event: (event) ->
    if not @closed
      @value = event
      if not @debug_excluded
        Debuggee.instance().event_emitted.trigger_event(
          source: this
          event: event
        )
      for observer in @observers
        if not @debug_excluded
          Debuggee.instance().event_consumed.trigger_event(
            event: event
            observer: observer
          )
        observer.on_event(event)
        if not @debug_excluded
          Debuggee.instance().end_consume()
    else
      throw "can't trigger_event on a closed event stream"

  trigger_error: (error) ->
    if not @closed
      # TOTHINK: refactor (otherevents)
      for observer in @observers
        observer.on_error(error)
    else
      throw "can't trigger_error on a closed event stream"

  # TODO: make close state actually mean something (?)
  trigger_close: (reason) ->
    @closed = true
    # TOTHINK: refactor (otherevents)
    for observer in @observers
      observer.on_close(reason)

  observe: (event_cb, error_cb, close_cb) ->
    observer = new Observer(this, event_cb, error_cb, close_cb)
    this.add_observer(observer)
    return observer

  # TODO: refactor these into "Mapper" "Folder" "Filterer" classes,
  # so we can see them more clearly in the debugger?
  map: (func, initial) ->
    if initial
      mapped = new EventStream(initial)
    else if this.value?
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
    if this.value?
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
    if this.value?
      console.log("#{repr}:initial:", this.value)
    return this.observe(
      (event) -> console.log("#{repr}:event:", event),
      (error) -> console.log("#{repr}:error:", error),
      (reason) -> console.log("#{repr}:close:", reason)
    )

class Observer

  constructor: (@event_stream, @event_cb, @error_cb, @close_cb) ->

  toString: ->
      return "#<Observer>"

  on_event: (event) ->
    @event_cb(event)

  on_error: (error) ->
    if @error_cb?
      @error_cb(error)
    else
      throw error

  on_close: (reason) ->
    if @close_cb?
      @close_cb(reason)

class Future extends EventStream

  constructor: () ->
    super()
    @fired = false

  trigger_event: (evt) ->
    super(evt)
    @fired = true
    @trigger_close('future fired')

  trigger_close: (reason) ->
    if @fired
      super reason
    else
      throw 'future closed before fired'

  andthen: (fun) ->
    next = new Future()
    # TODO: would be nice to throw real error objects or something...
    @observe(
      (evt) -> next.trigger_event(fun(evt)),
      (err) -> throw "error triggered on future: #{err}"
    )
    return next

class Environment

  ###
    @id_info some kind of info about the process
      e.g. URL of tab, command line of process
      don't think we can expect this to be globally unique,
      since a tab doesn't have a unique id number like a pid,
      and there could be other instances of the same URL running
  ###
  constructor: (@id_info) ->
    # the primordial event streams...
    @start    = new EventStream()
    @shutdown = new EventStream()
    @state = new StateMachine(
      beforeRun:
        do_start: 'running'
      running:
        do_shutdown: 'afterRun'
      afterRun: {}
    )
    @state.start('beforeRun')

  do_start: () ->
    @state.transition('do_start')
    @start.trigger_event('start!')

  do_shutdown: () ->
    @state.transition('do_shutdown')
    @shutdown.trigger_event('shutdown!')

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

exports = if exports? then exports else {}
exports.EventStream     = EventStream
exports.Observer        = Observer
exports.Ticker          = Ticker
