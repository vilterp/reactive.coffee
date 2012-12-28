# import WebSocketStream

class StateTransition

	constructor: (@from, @to, @edge_name) ->

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

class Debuggee

	@initialize: (server_url, id) ->
		if Debuggee.singleton?
			throw 'already initialized'
		Debuggee.singleton = new Debuggee(server_url, id)

	@instance: () ->
		if not Debuggee.singleton?
			throw 'not initialized'
		return Debuggee.singleton

	constructor: (server_url, id) ->

		# TODO: initialization ordering and logic...

		@streams = new IdMap()
		@observers = new IdMap()
		@events = new IdMap()
		@consumption_id = 0
		@consumptions = []

		@state = StateMachine.create(
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
		@transport.send(id)
		@state.transition('sendRegistration')
		@transport.observe((msg) =>
			if @state.state == 'regWait'
				if msg == DebugProtocol.REG_ACK
					@state.transition('regDone')
				else
					throw 'Protocol error!' # ...?
		)

	send: (edge_name, obj) ->
		msg =
			type: edge_name
			body: obj
		@transport.send(JSON.stringify(msg))
		@state.transition(edge_name)

	# ===== static methods here are called from the core (so much for DRY...) =========

	@new_stream: (stream) -> Debuggee.instance().new_stream(stream)
	new_stream: (stream) ->
		obj =
			id: @streams.add(stream)
			created: 0 # TODO: consumptions ... start_consumption(), end_consumption()? 
			type: stream.constructor.name # wut wut
		@send('sendNewStream', obj)

	@new_observer: (o, s) -> Debuggee.instance().new_observer(o, s)
	new_observer: (observer, stream) ->
		stream_id = @streams.get_id(stream)
		obj =
			id: @observers.add(observer)
			stream_id: stream_id
			consumption_id: 0 # TODO: consumptions
			type: observer.constructor.name
		@send('sendNewObserver', obj)

	@event_emitted: (s, e) -> Debuggee.instance().event_emitted(s, e)
	event_emitted: (stream, event) ->
		stream_id = @streams.get_id(stream)
		obj =
			id: @events.add(event)
			emitter: stream_id
			time: new Date()
			data: event
		@send('sendEventEmitted', obj)

	@start_consume: (e, o) -> Debuggee.instance().start_consume(e, o)
	start_consume: (event, observer) ->
		event_id = @events.get_id(event)
		observer_id = @observers.get_id(observer)
		obj =
			id: @push_consumption()
			event_id: event_id
			observer_id: observer_id
			time: new Date()
		@send('sendEventConsumed', obj)

	@end_consume: () -> Debuggee.instance().end_consume()
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
	@stream_closed: (s, r) -> Debuggee.instance().stream_closed(s, r)
	stream_closed: (stream, reason) ->
		stream_id = @streams.get_id(stream)
		obj =
			stream_id: stream_id
			consumption_id: 0 # TODO: consumptions
			reason: JSON.stringify(reason) # TODO: test...
		@send('sendStreamClosed', obj)

	# TOTHINK: refactor (otherevents)
	@stream_error: (s, e) -> Debuggee.instance().stream_error(s, e)
	stream_error: (stream, error) ->
		stream_id = @streams.get_id(stream)
		obj =
			stream_id: stream_id
			consumption_id: 0 # TODO: consumptions
			error:
				type: error.constructor.name
				data: JSON.stringify(error)
		@send('sendStreamError', obj)

	@shutdown: () -> Debuggee.instance().shutdown()
	shutdown: () ->
		@state.transition('shutdown')

	# ===== END static methods =================================
