# import WebSocketStream

# convention: call @state.transition(...) before sending something on socket,
#   so illegal state error will happen before we try to send something

class Debuggee

	@initialize: (server_url, env) ->
		if Debuggee.singleton?
			throw 'already initialized'
		Debuggee.singleton = new Debuggee(server_url, env)
		# set up primordial event streams...
		Debuggee.singleton.new_stream(env.start)
		Debuggee.singleton.new_stream(env.shutdown)
		for obs in env.start.observers
			Debuggee.singleton.new_observer(obs)
		for obs in env.shutdown.observers
			Debuggee.singleton.new_observer(obs)
		# now, when the 'start!' event fires, it'll go through these

	@instance: () ->
		if not Debuggee.singleton?
			throw 'not initialized'
		return Debuggee.singleton

	@is_initialized = false

	constructor: (server_url, env) ->

		if env.state.current_state() != 'beforeRun'
			throw 'must call Debuggee.initialize() before calling env.start()'

		@streams = new IdMap()
		@observers = new IdMap()
		@events = new IdMap()
		@consumption_id = 0
		@consumptions = []

		# these are public
		@new_streams    = new EventStream()
		@new_observers  = new EventStream()
		@event_emitted  = new EventStream()
		@event_consumed = new EventStream()

		multiplexed = EventStream.multiplex(
			new_streams:    @mapped_NS()
			new_observers:  @mapped_NO()
			event_emitted:  @mapped_EE()
			event_consumed: @mapped_EC()
		)

		# state machine to make sure we don't
		# do anything illegal...
		@state = new StateMachine(
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
		@state.start('initial')

		# connect to debug server...
		return WebSocketStream.connect(server_url, multiplexed)
									 				.andthen((transport) =>
			@state.transition('connected')
			# send registration....
			@state.transition('sendRegistration')
			transport.send(env.id_info)
			transport.observe((msg) =>
				if @state.state == 'regWait' and msg == 'ok'
					@state.transition('regDone')
					@is_initialized = true
					return this
				else
					throw 'Protocol error!' # ...?
			)
		)

	mapped_NS: () ->
		@new_streams.map((stream) =>
			id: @streams.add(stream)
			created: @current_consumption()
			type: stream.constructor.name # wut wut
		)

	mapped_NO: () ->
		@new_observers.map((evt) =>
			id: @observers.add(evt.observer)
			stream_id: @streams.get_id(evt.stream)
			consumption_id: @current_consumption()
			type: evt.observer.constructor.name
		)

	mapped_EE: () ->
		@event_emitted.map((evt) =>
			id: @events.add(evt.event)
			emitter: @streams.get_id(evt.stream)
			consumption: @current_consumption() # could be null
			time: new Date()
			data: evt.event
		)

	mapped_EC: () ->
		@event_consumed.map((evt) =>
			id: @push_consumption()
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
