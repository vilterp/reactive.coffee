include = (mod) ->
	for k, v of require(mod)
		exports[k] = v

(include('../core/' + m) for m in ['core', 'util', 'models'])
include './nodeenv'
