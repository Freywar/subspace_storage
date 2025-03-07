
local ItemStorage = {}
ItemStorage.__index = ItemStorage

script.register_metatable("subspace_storage__item_storage", ItemStorage)

function ItemStorage:new()
	local o = { data = {} }
	setmetatable(o, ItemStorage)
	return o
end

function ItemStorage:set(force, cx, cy, item, entry)
	self.data[force] = self.data[force] or {}
	self.data[force][cx] = self.data[force][cx] or {}
	self.data[force][cx][cy] = self.data[force][cx][cy] or {}
	self.data[force][cx][cy][item] = entry
end

function ItemStorage:get(force, cx, cy, item)
	return self.data[force] and self.data[force][cx] and self.data[force][cx][cy] and self.data[force][cx][cy][item]
end

function ItemStorage:update(force, cx, cy, item, f)
	self:set(force, cx, cy, item, f(self:get(force, cx, cy, item)))
end

function ItemStorage:delete(force, cx, cy, item)
	if self.data[force] and self.data[force][cx] and self.data[force][cx][cy] then
		self.data[force][cx][cy][item] = nil
	end
end

function ItemStorage:clear()
	self.data = {}
end

function ItemStorage:next(i)
	i = i + 1
	if i > #self then
		return nil, nil, nil, nil, nil, nil
	end
	return i, self[i].force, self[i].cx, self[i].cy, self[i].item, self[i].entry
end

function ItemStorage:entries()
	local entries = {}
	for force, cxs in pairs(self.data) do
		for cx, cys in pairs(cxs) do
			for cy, items in pairs(cys) do
				for item, entry in pairs(items) do
					table.insert(entries, { force = force, cx = cx, cy = cy, item = item, entry = entry })
				end
			end
		end
	end

	return self.next, entries, 0
end

return ItemStorage
