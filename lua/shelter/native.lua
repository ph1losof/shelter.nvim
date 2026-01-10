---@class ShelterNative
---LuaJIT FFI bindings for shelter-core native library
local M = {}

local ffi = require("ffi")

-- FFI type definitions matching Rust types exactly
-- Use pcall to handle "attempt to redefine" errors on module reload
pcall(
	ffi.cdef,
	[[
typedef struct {
    char* key;
    size_t key_len;
    char* value;
    size_t value_len;
    size_t key_start;
    size_t key_end;
    size_t value_start;
    size_t value_end;
    size_t line_number;
    size_t value_end_line;
    uint8_t quote_type;
    uint8_t is_exported;
    uint8_t is_comment;
} ShelterEntry;

typedef struct {
    ShelterEntry* entries;
    size_t count;
    size_t* line_offsets;
    size_t line_count;
    char* error;
} ShelterResult;

typedef struct {
    uint8_t include_comments;
    uint8_t track_positions;
} ShelterParseOptions;

// Parsing functions
ShelterResult* shelter_parse(const char* input, size_t input_len, ShelterParseOptions options);
void shelter_free_result(ShelterResult* result);

// Utility functions
const char* shelter_version(void);
]]
)

-- Library handle
local lib = nil

-- Find and load the native library
local function find_library()
	-- Get the plugin directory
	local source = debug.getinfo(1, "S").source:sub(2)
	local plugin_dir = vim.fn.fnamemodify(source, ":h:h:h")

	-- Platform-specific library names
	local lib_names = {
		Darwin = "libshelter_core.dylib",
		Linux = "libshelter_core.so",
		Windows = "shelter_core.dll",
	}

	local uname = vim.uv.os_uname()
	local lib_name = lib_names[uname.sysname] or lib_names.Linux

	-- Search paths
	local search_paths = {
		plugin_dir .. "/lib/" .. lib_name,
		plugin_dir .. "/target/release/" .. lib_name,
		vim.fn.stdpath("data") .. "/shelter/" .. lib_name,
	}

	for _, path in ipairs(search_paths) do
		if vim.fn.filereadable(path) == 1 then
			local ok, result = pcall(ffi.load, path)
			if ok then
				return result, path
			end
		end
	end

	return nil, nil
end

-- Initialize the library
local function ensure_lib()
	if lib then
		return lib
	end

	local loaded, path = find_library()
	if not loaded then
		error([[
shelter.nvim: Native library not found!

Run :ShelterBuild to download pre-built binary
or build from source (requires Rust toolchain).

See: https://github.com/philosofonusus/shelter.nvim#installation
]])
	end

	lib = loaded
	return lib
end

---Check if the native library is available
---@return boolean
function M.is_available()
	local ok, _ = pcall(ensure_lib)
	return ok
end

---Get the native library version
---@return string
function M.version()
	local l = ensure_lib()
	return ffi.string(l.shelter_version())
end

---@class ShelterParsedEntry
---@field key string
---@field value string
---@field key_start number
---@field key_end number
---@field value_start number
---@field value_end number
---@field line_number number
---@field value_end_line number
---@field quote_type number
---@field is_exported boolean
---@field is_comment boolean

---@class ShelterParseResult
---@field entries ShelterParsedEntry[]
---@field line_offsets number[] Byte offset where each line starts (1-indexed, line_offsets[1] = offset of line 1)

---Parse EDF content
---@param content string The content to parse
---@param opts? {include_comments?: boolean, track_positions?: boolean}
---@return ShelterParseResult
function M.parse(content, opts)
	local l = ensure_lib()
	opts = opts or {}

	local parse_opts = ffi.new("ShelterParseOptions", {
		include_comments = opts.include_comments ~= false and 1 or 0,
		track_positions = opts.track_positions ~= false and 1 or 0,
	})

	local result = l.shelter_parse(content, #content, parse_opts)

	-- Check for errors
	if result.error ~= nil then
		local err_msg = ffi.string(result.error)
		l.shelter_free_result(result)
		error("Parse error: " .. err_msg)
	end

	-- Convert entries to Lua tables
	local entries = {}
	local entry_count = tonumber(result.count)
	for i = 0, entry_count - 1 do
		local entry = result.entries[i]
		entries[i + 1] = {
			key = ffi.string(entry.key, entry.key_len),
			value = ffi.string(entry.value, entry.value_len),
			key_start = tonumber(entry.key_start),
			key_end = tonumber(entry.key_end),
			value_start = tonumber(entry.value_start),
			value_end = tonumber(entry.value_end),
			line_number = tonumber(entry.line_number),
			value_end_line = tonumber(entry.value_end_line),
			quote_type = tonumber(entry.quote_type),
			is_exported = entry.is_exported ~= 0,
			is_comment = entry.is_comment ~= 0,
		}
	end

	-- Extract line offsets (pre-computed in Rust)
	local line_offsets = {}
	local line_count = tonumber(result.line_count) or 0
	-- FFI null pointer check: use ffi.cast to check for NULL
	if line_count > 0 and result.line_offsets ~= ffi.cast("size_t*", 0) then
		for i = 0, line_count - 1 do
			line_offsets[i + 1] = tonumber(result.line_offsets[i])
		end
	end

	l.shelter_free_result(result)

	return {
		entries = entries,
		line_offsets = line_offsets,
	}
end

return M
