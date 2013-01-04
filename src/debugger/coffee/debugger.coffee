class Debugger

	constructor: (server_host, server_port, @debuggee_id) ->
		ds_url = "ws://#{server_host}:#{server_port}/debugger?debuggee_id=#{@debuggee_id}"
		
		@streams = new ListModel()
		@stream_map = {}

		@observers = new ListModel()
		@observer_map = new IdMap()

		@events = new ListModel()
		@event_map = {}

		@consumptions = new ListModel()
		@consumption_map = {}

		WebSocketStream.connect(ds_url).andthen((sock) =>
			console.log('connected!')
			streams = sock.map(JSON.parse).demultiplex(
				['new_streams', 'new_observers', 'event_emitted', 'event_consumed'])
			# RESOLVE IDs TO OBJECT REFERENCES (todo: handle nonexistent ids gracefully!)
			streams.event_emitted.observe((evt) =>
				stream = @stream_map[evt.stream_id]
				cons = @get_consumption(evt.consumption_id)

				event = new Event(evt.event_id, stream, cons, new Date(evt.time), evt.event_data)
				@event_map[event.id] = event
				@events.append(event)
			)
			streams.event_consumed.observe((evt) =>
				obs = @observer_map[evt.observer_id]
				event = @event_map[evt.event_id]
				cons = new Consumption(evt.consumption_id, obs, event, new Date(evt.time))
				@consumption_map[cons.id] = cons
				@consumptions.append(cons)
			)
			streams.new_streams.observe((evt) =>
				# TODO: get consumption
				cons = @get_consumption(evt.consumption_id)
				stream = new Stream(evt.stream_id, cons, evt.stream_type)
				@stream_map[stream.id] = stream
				@streams.append(stream)
			)
			streams.new_observers.observe((evt) =>
				cons = @get_consumption(evt.consumption_id)
				stream = @stream_map[evt.stream_id]
				obs = new Obs(evt.observer_id, stream, cons, evt.observer_type)
				@observer_map[obs.id] = obs
				@observers.append(obs)
			)
		)

	get_consumption: (id) ->
		if id?
			return @consumption_map[id]
		else
			return PrimordialConsumption.instance()

class TableView

	constructor: (@container, @list, @col_renderers) ->
		cols = (cr[0] for cr in @col_renderers)
		elements = @list.map((ind, row) =>
			(cr[1](row[cr[0]]) for cr in @col_renderers)
		).map((ind, row) ->
			row_el = document.createElement('tr')
			for col in row
				col_el = document.createElement('td')
				col_el.innerText = col
				row_el.appendChild(col_el)
			return row_el
		)
		# build header
		thead = document.createElement('thead')
		head_row = document.createElement('tr')
		for col in cols
			col_el = document.createElement('td')
			col_el.innerText = col
			head_row.appendChild(col_el)
		thead.appendChild(head_row)
		@container.appendChild(thead)
		# build, bind tbody
		tbody = document.createElement('tbody')
		@container.appendChild(tbody)
		elements.bind_as_child_nodes(tbody)

# Model classes (don't do anything)

class Consumption

class PrimordialConsumption extends Consumption
	@instance: () =>
		if not @singleton?
			@singleton = new PrimordialConsumption()
		return @singleton
	toString: () -> "#<PrimordialConsumption>"

class NormalConsumption
	constructor: (@id, @observer, @event, @time) ->

class Stream
	constructor: (@id, @consumption, @type) ->

# can't be called 'Observer' since that's an core eventstream class...
class Obs
	constructor: (@id, @stream, @consumption, @type) ->

class Event
	constructor: (@id, @stream, @consumption, @time, @data) ->

parse_query_params = (url) ->
	res = {}
	s = url.split('?')
	if s.length != 2
		throw 'no query string'
	qs = s[1]
	for assn in qs.split('&')
		[k, v] = assn.split('=')
		res[k] = v
	return res

# TODO: ...
window.onload = () ->
	console.log('hello?')
	debuggee_id = parse_query_params(window.location.href).debuggee_id
	dbg = new Debugger('localhost', 8000, debuggee_id)
	ts = (x) -> x?.toString()
	id = (x) -> x
	get_id = (x) -> x?.id?.toString()
	new TableView(document.getElementById('streams'), dbg.streams, [
		['id', ts],
		['consumption', get_id],
		['type', id]
	])
	new TableView(document.getElementById('observers'), dbg.observers, [
		['id', ts],
		['consumption', get_id],
		['type', id]
	])
	new TableView(document.getElementById('events'), dbg.events, [
		['id', ts],
		['stream', get_id],
		['consumption', get_id],
		['data', id],
		['time', ts]
	])
	new TableView(document.getElementById('consumptions'), dbg.consumptions, [
		['id', ts],
		['observer', get_id],
		['event', get_id],
		['time', ts]
	])
