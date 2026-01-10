---@class ShelterBufferIntegration
---Buffer masking integration for shelter.nvim
---Optimized for performance with batched extmarks and proper debouncing
local M = {}

local config = require("shelter.config")
local state = require("shelter.state")
local masking = require("shelter.masking")
local env_file = require("shelter.utils.env_file")

-- Sub-modules
local extmarks = require("shelter.integrations.buffer.extmarks")
local peek = require("shelter.integrations.buffer.peek")
local completion = require("shelter.integrations.buffer.completion")
local paste = require("shelter.integrations.buffer.paste")
local autocmds = require("shelter.integrations.buffer.autocmds")

-- Fast locals for hot path
local api = vim.api
local nvim_buf_is_valid = api.nvim_buf_is_valid
local nvim_buf_get_lines = api.nvim_buf_get_lines
local nvim_buf_get_name = api.nvim_buf_get_name
local nvim_get_current_buf = api.nvim_get_current_buf
local nvim_get_current_win = api.nvim_get_current_win
local table_concat = table.concat

-- Debouncing state for TextChanged events
local DEBOUNCE_MS = 50
local buffer_timers = {}

-- Content hash tracking to skip redundant re-masks
local buffer_content_hashes = {}

---Setup buffer options for sheltering
---@param bufnr number
---@param winid number
local function setup_buffer_options(bufnr, winid)
	-- Set conceal options for proper masking display
	api.nvim_win_set_option(winid, "conceallevel", 2)
	api.nvim_win_set_option(winid, "concealcursor", "nvic")

	-- Disable completion if configured
	completion.disable(bufnr)
end

---Debounced shelter for TextChanged events
---Coalesces rapid edits into a single re-mask operation
---@param bufnr number
local function debounced_shelter(bufnr)
	-- Cancel any pending timer for this buffer
	if buffer_timers[bufnr] then
		vim.fn.timer_stop(buffer_timers[bufnr])
		buffer_timers[bufnr] = nil
	end

	-- Schedule new update
	buffer_timers[bufnr] = vim.fn.timer_start(DEBOUNCE_MS, function()
		buffer_timers[bufnr] = nil
		if nvim_buf_is_valid(bufnr) and state.is_enabled("files") then
			M.shelter_buffer(bufnr, true)
		end
	end)
end

