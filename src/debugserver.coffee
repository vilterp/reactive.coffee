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

accept = (req) ->
	req.accept(req.origin, [])

debugger_reqs = new es.EventStream()
router.mount('/debugger', null, (req) ->
	debugger_reqs.trigger_event(req)
)
debugger_conns = debugger_reqs.map(accept)

debuggee_reqs = new es.EventStream()
router.mount('/debuggee', null, (req) ->
	debuggee_reqs.trigger_event(req)
)
debuggee_conns = debuggee_reqs.map(accept)

debuggee_reqs.log()
debuggee_conns.log()
