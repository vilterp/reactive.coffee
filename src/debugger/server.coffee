ws      = require 'websocket'
express = require 'express'
http    = require 'http'
es      = require '../core'

args = require('optimist')
				 .default('p', 8000).alias('p', 'port')
				 .argv

app = express()
app.use(express.logger('short'))
	 .use(express.static(__dirname + '/static'))

connected = []

# express routes -- http stuff
app.get('/', (req, res) ->
	res.set('Content-Type', 'text/plain');
	res.send("Hello from the debug server!\n" +
					 "Hit /connected for JSON of currently connected debuggees.")
)
app.get('/connected', (req, res) ->
	res.set('Content-Type', 'application/json');
	list = connected.map((dc) ->
		id: dc.id
		id_info: dc.id_info
	)
	res.send(JSON.stringify(list))
)
# serve debugger interface
app.get('/debugger', (req, res) ->
	res.sendfile('./debugger.html')
)

# wrap express app in standard node http server
# necessary for websockets compatibility, annoyingly...
wrap_server = http.createServer(app)

# web sockets listeners
ws_server = new ws.server({ httpServer: wrap_server })
router = new ws.router()
router.attachServer(ws_server)

debuggee_id = 0

router.mount('/debuggee', null, (req) ->
	conn = req.accept()
	state = 'initial'
	debuggee_connection = null
	conn.on('message', (msg_frame) ->
		msg = msg_frame.utf8Data
		if state == 'initial'
			console.log("new debuggee connection: id #{debuggee_id}, info #{msg}")
			debuggee_connection = new DebuggeeConnection(debuggee_id, msg, conn)
			debuggee_id += 1
			connected.push(debuggee_connection)
			state = 'registered'
			conn.send('ok')
		else if state == 'registered'
			debuggee_connection.debug_events.trigger_event(JSON.parse(msg))
			console.log("msg from conn #{debuggee_connection.id}:", msg)
		else
			throw "unknown state #{state}"
	)
	conn.on('close', () ->
		debuggee_connection.debug_events.trigger_close()
		# delete from list (so clumsy in js!)
		ind = connected.indexOf(debuggee_connection)
		connected.splice(ind, 1)
	)
)

router.mount('/debugger', null, (req) ->
	id_str = req.resourceURL.query.debuggee_id
	if not id_str?
		req.reject(404)
		console.log('debugger req: no debuggee_id')
	else
		id = parseInt(id_str)
		for dc in connected
			if dc.id == id
				debuggee_connection = dc
		if not debuggee_connection?
			req.reject(404)
			console.log("debugger req: id #{id} not found")
		else
			console.log("debugger req: id #{id} found")
			conn = req.accept()
			# send old events to bring debugger up to date
			for evt in debuggee_connection.history
				conn.send(JSON.stringify(evt))
			# not sure if there's a race condition here...
			# then, proxy new ones...
			debuggee_connection.debug_events.observe(
				(evt) -> conn.send(JSON.stringify(evt)),
				(err) -> throw err,
				(reason) -> conn.close()
			)
)

class DebuggeeConnection

	constructor: (@id, @id_info, @conn) ->
		@history = []
		@debug_events = new es.EventStream()
		@closed = false
		@debug_events.observe(
			(evt) => @history.push(evt),
			(err) => throw err,
			(close) => @closed = true
		)

wrap_server.listen(args.port)
console.log("Debug server listening on port #{args.port}")
