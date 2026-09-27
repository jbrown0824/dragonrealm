-- Minimal signal: connect handlers, fire them in order.

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local handlers = self.handlers
	table.insert(handlers, fn)
	return {
		Disconnect = function()
			local i = table.find(handlers, fn)
			if i then
				table.remove(handlers, i)
			end
		end,
	}
end

function Signal:Fire(...)
	for _, fn in ipairs(table.clone(self.handlers)) do
		task.spawn(fn, ...)
	end
end

return Signal
