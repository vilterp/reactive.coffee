if require?
	core = require './core'

EventStream = if core? then core.EventStream else EventStream

class StateMachine extends EventStream

	constructor: (states) ->
		super()
		@started = false
		@transitions = {}
		@state = null
		# create initial states...
		for from, transitions of states
			for edge_name, to of transitions
				@add_transition(from, to, edge_name)

	add_transition: (from, to, edge_name) ->
		if not @transitions[from]?
			@transitions[from] = {}
		if @transitions[from][edge_name]?
			throw "already transition from state '#{from}' with edge name '#{edge_name}'"
		@transitions[from][edge_name] = to

	start: (start_st) ->
		if not @transitions[start_st]?
			throw "no state '#{start_st}'"
		@started = true
		@state = start_st

	transition: (edge_name) ->
		if not @started
			throw "not started"
		if not @transitions[@state][edge_name]
			err = "no edge '#{edge_name}' from state '#{@state}'"
			this.trigger_error(err)
			throw err # this is weird.
		else
			from = @state
			@state = @transitions[@state][edge_name]
			this.trigger_event(new StateTransition(from, @state, edge_name))

	current_state: () ->
		if @started
			return @state
		else
			throw 'not started'

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
		return null

# only static methods
class Util

  @clamp = ((in_min, in_max, out_min, out_max) ->
    in_delta = in_max - in_min
    out_delta = out_max - out_min
    multiplier = out_delta / in_delta
    return (val) ->
      out_min + (val-in_min) * multiplier)

  # key_func :: object -> comparable object
  @partition_ordered_list = (list_model, key_func, divider) ->
    below = new ListModel()
    above = new ListModel()
    list_model.additions.observe((evt) ->
      above.append(evt.value)
    )
    divider.observe((evt) ->
      while above.list.length > 0 and key_func(above.get(0)) < evt
        removed = above.remove(0)
        below.append(removed)
    )
    return [below, above]

exports = if exports? then exports else {}
exports.StateMachine    = StateMachine
exports.StateTransition = StateTransition
exports.IdMap           = IdMap
exports.Util            = Util
