local RoundQueue = require("lib.round-queue")

local clusterio_api = require("__clusterio_lib__/api")

subspace_injectors = {
  ["subspace-item-injector"] = true,
  ["subspace-fluid-injector"] = true,
  ["subspace-electricity-injector"] = true,
}

subspace_extractors = {
  ["subspace-item-extractor"] = true,
  ["subspace-fluid-extractor"] = true,
  ["subspace-electricity-extractor"] = true,
}

subspace_combinators = {
  ["subspace-inventory-combinator"] = true,
}

subspace_interactors = {
  ["subspace-item-injector"] = true,
  ["subspace-item-extractor"] = true,
  ["subspace-fluid-injector"] = true,
  ["subspace-fluid-extractor"] = true,
  ["subspace-electricity-injector"] = true,
  ["subspace-electricity-extractor"] = true,
  ["subspace-inventory-combinator"] = true,
}

local injection_limit_settings = {
  ["subspace-item-injector"] = "subspace_storage-max-items",
  ["subspace-fluid-injector"] = "subspace_storage-max-fluid",
  ["subspace-electricity-injector"] = "subspace_storage-max-electricity",
}

function get_endpoint(entity)
  local force = entity.force.name

  local spawn_position = entity.force.get_spawn_position(entity.surface)
  local entity_position = entity.position
  local cx = math.floor((entity_position.x - spawn_position.x) / CHUNK_SIZE)
  local cy = math.floor((entity_position.y - spawn_position.y) / CHUNK_SIZE)

  return force, cx, cy
end

function register_interactor(entity)
  if not entity or not entity.valid or entity.type == "entity-ghost"
      or not subspace_interactors[entity.name] then
    return
  end

  if subspace_injectors[entity.name] then
    global.injectors[entity.name]:insert(entity)
  elseif subspace_extractors[entity.name] then
    global.extractors[entity.name]:insert(entity)
  elseif subspace_combinators[entity.name] then
    if entity.name == "subspace-inventory-combinator" then
      entity.operable = false
    end

    global.combinators[entity.name]:insert(entity)
  end
end

function unregister_interactor(entity)
  if not entity or not entity.valid or entity.type == "entity-ghost"
      or not subspace_interactors[entity.name] then
    return
  end

  if subspace_injectors[entity.name] then
    global.injectors[entity.name]:remove(entity)
  elseif subspace_extractors[entity.name] then
    global.extractors[entity.name]:remove(entity)
  elseif subspace_combinators[entity.name] then
    global.combinators[entity.name]:remove(entity)
  end
end

function init_interactors()
  global.injectors = RoundQueue:new()
  global.extractors = RoundQueue:new()
  global.combinators = RoundQueue:new()

  for _, surface in ipairs(game.surfaces) do
    for name, _ in pairs(subspace_interactors) do
      for _, entity in pairs(surface.find_entities_filtered { name = name }) do
        register_interactor(entity)
      end
    end
  end
end

local contents_pairs = {
  ["subspace-item-injector"] = function(entity)
    local inventory = entity.get_inventory(defines.inventory.chest)
    return function(contents, name)
      name = next(contents, name)
      if not name then
        return nil, nil, nil
      end
      return name, contents[name], function(count)
        inventory.remove({ name = name, count = count })
        return count
      end
    end, inventory.get_contents(), nil
  end,
  ["subspace-fluid-injector"] = function(entity)
    return function(fluidbox, name)
      local fluid = fluidbox[1]
      if name or not fluid or fluid.amount < 1 then
        return nil, nil, nil
      end
      return fluid.name, fluid.amount, function(amount)
        fluid.amount = fluid.amount - amount
        fluidbox[1] = fluid
        return amount
      end
    end, entity.fluidbox, nil
  end,
  ["subspace-electricity-injector"] = function(entity)
    return function(entity, name)
      local electricity = math.floor(entity.energy / ELECTRICITY_UNIT)
      if not name or electricity < 1 then
        return nil, nil, nil
      end
      return "electricity", electricity, function(count)
        entity.energy = entity.energy - count * ELECTRICITY_UNIT
        return count
      end
    end, entity, nil
  end,
}

function process_injector(entity)
  if not entity.valid or entity.to_be_deconstructed(entity.force)
      or not subspace_injectors[entity.name] then
    return
  end

  local force, cx, cy = get_endpoint(entity)

  local limit = settings.global[injection_limit_settings[entity.name]].value

  for item, available, take in contents_pairs[entity.name](entity) do
    if settings.global["subspace_storage-infinity-mode"].value then
      take(available)
    else
      local taken = 0
      if limit <= 0 then
        taken = take(available)
      else
        taken = take(math.min(available, limit - global.inventory:get(force, cx, cy, item)))
      end
      if taken > 0 then
        global.outbox:update(force, cx, cy, item, function(c) return (c or 0) + taken end)
      end
    end
  end
