---@class ShelterPatternCache
---Pre-compiled pattern matching for O(1) lookups after O(n) setup
local M = {}

---@class CompiledPattern
---@field lua_pattern string
---@field mode string
---@field specificity number

---@type table<string, CompiledPattern>
local _key_patterns = {}

---@type table<string, string>
local _source_patterns = {}

---@type string
local _default_mode = "full"

---@type boolean
local _compiled = false

---Convert glob pattern to Lua pattern (cached at module level)
---@param glob string
---@return string
local function glob_to_pattern(glob)
	local pattern = glob
	-- Escape special Lua pattern characters (except *)
	pattern = pattern:gsub("([%.%+%-%?%^%$%(%)%[%]%%])", "%%%1")
	-- Convert * to .*
	pattern = pattern:gsub("%*", ".*")
	return "^" .. pattern .. "$"
end

---Calculate pattern specificity (higher = more specific)
---@param pattern string
---@return number
local function calculate_specificity(pattern)
	-- Longer patterns are more specific
	-- Wildcards reduce specificity
	local wildcards = 0
	for _ in pattern:gmatch("%*") do
		wildcards = wildcards + 1
	end
	return #pattern - (wildcards * 10)
end

---Compile all patterns from config (call once at setup)
---@param config table The config table with patterns, sources, default_mode
function M.compile(config)
	_key_patterns = {}
	_source_patterns = {}
	_default_mode = config.default_mode or "full"

	-- Pre-compile key patterns
	for pattern, mode in pairs(config.patterns or {}) do
		_key_patterns[pattern] = {
			lua_pattern = glob_to_pattern(pattern),
			mode = mode,
			specificity = calculate_specificity(pattern),
		}
	end

	-- Pre-compile source patterns
	for pattern, mode in pairs(config.sources or {}) do
		_source_patterns[pattern] = glob_to_pattern(pattern)
		-- Store mode separately since we use pattern as key
		_source_patterns[pattern .. "_mode"] = mode
	end

	_compiled = true
end

---Match a key against pre-compiled patterns
---@param key string
---@return string|nil mode
function M.match_key(key)
	local best_match = nil
	local best_specificity = -math.huge -- Start with negative infinity so any match wins

	for _, compiled in pairs(_key_patterns) do
		if key:match(compiled.lua_pattern) then
			if compiled.specificity > best_specificity then
				best_specificity = compiled.specificity
				best_match = compiled.mode
			end
		end
	end

	return best_match
end

---Match a source filename against pre-compiled patterns
---@param source_name string The basename of the source file
---@return string|nil mode
function M.match_source(source_name)
	for pattern, lua_pattern in pairs(_source_patterns) do
		-- Skip the _mode entries
		if not pattern:match("_mode$") then
			if source_name:match(lua_pattern) then
				return _source_patterns[pattern .. "_mode"]
			end
		end
	end
	return nil
end

---Get the default masking mode
---@return string
function M.get_default_mode()
	return _default_mode
end

---Determine masking mode for a key (uses pre-compiled patterns)
---@param key string
---@param source string|nil
---@return string mode
function M.determine_mode(key, source)
	-- Check key patterns first (most specific wins)
	local key_mode = M.match_key(key)
	if key_mode then
		return key_mode
	end

	-- Check source patterns
	if source then
		local source_name = vim.fn.fnamemodify(source, ":t")
		local source_mode = M.match_source(source_name)
		if source_mode then
			return source_mode
		end
	end

	return _default_mode
end

---Check if patterns are compiled
---@return boolean
function M.is_compiled()
	return _compiled
end

---Clear compiled patterns (for config reload)
function M.clear()
	_key_patterns = {}
	_source_patterns = {}
	_compiled = false
end

return M
