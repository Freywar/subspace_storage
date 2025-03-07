local RoundQueue = {}
RoundQueue.__index = RoundQueue

script.register_metatable("subspace_storage__round_queue", RoundQueue)

function RoundQueue:new()
	local o = { data = {}, pos = 0 }
	setmetatable(o, RoundQueue)
	return o
end

function RoundQueue:insert(item)
	table.insert(self.data, item)
end

function RoundQueue:remove(item)
	for i, v in ipairs(self.data) do
		if v == item then
			table.remove(self.data, i)
			return
		end
	end
end

function RoundQueue:next(i)
	i = i + 1
	if i > #self.data or self.pos > 0 and i > self.pos then
		return nil, nil
	end
	return i, self.data[i]
end

function RoundQueue:ipairs(count)
	local i = self.pos
	self.pos = self.pos + (count or #self.data)
	if self.pos >= #self then
		self.pos = 0 -- TODO Should wrap around instead.
	end
	return self.next, self, i
end

function RoundQueue:reset()
	self.pos = 0
end

function RoundQueue:clear()
	self.data = {}
	self.pos = 0
end

return RoundQueue
