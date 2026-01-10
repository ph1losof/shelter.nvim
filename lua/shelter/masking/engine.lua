---@class ShelterMaskingEngine
---Core masking engine for shelter.nvim
local M = {}

local config = require("shelter.config")
local native = require("shelter.native")
local modes = require("shelter.modes")
local pattern_cache = require("shelter.utils.pattern_cache")

-- LRU Cache for parsed content
local LRU_SIZE = 200
local lru = require("shelter.cache.lru")
local parsed_cache = lru.new(LRU_SIZE)

-- Fast locals for hot path
local string_byte = string.byte
local string_format = string.format
local bit_band = bit and bit.band or function(a, b)
	return a % (b + 1)
end

---Optimized content hash using sampling for large files
---For small files (<512 bytes): use length + first 64 chars
---For large files: sample every 16th byte up to 512 samples
---@param content string
---@return string
local function hash_content(content)
	local len = #content

	-- Small file: fast path
	if len < 512 then
		return string_format("%d:%s", len, content:sub(1, 64))
	end

	-- Large file: sample every 16th byte
	local hash = len
	local samples = 0
	local max_samples = 512

	for i = 1, len, 16 do
		hash = bit_band(hash * 31 + string_byte(content, i), 0xFFFFFFFF)
		samples = samples + 1
		if samples >= max_samples then
			break
		end
	end

	return string_format("%d:%x", len, hash)
end

---Clear all caches
function M.clear_caches()
	parsed_cache:clear()
end

---@class ShelterParsedContent
---@field entries ShelterParsedEntry[]
---@field line_offsets number[]

---Parse buffer content with caching
---Returns both entries and pre-computed line offsets from Rust
---@param content string
---@return ShelterParsedContent
function M.parse_content(content)
	local cache_key = hash_content(content)
	local cached = parsed_cache:get(cache_key)
	if cached then
		return cached
	end

	-- native.parse now returns {entries, line_offsets}
	local result = native.parse(content)
	parsed_cache:put(cache_key, result)
	return result
end

---Determine masking mode for a key based on patterns (uses pattern cache)
---@param key string
---@param source_basename string|nil Pre-computed basename of source file
---@return string mode_name
function M.determine_mode(key, source_basename)
	-- Use pre-compiled pattern cache if available
	if pattern_cache.is_compiled() then
		return pattern_cache.determine_mode(key, source_basename)
	end

	-- Fallback: compile on demand (shouldn't happen after setup)
	local cfg = config.get()
	pattern_cache.compile(cfg)
	return pattern_cache.determine_mode(key, source_basename)
end

---@class ShelterMaskContext
---@field key string
---@field source string|nil
---@field line_number number
---@field quote_type number

---Mask a single value
---@param value string
---@param context ShelterMaskContext
---@param cfg? table Optional config (to avoid repeated lookups)
---@param mode_name? string Optional pre-determined mode name
---@return string
function M.mask_value(value, context, cfg, mode_name)
	cfg = cfg or config.get()
	mode_name = mode_name or M.determine_mode(context.key, context.source)

	-- Extend context with config for modes that need it
	context.config = cfg

	return modes.apply(mode_name, value, context)
end

---@class ShelterMaskedLine
---@field line_number number
---@field value_end_line number
---@field mask string
---@field value_start number
---@field value_end number
---@field value string
---@field is_comment boolean
---@field quote_type number 0=none, 1=single, 2=double

---@class ShelterMaskResult
---@field masks ShelterMaskedLine[]
---@field line_offsets number[] Pre-computed line offsets from Rust

---Generate masks for buffer content
---Returns masks and pre-computed line offsets for O(1) byte-to-column conversion
---@param content string
---@param source string|nil
---@return ShelterMaskResult
function M.generate_masks(content, source)
	local cfg = config.get()
	local skip_comments = cfg.skip_comments
	local parsed = M.parse_content(content)
	local masks = {}

	-- Cache source basename once (avoid vim.fn.fnamemodify per entry)
	local source_basename = source and vim.fn.fnamemodify(source, ":t") or nil

	-- Memoize key→mode mapping for this batch (same keys get same mode)
	local mode_memo = {}

	for _, entry in ipairs(parsed.entries) do
		-- Skip comments only if skip_comments is true
		-- When skip_comments is false, we mask values in comments too
		local should_skip = entry.is_comment and skip_comments

		if not should_skip then
			-- Check memoized mode first
			local mode_name = mode_memo[entry.key]
			if not mode_name then
				mode_name = pattern_cache.determine_mode(entry.key, source_basename)
				mode_memo[entry.key] = mode_name
			end

			local context = {
				key = entry.key,
				source = source,
				line_number = entry.line_number,
				quote_type = entry.quote_type,
				is_comment = entry.is_comment,
			}

			local mask = M.mask_value(entry.value, context, cfg, mode_name)

			masks[#masks + 1] = {
				line_number = entry.line_number,
				value_end_line = entry.value_end_line,
				mask = mask,
				value_start = entry.value_start,
				value_end = entry.value_end,
				value = entry.value,
				is_comment = entry.is_comment,
				quote_type = entry.quote_type,
			}
		end
	end

	return {
		masks = masks,
		line_offsets = parsed.line_offsets,
	}
end

---Initialize the pattern cache and modes from config (call at setup)
function M.init()
	local cfg = config.get()
	pattern_cache.compile(cfg)

	-- Setup modes with config
	modes.setup(cfg)
end

---Reload pattern cache and modes (call when config changes)
function M.reload_patterns()
	local cfg = config.get()
	pattern_cache.compile(cfg)

	-- Reload modes with updated config
	modes.reset()
	modes.setup(cfg)
end

return M
