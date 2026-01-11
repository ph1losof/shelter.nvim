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
local string_rep = string.rep
local bit_band = bit and bit.band or function(a, b)
	return a % (b + 1)
end

-- Pre-computed mask strings cache for common lengths
-- Avoids repeated string.rep() calls for the same mask char + length
local mask_cache = {}
local MASK_CACHE_SIZE = 128 -- Cache masks up to 128 chars

---Get or create cached mask string
---@param mask_char string Single character used for masking
---@param length number Desired mask length
---@return string
local function get_cached_mask(mask_char, length)
	if length <= 0 then
		return ""
	end
	if length > MASK_CACHE_SIZE then
		return string_rep(mask_char, length)
	end

	local char_cache = mask_cache[mask_char]
	if not char_cache then
		char_cache = {}
		mask_cache[mask_char] = char_cache
	end

	local cached = char_cache[length]
	if not cached then
		cached = string_rep(mask_char, length)
		char_cache[length] = cached
	end

	return cached
end

-- Export for use by other modules
M.get_cached_mask = get_cached_mask

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
	-- Note: mask_cache is intentionally not cleared - mask strings are reusable
	-- across content changes since they only depend on mask_char + length
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
	local mask_count = 0

	-- Cache source basename once (avoid vim.fn.fnamemodify per entry)
	local source_basename = source and vim.fn.fnamemodify(source, ":t") or nil

	-- Memoize key→mode name mapping for this batch
	local mode_name_memo = {}

	-- Cache mode INSTANCES to avoid modes.get() per entry
	local mode_instance_cache = {}

	-- Reusable context table to avoid allocation per entry
	local context = {
		key = nil,
		source = source,
		line_number = nil,
		quote_type = nil,
		is_comment = nil,
		config = cfg,
		value = nil,
	}

	for _, entry in ipairs(parsed.entries) do
		-- Skip comments only if skip_comments is true
		-- When skip_comments is false, we mask values in comments too
		local should_skip = entry.is_comment and skip_comments

		if not should_skip then
			-- Check memoized mode name first
			local mode_name = mode_name_memo[entry.key]
			if not mode_name then
				mode_name = pattern_cache.determine_mode(entry.key, source_basename)
				mode_name_memo[entry.key] = mode_name
			end

			-- Get cached mode instance (avoids modes.get lookup per entry)
			local mode = mode_instance_cache[mode_name]
			if not mode then
				mode = modes.get(mode_name)
				mode_instance_cache[mode_name] = mode
			end

			-- Update reusable context (no allocation)
			context.key = entry.key
			context.value = entry.value
			context.line_number = entry.line_number
			context.quote_type = entry.quote_type
			context.is_comment = entry.is_comment

			-- Call mode:apply directly (skip modes.apply overhead)
			local mask = mode:apply(context)

			-- Direct indexed assignment (faster than #masks + 1)
			mask_count = mask_count + 1
			masks[mask_count] = {
				line_number = entry.line_number,
				value_end_line = entry.value_end_line,
				mask = mask,
				value_start = entry.value_start,
				value_end = entry.value_end,
				quote_type = entry.quote_type,
				value = entry.value, -- Keep for tests/diagnostics (string ref, no copy)
			}
		end
	end

	return {
		masks = masks,
		line_offsets = parsed.line_offsets,
	}
end

---Generate masks for specific line range only (incremental update)
---Only processes entries in the affected range, merges with cached masks
---@param content string Full buffer content
---@param source string|nil
---@param line_range {min_line: number, max_line: number} 1-indexed line range
---@param cached_masks ShelterMaskedLine[] Previously cached masks
---@return ShelterMaskResult
function M.generate_masks_incremental(content, source, line_range, cached_masks)
	local cfg = config.get()
	local skip_comments = cfg.skip_comments
	local parsed = M.parse_content(content)

	-- Filter entries to only those in affected range
	local affected_entries = {}
	local affected_count = 0
	for _, entry in ipairs(parsed.entries) do
		if entry.line_number >= line_range.min_line and entry.line_number <= line_range.max_line then
			affected_count = affected_count + 1
			affected_entries[affected_count] = entry
		end
	end

	-- Generate masks ONLY for affected entries
	local source_basename = source and vim.fn.fnamemodify(source, ":t") or nil
	local mode_name_memo = {}
	local mode_instance_cache = {}
	local new_masks = {}
	local new_mask_count = 0

	-- Reusable context table
	local context = {
		key = nil,
		source = source,
		line_number = nil,
		quote_type = nil,
		is_comment = nil,
		config = cfg,
		value = nil,
	}

	for _, entry in ipairs(affected_entries) do
		local should_skip = entry.is_comment and skip_comments
		if not should_skip then
			local mode_name = mode_name_memo[entry.key]
			if not mode_name then
				mode_name = pattern_cache.determine_mode(entry.key, source_basename)
				mode_name_memo[entry.key] = mode_name
			end

			local mode = mode_instance_cache[mode_name]
			if not mode then
				mode = modes.get(mode_name)
				mode_instance_cache[mode_name] = mode
			end

			context.key = entry.key
			context.value = entry.value
			context.line_number = entry.line_number
			context.quote_type = entry.quote_type
			context.is_comment = entry.is_comment

			local mask = mode:apply(context)

			new_mask_count = new_mask_count + 1
			new_masks[new_mask_count] = {
				line_number = entry.line_number,
				value_end_line = entry.value_end_line,
				mask = mask,
				value_start = entry.value_start,
				value_end = entry.value_end,
				quote_type = entry.quote_type,
				value = entry.value, -- Keep for tests/diagnostics (string ref, no copy)
			}
		end
	end

	-- Merge with cached masks (keep masks outside range)
	local merged_masks = {}
	local merged_count = 0
	for _, cached_mask in ipairs(cached_masks) do
		if cached_mask.line_number < line_range.min_line or cached_mask.line_number > line_range.max_line then
			merged_count = merged_count + 1
			merged_masks[merged_count] = cached_mask
		end
	end
	for _, new_mask in ipairs(new_masks) do
		merged_count = merged_count + 1
		merged_masks[merged_count] = new_mask
	end

	-- Sort by line number for consistent ordering
	table.sort(merged_masks, function(a, b)
		return a.line_number < b.line_number
	end)

	return {
		masks = merged_masks,
		masks_to_apply = new_masks, -- Only these need extmark update
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
