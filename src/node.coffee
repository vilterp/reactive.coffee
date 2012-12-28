EventStream = require('./core').EventStream

class ESNode

	@from_event_emitter: (emitter, event) ->
		es = new EventStream()
		emitter.on(event, (arg) =>
			es.trigger_event(arg)
		)
		return es

exports.ESNode = ESNode
