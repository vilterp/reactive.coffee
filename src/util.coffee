class StateMachine extends EventStream

	@create: (states) ->
		### e.g.
		StateMachine.create({
			stateA: {
				edge1: stateB,
				edge2: stateC,
			},
			stateB: {
				edge3: stateC
			},
			stateC: {
				edge4: stateD
			},
			stateD: {}
		})
		###
		sm = new StateMachine()
		for from of states
			for edge_name, to of from
				sm.add_transition(from, to, edge_name)
		return sm

	constructor: () ->
		super()
		@started = false
		@transitions = {}
		@state = null

	add_transition: (from, to, edge_name) ->
		if not @transitions[from]?
			@transitions[from] = {}
		if @transitions[from][edge_name]?
			throw "already transition from state '#{from}' with edge name '#{edge_name}'"
		@transitions[from][edge_name] = to

	start: (start_st) ->
		if not @transitions[start_st]?
			throw "no state '#{start_st}'"
		started = true
		@state = start_st

	transition: (edge_name) ->
		if not started
			throw "not started"
		if not @transitions[@state][edge_name]
			this.trigger_error("no edge '#{edge_name}' from state '#{@state}'")
		else
			from = @state
			@state = @transitions[@state][edge_name]
			this.trigger_event(new StateTransition(from, @state, edge_name))

exports = if exports? then exports else {}
exports.StateMachine = StateMachine
