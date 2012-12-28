# import WebSocketStream

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

		@state = new StateMachine(
			initial:
				sendRegistration: 'regWait'
			regWait:
				regDone: 'running'
			running:
				sendEventEmitted: 'running'
				sendNewStream: 'running'
				# TOTHINK: refactor (otherevents)
				sendStreamClosed: 'running'
				sendStreamError: 'running'
				# / TOTHINK
				sendNewObserver: 'running'
				sendEventConsumed: 'running'
				# TODO: error, close
				shutdown: 'done'
			done: {}
		)
		@state.start('initial')
		@transport = new WebSocketStream(server_url)
		@transport.send(env.id_info)
		@state.transition('sendRegistration')
		@transport.observe((msg) =>
			if @state.state == 'regWait'
				if msg == DebugProtocol.REG_ACK
					@state.transition('regDone')
				else
					throw 'Protocol error!' # ...?
			else
				throw 'Protocol error!' # ...?
		)
		@is_initialized = true

	send: (edge_name, obj) ->
		msg =
			type: edge_name
			body: obj
		@transport.send(JSON.stringify(msg))
		@state.transition(edge_name)

	new_stream: (stream) ->
		obj =
			id: @streams.add(stream)
			created: 0 # TODO: consumptions ... start_consumption(), end_consumption()? 
			type: stream.constructor.name # wut wut
		@send('sendNewStream', obj)

	new_observer: (observer, stream) ->
		stream_id = @streams.get_id(stream)
		obj =
			id: @observers.add(observer)
			stream_id: stream_id
			consumption_id: 0 # TODO: consumptions
			type: observer.constructor.name
		@send('sendNewObserver', obj)

	event_emitted: (stream, event) ->
		stream_id = @streams.get_id(stream)
		obj =
			id: @events.add(event)
			emitter: stream_id
			time: new Date()
			data: event
		@send('sendEventEmitted', obj)

	start_consume: (event, observer) ->
		event_id = @events.get_id(event)
		observer_id = @observers.get_id(observer)
		obj =
			id: @push_consumption()
			event_id: event_id
			observer_id: observer_id
			time: new Date()
		@send('sendEventConsumed', obj)

	end_consume: () ->
		@pop_consumption()

	push_consumption: () ->
		retval = @consumption_id
		@consumptions.push(retval)
		@consumption_id += 1
		return retval

	pop_consumption: () ->
		if @consumptions.length == 0
			throw 'consumptions stack empty'
		return @consumptions.pop()

	# TOTHINK: refactor (otherevents)
	stream_closed: (stream, reason) ->
		stream_id = @streams.get_id(stream)
		obj =
			stream_id: stream_id
			consumption_id: 0 # TODO: consumptions
			reason: JSON.stringify(reason) # TODO: test...
		@send('sendStreamClosed', obj)

	# TOTHINK: refactor (otherevents)
	stream_error: (stream, error) ->
		stream_id = @streams.get_id(stream)
		obj =
			stream_id: stream_id
			consumption_id: 0 # TODO: consumptions
			error:
				type: error.constructor.name
				data: JSON.stringify(error)
		@send('sendStreamError', obj)

	shutdown: () ->
		@state.transition('shutdown')

	# ===== END static methods =================================

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
