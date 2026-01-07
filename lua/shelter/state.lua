---@class ShelterState
---State management for shelter.nvim
---Optimized: removed vim.validate from hot paths for performance
local M = {}

local uv = vim.uv or vim.loop

-- Memory management constants
local MEMORY_CHECK_INTERVAL = 600000 -- 10 minutes
local MEMORY_THRESHOLD = 100 * 1024 * 1024 -- 100MB

-- Fast locals
local collectgarbage = collectgarbage
local pairs = pairs
local pcall = pcall

---@class ShelterFeatureState
---@field enabled table<string, boolean>
---@field initial table<string, boolean>

---@class ShelterBufferState
---@field revealed_lines table<number, boolean>

---@class ShelterMemoryState
---@field last_gc number
---@field last_check number

---@class ShelterInternalState
---@field features ShelterFeatureState
---@field buffer ShelterBufferState
---@field memory ShelterMemoryState

---@class ShelterOriginalsState
---@field snacks_preview function|nil
---@field file_previewer function|nil
---@field grep_previewer function|nil
---@field fzf_preview_buf_post function|nil

---@type ShelterInternalState
local state = {
	features = {
		enabled = {},
		initial = {},
	},
	buffer = {
		revealed_lines = {},
	},
	memory = {
		last_gc = uv.now(),
		last_check = 0,
	},
	---@type ShelterOriginalsState
	originals = {
		snacks_preview = nil,
		file_previewer = nil,
		grep_previewer = nil,
		fzf_preview_buf_post = nil,
	},
}

-- Weak table caches
local _state_cache = setmetatable({}, { __mode = "k" })

---Get memory usage statistics
---@return table
local function get_memory_usage()
	return {
		lua_used = collectgarbage("count") * 1024,
	}
end

---Check memory usage and trigger GC if needed
local function check_memory_usage()
	local current_time = uv.now()
	if current_time - state.memory.last_check < MEMORY_CHECK_INTERVAL then
		return
	end

	state.memory.last_check = current_time
	local stats = get_memory_usage()

	if stats.lua_used > MEMORY_THRESHOLD then
		M.force_garbage_collection()
	end
end

---Force garbage collection
function M.force_garbage_collection()
	_state_cache = setmetatable({}, { __mode = "k" })
	state.buffer.revealed_lines = {}
	collectgarbage("collect")
	state.memory.last_gc = uv.now()
end

---Get full state (for debugging)
---@return ShelterInternalState
function M.get_state()
	check_memory_usage()
	return state
end

---Check if a feature is enabled (HOT PATH - no validation)
---@param feature string
---@return boolean
function M.is_enabled(feature)
	local cache_key = "feature_enabled_" .. feature
	local cached = _state_cache[cache_key]
	if cached ~= nil then
		return cached
	end

	local enabled = state.features.enabled[feature] or false
	_state_cache[cache_key] = enabled
	return enabled
end

---Set feature enabled state
---@param feature string
---@param enabled boolean
function M.set_enabled(feature, enabled)
	state.features.enabled[feature] = enabled
	_state_cache["feature_enabled_" .. feature] = enabled

	if feature == "files" then
		vim.schedule(function()
			local buffer_ok, buffer = pcall(require, "shelter.integrations.buffer")
			if not buffer_ok then
				return
			end

			if enabled then
				-- If enabling files, clear revealed lines and refresh
				M.reset_revealed_lines()
				local ok, engine = pcall(require, "shelter.masking.engine")
				if ok and engine.clear_caches then
					engine.clear_caches()
				end
				buffer.shelter_buffer()
			else
				-- If disabling files, clear all extmarks
				buffer.unshelter_buffer()
			end
		end)
	end
end

---Toggle a feature
---@param feature string
---@return boolean new_state
function M.toggle(feature)
	local current = M.is_enabled(feature)
	M.set_enabled(feature, not current)
	return not current
end

---Set initial feature state (from config)
---@param feature string
---@param enabled boolean
function M.set_initial(feature, enabled)
	state.features.initial[feature] = enabled
	state.features.enabled[feature] = enabled
	_state_cache["feature_enabled_" .. feature] = enabled
end

---Restore initial settings
function M.restore_initial()
	for feature, enabled in pairs(state.features.initial) do
		state.features.enabled[feature] = enabled
		_state_cache["feature_enabled_" .. feature] = enabled
	end
end

---Check if a line is revealed (for peek) (HOT PATH - no validation)
---@param line_num number
---@return boolean
function M.is_line_revealed(line_num)
	return state.buffer.revealed_lines[line_num] or false
end

---Set line revealed state
---@param line_num number
---@param revealed boolean
function M.set_revealed_line(line_num, revealed)
	state.buffer.revealed_lines[line_num] = revealed
end

---Reveal a specific line (alias for set_revealed_line(line_num, true))
---@param line_num number
function M.reveal_line(line_num)
	state.buffer.revealed_lines[line_num] = true
end

---Hide a previously revealed line (alias for set_revealed_line(line_num, nil))
---@param line_num number
function M.hide_line(line_num)
	state.buffer.revealed_lines[line_num] = nil
end

---Reset all revealed lines
function M.reset_revealed_lines()
	state.buffer.revealed_lines = {}
end

---Get list of currently revealed line numbers
---@return number[]
function M.get_revealed_lines()
	local lines = {}
	for line_num, revealed in pairs(state.buffer.revealed_lines) do
		if revealed then
			lines[#lines + 1] = line_num
		end
	end
	table.sort(lines)
	return lines
end

---Get memory statistics
---@return table
function M.get_memory_stats()
	check_memory_usage()
	return get_memory_usage()
end

---Get an original function stored for integration cleanup
---@param key string Key name (snacks_preview, file_previewer, grep_previewer, fzf_preview_buf_post)
---@return function|nil
function M.get_original(key)
	return state.originals[key]
end

---Store an original function for later restoration
---@param key string Key name
---@param fn function|nil Function to store
function M.set_original(key, fn)
	state.originals[key] = fn
end

---Clear an original function (for cleanup)
---@param key string Key name
function M.clear_original(key)
	state.originals[key] = nil
end

---Get list of modules that user initially enabled
---@return string[]
function M.get_user_enabled_modules()
	local modules = {}
	for feature, enabled in pairs(state.features.initial) do
		if enabled then
			modules[#modules + 1] = feature
		end
	end
	return modules
end

---Toggle all user-enabled modules
---Toggles based on current state of "files" feature (primary module)
---@return boolean new_state The new enabled state for all modules
function M.toggle_all_user_modules()
	local target_state = not M.is_enabled("files")
	local modules = M.get_user_enabled_modules()

	for _, module in ipairs(modules) do
		M.set_enabled(module, target_state)
	end

	return target_state
end

---Enable all user-enabled modules (restore to initial state)
function M.enable_all_user_modules()
	for feature, was_enabled in pairs(state.features.initial) do
		if was_enabled then
			M.set_enabled(feature, true)
		end
	end
end

---Disable all modules
function M.disable_all_user_modules()
	for feature, _ in pairs(state.features.enabled) do
		M.set_enabled(feature, false)
	end
end

return M