end

local requests_pairs = {
  ["subspace-item-extractor"] = function(entity)
    local free_slots = 60
    return function(entity, i)
      i = i + 1
      if i > entity.request_slot_count then
        return nil, nil, nil
      end
      local request = entity.get_request_slot(i)
      if not request then
        return "unknown", 0, function() return 0 end
      end
      local inventory = entity.get_inventory(defines.inventory.chest)
      local stack_size = game.item_prototypes[request.name].stack_size
      local missing = math.min(
        request.count - inventory.get_item_count(request.name),
        free_slots * stack_size)
      free_slots = free_slots - math.ceil(missing / stack_size)
      return request.name, missing, function(count)
        return inventory.insert { name = request.name, count = count }
      end
    end, entity, 0
  end,
  ["subspace-fluid-extractor"] = function(entity)
    return function(entity, name)
      if name then
        return nil, nil, nil
      end
      local recipe = entity.get_recipe() -- There are not fluid requests, so fluid extraction is handled with fake "extraction recipes".
      if not recipe then
        return nil, nil, nil
      end
      local fluid = entity.fluidbox[1] or { name = recipe.products[1].name, amount = 0 }
      if fluid.name ~= recipe.products[1].name then
        return nil, nil, nil
      end
      local missing = math.max(0, math.floor(entity.fluid_capacity - fluid.amount))
      if missing < 1 then
        return nil, nil, nil
      end
      return fluid.name, missing, function(amount)
        fluid.amount = fluid.amount + amount
        entity.fluidbox[1] = fluid
        return amount
      end
    end, entity, nil
  end,
  ["subspace-electricity-extractor"] = function(entity)
    return function(entity, name)
      if name then
        return nil, nil, nil
      end
      local missing = math.floor((entity.electric_buffer_size - entity.energy) / ELECTRICITY_UNIT)
      if name or missing <= 0 then
        return nil, nil, nil
      end
      return "electricity", missing, function(count)
        entity.energy = entity.energy + count * ELECTRICITY_UNIT
        return count
      end
    end, entity, nil
  end
}

function process_extractor(entity)
  if not entity.valid or entity.to_be_deconstructed(entity.force)
      or not subspace_extractors[entity.name] then
    return
  end

  local force, cx, cy = get_endpoint(entity)

  for item, requested, give in requests_pairs[entity.name](entity) do
    if settings.global["subspace_storage-infinity-mode"].value then
      give(requested)
    else
      local given = give(math.min(requested, global.inbox:get(force, cx, cy, item) or 0))
      if given > 0 then
        global.inbox:update(force, cx, cy, item, function(c) return (c or 0) - given end)
      end

      requested = requested - given
      if requested > 0 then
        global.requests:update(force, cx, cy, item, function(c) return (c or 0) + requested end)
      end
    end
  end
end

function process_combinator(entity)
  if not entity.valid or entity.to_be_deconstructed(entity.force)
      or not subspace_combinators[entity.name] then
    return
  end

  local force, cx, cy = get_endpoint(entity)

  local behaviour = entity.get_or_create_control_behavior()
  behaviour.enabled = not settings.global["subspace_storage-infinity-mode"].value

  local parameters = {
    {
      index = 1,
      signal = { name = "signal-localid", type = "virtual" },
      -- Clamp to 32-bit to avoid error raised by Factorio
      count = math.max(math.min(clusterio_api.get_instance_id() or 0, 0x7fffffff), -0x0000),
    }
  }

  if settings.global["subspace_storage-infinity-mode"].value then
    behaviour.parameters = parameters
    return
  end

  for f, x, y, item, count in global.inventory:entries() do
    if f == force and x == cx and y == cy then
      local type
      if game.item_prototypes[item] then
        type = "item"
      elseif game.fluid_prototypes[item] then
        type = "fluid"
      elseif game.virtual_signal_prototypes[item] then
        type = "virtual"
      end
      if type then
        table.insert(parameters, {
          index = #parameters + 1,
          signal = { name = item, type = type },
          -- Combinator signals are limited to a max value of 2^31-1
          count = math.min(count, 0x7fffffff),
        })
      end
    end
  end

  behaviour.parameters = parameters
end
