---@class ShelterDebounce
---Proper debounce with timer cleanup to prevent memory leaks
local M = {}

-- Active timers keyed by identifier
local _timers = {}

-- vim.fn.timer_start/timer_stop cached
local timer_start = vim.fn.timer_start
local timer_stop = vim.fn.timer_stop

---Create a debounced function
---@param fn function The function to debounce
---@param delay number Delay in milliseconds
---@param key string Unique key for this debounce instance
---@return function debounced_fn
function M.create(fn, delay, key)
	return function(...)
		local args = { ... }

		-- Cancel existing timer
		if _timers[key] then
			timer_stop(_timers[key])
			_timers[key] = nil
		end

		-- Start new timer
		_timers[key] = timer_start(delay, function()
			_timers[key] = nil
			fn(unpack(args))
		end)
	end
end

---Cancel a debounced operation
---@param key string The key used when creating the debounce
function M.cancel(key)
	if _timers[key] then
		timer_stop(_timers[key])
		_timers[key] = nil
	end
end

---Cancel all pending debounced operations
function M.cancel_all()
	for key, timer_id in pairs(_timers) do
		timer_stop(timer_id)
		_timers[key] = nil
	end
end

---Get count of active timers (for debugging)
---@return number
function M.active_count()
	local count = 0
	for _ in pairs(_timers) do
		count = count + 1
	end
	return count
end

return M