---Shelter a buffer (apply masks)
---@param bufnr? number Buffer number (default: current)
---@param sync? boolean If true, apply masks synchronously (for paste protection)
---@param force? boolean If true, skip content hash check
function M.shelter_buffer(bufnr, sync, force)
	bufnr = bufnr or nvim_get_current_buf()

	-- Check if feature is enabled
	if not state.is_enabled("files") then
		return
	end

	-- Check if buffer is valid
	if not nvim_buf_is_valid(bufnr) then
		return
	end

	-- Check if buffer filetype is an env filetype
	if not env_file.is_env_buffer(bufnr) then
		return
	end

	-- Get buffer name for source tracking
	local bufname = nvim_buf_get_name(bufnr)

	-- Get buffer content
	local lines = nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table_concat(lines, "\n")

	-- Skip if content hasn't changed (optimization for rapid events)
	if not force then
		local content_len = #content
		-- Simple hash: length + first 64 chars (matches engine.lua hash strategy for small files)
		local simple_hash
		if content_len < 512 then
			simple_hash = content_len .. ":" .. content:sub(1, 64)
		else
			simple_hash = content_len .. ":" .. content:sub(1, 32) .. content:sub(-32)
		end

		if buffer_content_hashes[bufnr] == simple_hash then
			return -- Content unchanged, skip re-masking
		end
		buffer_content_hashes[bufnr] = simple_hash
	end

	-- Clear existing marks
	extmarks.clear(bufnr)

	-- Generate masks (includes pre-computed line_offsets from Rust)
	local result = masking.generate_masks(content, bufname)

	-- line_offsets must be provided by Rust - no fallbacks
	local line_offsets = result.line_offsets
	assert(line_offsets and #line_offsets > 0, "shelter.nvim: line_offsets not provided by native parser")

	-- Apply masks (sync mode for paste protection, pass lines to avoid double read)
	extmarks.apply_masks(bufnr, result.masks, line_offsets, lines, sync)
end

---Shelter a preview buffer (for picker integrations)
---Unlike shelter_buffer, this doesn't check "files" feature state
---and accepts filetype directly instead of checking buffer filetype
---@param bufnr number Buffer number
---@param filename string Filename for source tracking
---@param filetype? string Optional filetype override (for preview buffers)
function M.shelter_preview_buffer(bufnr, filename, filetype)
	-- Check if buffer is valid
	if not nvim_buf_is_valid(bufnr) then
		return
	end

	-- Use provided filetype or detect from buffer
	local ft = filetype or vim.bo[bufnr].filetype
	if not env_file.is_env_filetype(ft) then
		return
	end

	-- Clear existing marks
	extmarks.clear(bufnr)

	-- Get buffer content
	local lines = nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table_concat(lines, "\n")

	-- Generate masks (includes pre-computed line_offsets from Rust)
	local result = masking.generate_masks(content, filename)

	-- line_offsets must be provided by Rust - silently fail for preview buffers
	local line_offsets = result.line_offsets
	if not line_offsets or #line_offsets == 0 then
		return
	end

	-- Apply masks (pass lines to avoid double read)
	extmarks.apply_masks(bufnr, result.masks, line_offsets, lines)
end

---Unshelter a buffer (remove masks)
---@param bufnr? number Buffer number (default: current)
function M.unshelter_buffer(bufnr)
	bufnr = bufnr or nvim_get_current_buf()

	-- Reset conceal options
	local winid = nvim_get_current_win()
	pcall(api.nvim_win_set_option, winid, "conceallevel", 0)
	pcall(api.nvim_win_set_option, winid, "concealcursor", "")

	extmarks.clear(bufnr)
	completion.restore(bufnr)

	-- Clear content hash so re-sheltering will apply masks
	buffer_content_hashes[bufnr] = nil
end

---Refresh a buffer (re-apply masks)
---@param bufnr? number Buffer number (default: current)
function M.refresh_buffer(bufnr)
	bufnr = bufnr or nvim_get_current_buf()
	M.unshelter_buffer(bufnr)
	M.shelter_buffer(bufnr)
end

---Toggle masking for a buffer
---@param bufnr? number Buffer number (default: current)
---@return boolean new_state
function M.toggle_buffer(bufnr)
	bufnr = bufnr or nvim_get_current_buf()
	local enabled = state.toggle("files")

	if enabled then
		M.shelter_buffer(bufnr)
	else
		M.unshelter_buffer(bufnr)
	end

	return enabled
end

-- ============================================================================
-- Peek Functions (Temporary line reveal)
-- ============================================================================

---Peek a line temporarily (reveal for 3 seconds)
---@param bufnr? number Buffer number (default: current)
---@param line_num? number Line number (default: current cursor line)
function M.peek_line(bufnr, line_num)
	bufnr = bufnr or nvim_get_current_buf()
	line_num = line_num or api.nvim_win_get_cursor(0)[1]

	peek.peek_line(bufnr, line_num, function()
		M.refresh_buffer(bufnr)
	end)
end

---Hide a peeked line
---@param bufnr? number Buffer number (default: current)
---@param line_num number Line number to hide
function M.hide_line(bufnr, line_num)
	bufnr = bufnr or nvim_get_current_buf()

	peek.hide_line(bufnr, line_num, function()
		M.refresh_buffer(bufnr)
	end)
end

---Toggle peek for current line
---@param bufnr? number Buffer number (default: current)
---@param line_num? number Line number (default: current cursor line)
function M.toggle_peek(bufnr, line_num)
	bufnr = bufnr or nvim_get_current_buf()
	line_num = line_num or api.nvim_win_get_cursor(0)[1]

	peek.toggle_peek(bufnr, line_num, function()
		M.refresh_buffer(bufnr)
	end)
end

-- ============================================================================
-- Setup and Cleanup
-- ============================================================================

---Setup buffer integration
function M.setup()
	-- Initialize feature state from config
	local cfg = config.get()
	local files_enabled = cfg.modules.files ~= false and cfg.modules.files ~= nil
	state.set_initial("files", files_enabled)

	-- Initialize pattern cache
	local engine = require("shelter.masking.engine")
	engine.init()

	-- Setup paste override for protection
	paste.setup(function(bufnr, masks, line_offsets, lines, sync)
		extmarks.apply_masks(bufnr, masks, line_offsets, lines, sync)
	end, function(content, source)
		return masking.generate_masks(content, source)
	end)

	-- Setup autocmds with callbacks
	autocmds.setup({
		on_filetype = function(ev)
			if state.is_enabled("files") then
				local winid = nvim_get_current_win()
				setup_buffer_options(ev.buf, winid)
				M.shelter_buffer(ev.buf, true) -- sync=true to prevent flash
			end
		end,

		on_buf_enter = function(ev)
			if not env_file.is_env_buffer(ev.buf) then
				return
			end
			if state.is_enabled("files") then
				local winid = nvim_get_current_win()
				setup_buffer_options(ev.buf, winid)
				M.shelter_buffer(ev.buf, true)
			end
		end,

		on_buf_leave = function(ev)
			if not env_file.is_env_buffer(ev.buf) then
				return
			end
			local files_config = config.get_files_config()
			if files_config.shelter_on_leave then
				state.reset_revealed_lines()
				state.enable_all_user_modules()
				if state.is_enabled("files") and nvim_buf_is_valid(ev.buf) then
					M.shelter_buffer(ev.buf, true)
				end
			end
		end,

		on_text_changed = function(ev)
			if not env_file.is_env_buffer(ev.buf) then
				return
			end
			if paste.is_paste_in_progress() then
				return
			end
			if not state.is_enabled("files") then
				return
			end
			-- Use debounced update to coalesce rapid edits
			debounced_shelter(ev.buf)
		end,

		on_text_changed_i = function(ev)
			if not env_file.is_env_buffer(ev.buf) then
				return
			end
			if paste.is_paste_in_progress() then
				return
			end
			if not state.is_enabled("files") then
				return
			end
			-- Use debounced update to coalesce rapid edits
			debounced_shelter(ev.buf)
		end,

		on_insert_leave = function(ev)
			if not env_file.is_env_buffer(ev.buf) then
				return
			end
			if not state.is_enabled("files") then
				return
			end
			-- Final update after leaving insert mode (immediate, not debounced)
			-- Cancel any pending debounced update
			if buffer_timers[ev.buf] then
				vim.fn.timer_stop(buffer_timers[ev.buf])
				buffer_timers[ev.buf] = nil
			end
			M.shelter_buffer(ev.buf, true)
		end,
	})
end

---Cleanup buffer integration
function M.cleanup()
	autocmds.cleanup()
	peek.cleanup()
	paste.cleanup()
end

return M
