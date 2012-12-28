ws      = require 'websocket'
http    = require 'http'
es      = require './core'
util    = require './util'

args = require('optimist')
				 .default('p', 8000).alias('p', 'port')
				 .argv

# create http server
server = http.createServer((request, response) ->
	response.writeHead(404)
	response.end('try /debugger or /app\n')
)

# start it up....
server.listen(args.port, () ->
	console.log("Debug server listening on #{args.port}")
)

# attach websocket server & router to http server
# don't really like this API...
# how exactly is it hooking into the http server?
wsServer = new ws.server(
	httpServer: server
)

router = new ws.router()
router.attachServer(wsServer)

accept = (req) -> req.accept(req.origin, [])

debug_reqs = new es.EventStream()
router.mount('/debugger', null, (req) ->
	debug_reqs.trigger_event(req)
)
debug_conns = debug_reqs.map(accept)

app_reqs = new es.EventStream()
router.mount('/debuggee', null, (req) ->
	app_reqs.trigger_event(req)
)
app_conns = debug_reqs.map(accept)

