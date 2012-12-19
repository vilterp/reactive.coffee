class ListModel

  # TODO: changes stream, length

  constructor: ->
    @list = []
    @additions = new EventStream()
    @removals = new EventStream()
    @mutations = new EventStream()
    incrs = @additions.map((evt) -> 1)
    decrs = @removals.map((evt) -> -1)
    @length = EventStream.merge([incrs, decrs]).fold(0, (length, evt) -> length + evt)
    @empty = @length.map((l) -> l == 0)

  get: (index) ->
    if index < 0
      @list[@list.length+index]
    else
      @list[index]

  add: (index, value) ->
    @list.splice(index, 0, value)
    @additions.trigger_event(
      index: index
      value: value
    )

  append: (value) ->
    this.add(@list.length, value)

  remove: (index) ->
    removed = @list.splice(index, 1)[0]
    @removals.trigger_event(
      index: index
      removed: removed
    )
    return removed

  mutate: (index, value) ->
    old_value = @list_index
    @list[index] = value
    @mutations.trigger_event(
      index: index
      old_value: old_value
      new_value: value
    )

  destroy: ->
    @additions.trigger_close()
    @removals.trigger_close()
    @mutations.trigger_close()

  map: (func) ->
    mapped = new ListModel()
    @additions.observe(
      (evt) -> mapped.add(evt.index, func(evt.index, evt.value))
    )
    @removals.observe(
      (evt) -> mapped.remove(evt.index)
    )
    @mutations.observe(
      (evt) -> mapped.mutate(evt.index, func(evt.index, evt.new_value))
    )
    for item in this.list
      mapped.append(item)
    return mapped

  bind_as_child_nodes: (parent) ->
    this.removals.observe(
      (evt) -> parent.removeChild(evt.removed)
    )
    this.mutations.observe(
      (evt) -> parent.replaceChild(evt.new_value, evt.old_value)
    )
    this.additions.observe(
      ((evt) ->
        if evt.index == parent.childNodes.length
          parent.appendChild(evt.value)
        else
          parent.insertBefore(evt.value, parent.childNodes[evt.index])
      )
    )
