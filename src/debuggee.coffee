# TODO: refactor to make usable to debug node programs

# convention: call @state.transition(...) before sending something on socket,
#   so illegal state error will happen before we try to send something


###
Things get kind of tricky in here. How to use this class:
1. create environment
2. add listener on myEnvironment.start
3. call Debuggee.initialize(debug server url, myEnvironment)
4. bind a listener to the future returned by #4, and in it call
   myEnvironment.do_start() (All because we don't want to do
   anything until the debugger is initialized)
###

class Debuggee

	# :: (url, Environment) -> Future[Debuggee]
	@initialize: (server_url, env) ->
		if Debuggee.singleton?
			throw 'already initialized'
		return Debuggee.create(server_url, env)
									 .andthen((inst) ->
			Debuggee.singleton = inst
			# set up primordial event streams...
			inst.new_streams.trigger_event(env.start)
			inst.new_streams.trigger_event(env.shutdown)
			add_observers = (observers) ->
				for obs in observers
					inst.new_observers.trigger_event(
						stream: obs.event_stream
						observer: obs
					)
			add_observers(env.start.observers)
			add_observers(env.shutdown.observers)
			# now, when the 'start!' event fires, it'll go through these
			return inst
		)

	@is_initialized = false

	@instance: () ->
		if not Debuggee.singleton?
			throw 'not initialized'
		return Debuggee.singleton

	# like a constructor, but returns a Future[Debugee] instead of a Debuggee
	@create: (server_url, env) ->
		it = new Debuggee()
		if env.state.current_state() != 'beforeRun'
			throw 'must call Debuggee.initialize() before calling env.start()'

		it.streams = new IdMap()
		it.observers = new IdMap()
		it.events = new IdMap()
		it.consumption_id = 0
		it.consumptions = []

		# these are public
		it.new_streams    = new EventStream()
		it.new_observers  = new EventStream()
		it.event_emitted  = new EventStream()
		it.event_consumed = new EventStream()

		multiplexed = EventStream.multiplex(
			new_streams:    it.mapped_NS()
			new_observers:  it.mapped_NO()
			event_emitted:  it.mapped_EE()
			event_consumed: it.mapped_EC()
		)
		multiplexed.log('multiplexed')

		# state machine to make sure we don't
		# do anything illegal...
		it.state = new StateMachine(
			initial:
				connect: 'connecting'
			connecting:
				connected: 'connected'
			connected:
				sendRegistration: 'regWait'
			regWait:
				regDone: 'running'
			running:
				shutdown: 'done'
			done: {}
		)
		it.state.log('state')
		it.state.start('initial')

		# connect to debug server...
		it.state.transition('connect')
		# TODO: protocols & futures & andthen are weird.
		conn = WebSocketStream.connect(server_url, multiplexed.map(JSON.stringify))
		reg = new Future()
		conn.andthen((transport) =>
			it.state.transition('connected')
			# send registration....
			it.state.transition('sendRegistration')
			console.log('id_info:', env.id_info)
			transport.stream.trigger_event(env.id_info) # TODO: this is janky.
			transport.observe((msg) =>
				if it.state.state == 'regWait' and msg == 'ok'
					it.state.transition('regDone')
					Debuggee.is_initialized = true
					reg.trigger_event(it)
				else
					throw 'Protocol error!' # ...?
			)
		)
		return reg

	constructor: () -> # must go through create!

	mapped_NS: () ->
		@new_streams.map((stream) =>
			stream_id: @streams.add(stream)
			consumption_id: @current_consumption()
			stream_type: stream.constructor.name # wut wut
		)

	mapped_NO: () ->
		@new_observers.map((evt) =>
			observer_id: @observers.add(evt.observer)
			stream_id: @streams.get_id(evt.stream)
			consumption_id: @current_consumption()
			observer_type: evt.observer.constructor.name
		)

	mapped_EE: () ->
		@event_emitted.map((evt) =>
			event_id: @events.add(evt.event)
			stream_id: @streams.get_id(evt.stream)
			consumption_id: @current_consumption() # could be null
			time: new Date()
			# TODO: would be nice to send the whole thing, but have to avoid circular refs
			event_data: evt.event.constructor.name
		)

	mapped_EC: () ->
		@event_consumed.map((evt) =>
			consumption_id: @push_consumption()
			event_id: @events.get_id(evt.event)
			observer_id: @observers.get_id(evt.observer)
			time: new Date()
		)

	push_consumption: () ->
		retval = @consumption_id
		@consumptions.push(retval)
		@consumption_id += 1
		return retval

	end_consume: () ->
		@pop_consumption()

	pop_consumption: () ->
		if @consumptions.length == 0
			throw 'consumptions stack empty'
		return @consumptions.pop()

	current_consumption: () ->
		if @consumptions.length == 0
			return null
		return @consumptions[@consumptions.length-1] # grr

	shutdown: () ->
		@state.transition('shutdown')

class IdMap

	constructor: () ->
		@id = 0
		@map = {}

	add: (obj) ->
		@map[@id] = obj
		retval = @id
		@id += 1
		return retval

	remove: (obj) ->
		for id, some_obj of @map
			if some_obj == obj
				delete @map[id]
				return true
		return false

	get_id: (obj) ->
		# FIXME: this is slow. grr javascript
		for id, some_obj of @map
			if some_obj == obj
				return id
		return -1

exports = if exports? then exports else {}
exports.Debuggee = Debuggee
