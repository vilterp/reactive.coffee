es = require '../core/core'

class NodeEnvironment extends es.Environment

	@instance: () =>
		if not @singleton
			@singleton = new NodeEnvironment()
		return @singleton

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

exports.NodeEnvironment = NodeEnvironment
