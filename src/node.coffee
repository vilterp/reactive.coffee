net = require 'net'
es  = require './core'

class NodeEnvironment extends es.Environment

	constructor: () ->
		super(process.args.join(' '))
		# register shutdown event
		process.on('exit', () =>
			@shut_down()
		)

	from_event_emitter: (emitter, event) ->
		es = new EventStream()
		emitter.on(event, (arg) ->
			es.trigger_event(arg)
		)
		return es

	from_signal: (signame) ->
		return @from_event_emitter(process, signame)

class TcpServer extends es.EventStream

	@listen: (port, host, backlog, allowHalfOpen=false) ->
		server = net.createServer({allowHalfOpen: allowHalfOpen})
		listening = new es.Future()
		server.on('listening', () ->
			listening.trigger_event(new TcpServer(server))
		)
		# TODO: semantics of triggering errors on futures...?
		server.on('error', (err) ->
			if not listening.fired
				listening.trigger_error(err)
		)
		server.listen(port, host, backlog)
		return listening

	constructor: (@node_server) ->
		super()
		# should this somehow be done with env.from_event_emitter for consistency?
		@node_server.on('connection', (conn) =>
			@trigger_event(new TcpSocket(conn))
		)
		@node_server.on('error', (err) =>
			@trigger_error(err)
		)
		@node_server.on('close', () =>
			@trigger_close('server closed')
		)
		# TODO: handle connections....

	converse: (make_converser) ->
		return this.map((sock) -> new Conversation(sock, make_converser(sock)))

class Conversation

	constructor: (@incoming, @outgoing) ->
		@outgoing.observe((evt) => @incoming.node_socket.write(evt))

	toString: () -> "#<Conversation incoming: #{@incoming}; outgoing: #{@outgoing}>"

class TcpSocket extends es.EventStream

	@connect: (port, host, options) ->
		sock = new net.Socket(options)
		sock.connect(port, host)
		connected = new es.Future()
		sock.on('connect', () ->
			connected.trigger_event(new TcpSocket(sock))
		)
		sock.on('error', (err) ->
			if not connected.fired
				connected.trigger_error(err)
		)
		return connected

	constructor: (@node_socket) ->
		super()
		# TODO: assert that it's connected
		# react to events coming over the socket
		@node_socket.on('data', (buf) =>
			@trigger_event(buf)
		)
		@node_socket.on('close', (had_error) =>
			# TODO: allowHalfOpen behavior probably not right
			@trigger_close(had_error)
		)
		@node_socket.on('end', () =>
			@trigger_close('end')
		)
		# TODO: timeout, drain...
		# construct stream
		# send stream's messages over the socket
		# @stream.observe(
		# 	((evt) =>
		# 		if not @closed
		# 			@node_socket.write(evt)
		# 		else
		# 			throw "can't send data over a closed socket"
		# 	),
		# 	((err) =>
		# 		throw {
		# 			msg: "tried to send error over a socket",
		# 			err: err
		# 		}
		# 	),
		# 	((reason) =>
		# 		if not @closed
		# 			@node_socket.end()
		# 		else
		# 			throw "socket already closed"
		# 	)
		# )

	transmit_events_of: (stream) ->
		stream.observe(
			(evt) => @node_socket.write(evt)
		)

exports.NodeEnvironment = NodeEnvironment
exports.TcpSocket       = TcpSocket
exports.TcpServer       = TcpServer
