---@class ShelterBufferIntegration
---Buffer masking integration for shelter.nvim
---Optimized for performance with batched extmarks and proper debouncing
local M = {}

local config = require("shelter.config")
local state = require("shelter.state")
local masking = require("shelter.masking")

-- Fast locals for hot path (5-15% speedup)
local api = vim.api
local fn = vim.fn
local nvim_buf_is_valid = api.nvim_buf_is_valid
local nvim_buf_get_lines = api.nvim_buf_get_lines
local nvim_buf_get_name = api.nvim_buf_get_name
local nvim_buf_set_extmark = api.nvim_buf_set_extmark
local nvim_buf_clear_namespace = api.nvim_buf_clear_namespace
local nvim_create_namespace = api.nvim_create_namespace
local nvim_get_current_buf = api.nvim_get_current_buf
local nvim_get_current_win = api.nvim_get_current_win
local nvim_create_autocmd = api.nvim_create_autocmd
local nvim_create_augroup = api.nvim_create_augroup
local table_concat = table.concat
local string_rep = string.rep
local math_max = math.max
local math_min = math.min

-- Namespace for extmarks
local ns_id = nil

-- Peek timer and constants
local PEEK_DURATION = 3000 -- 3 seconds
local peek_timer = nil

-- Original paste function (for paste protection)
local original_paste = nil

-- Flag to prevent TextChanged from interfering during paste
local paste_in_progress = false

-- Forward declarations for helper functions
local restore_completion
local setup_paste_override
local restore_paste_override

---Get or create the namespace
---@return number
local function get_namespace()
	if not ns_id then
		ns_id = nvim_create_namespace("shelter_mask")
	end
	return ns_id
end

---Convert glob pattern to Lua pattern (cached version exists in pattern_cache)
---@param glob string
---@return string
local function glob_to_pattern(glob)
	local pattern = glob
	pattern = pattern:gsub("([%.%+%-%?%^%$%(%)%[%]%%])", "%%%1")
	pattern = pattern:gsub("%*", ".*")
	return "^" .. pattern .. "$"
end

---Check if a file matches env file patterns
---@param filename string
---@return boolean
local function is_env_file(filename)
	local cfg = config.get()
	local basename = fn.fnamemodify(filename, ":t")

	for _, pattern in ipairs(cfg.env_file_patterns or {}) do
		local lua_pattern = glob_to_pattern(pattern)
		if basename:match(lua_pattern) then
			return true
		end
	end

	return false
end

---Clear all extmarks in a buffer
---@param bufnr number
local function clear_extmarks(bufnr)
	local ns = get_namespace()
	nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

---Apply masks to a buffer using batched extmark application
---@param bufnr number
---@param masks ShelterMaskedLine[]
---@param line_offsets number[] Pre-computed line offsets from Rust
---@param sync? boolean If true, apply synchronously (for paste protection)
local function apply_masks(bufnr, masks, line_offsets, sync)
	local ns = get_namespace()
	local cfg = config.get()
	local hl_group = cfg.highlight_group or "Comment"
	local mask_char = cfg.mask_char or "*"

	-- Get all lines for calculating column positions
	local lines = nvim_buf_get_lines(bufnr, 0, -1, false)

	-- line_offsets already pre-computed by Rust - O(1) lookups

	-- Collect extmarks for batched application
	local extmarks = {}

	for _, mask_info in ipairs(masks) do
		local start_line_idx = mask_info.line_number - 1
		local end_line_idx = mask_info.value_end_line - 1

		-- Skip if any line in range is revealed
		local any_revealed = false
		for ln = mask_info.line_number, mask_info.value_end_line do
			if state.is_line_revealed(ln) then
				any_revealed = true
				break
			end
		end
		if any_revealed then
			goto continue
		end

		-- Ensure lines exist
		if start_line_idx < 0 or start_line_idx >= #lines then
			goto continue
		end

		local start_line = lines[start_line_idx + 1]

		-- Calculate column from byte offset using pre-built offsets
		local line_start_offset = line_offsets[mask_info.line_number] or 0
		local value_col = mask_info.value_start - line_start_offset

		-- Check if value is quoted (quote_type: 0=none, 1=single, 2=double)
		-- For quoted values, korni's value_start includes the opening quote
		-- We want to PRESERVE quotes by not masking them
		local is_quoted = mask_info.quote_type and mask_info.quote_type > 0

		-- Check if this is a multi-line value
		local is_multiline = end_line_idx > start_line_idx

		if is_multiline then
			-- Multi-line value handling
			for i = 0, end_line_idx - start_line_idx do
				local line_idx = start_line_idx + i
				if line_idx >= #lines then
					break
				end

				local current_line = lines[line_idx + 1] or ""
				local col_start, col_end

				if i == 0 then
					-- First line: start after opening quote for quoted values
					col_start = value_col
					if is_quoted then
						col_start = col_start + 1 -- Skip opening quote
					end
					col_end = #current_line
				elseif i == end_line_idx - start_line_idx then
					-- LAST line: mask only up to value_end, excluding closing quote
					local last_line_offset = line_offsets[mask_info.value_end_line] or 0
					col_start = 0
					col_end = math_max(0, mask_info.value_end - last_line_offset)
					if is_quoted then
						col_end = col_end - 1 -- Exclude closing quote
					end
				else
					-- MIDDLE lines: mask entire line content
					col_start = 0
					col_end = #current_line
				end

				-- Ensure valid bounds
				col_start = math_max(0, col_start)
				col_end = math_max(col_start, col_end)

				-- Generate mask for this line segment
				local line_content_len = col_end - col_start
				local line_mask = string_rep(mask_char, math_max(0, line_content_len))

				extmarks[#extmarks + 1] = {
					line_idx,
					col_start,
					{
						end_col = col_end,
						virt_text = { { line_mask, hl_group } },
						virt_text_pos = "overlay",
						hl_mode = "combine",
						priority = 9999,
						strict = false,
					},
				}
			end
		else
			-- Single-line value handling
			local value_start_col = value_col

			-- For quoted values, skip the opening quote to preserve it
			if is_quoted then
				value_start_col = value_start_col + 1
			end

			-- Calculate end column using value_end byte offset directly
			-- This is more reliable than using value string length
			local value_end_col = mask_info.value_end - line_start_offset

			-- For quoted values, exclude the closing quote to preserve it
			if is_quoted then
				value_end_col = value_end_col - 1
			end

			-- Ensure valid bounds
			value_start_col = math_max(0, value_start_col)
			value_end_col = math_min(value_end_col, #start_line)
			value_end_col = math_max(value_start_col, value_end_col)

			extmarks[#extmarks + 1] = {
				start_line_idx,
				value_start_col,
				{
					end_col = value_end_col,
					virt_text = { { mask_info.mask, hl_group } },
					virt_text_pos = "overlay",
					hl_mode = "combine",
					priority = 9999,
					strict = false,
				},
			}
		end

		::continue::
	end

	-- Function to actually apply the extmarks
	local function do_apply()
		if not nvim_buf_is_valid(bufnr) then
			return
		end

		-- Clear extmarks to handle race conditions
		-- when shelter_buffer is called multiple times rapidly
		nvim_buf_clear_namespace(bufnr, ns, 0, -1)

		for _, mark in ipairs(extmarks) do
			pcall(nvim_buf_set_extmark, bufnr, ns, mark[1], mark[2], mark[3])
		end
	end

	-- Apply synchronously for paste protection, scheduled otherwise
	if sync then
		do_apply()
	else
		vim.schedule(do_apply)
	end
end

---Shelter a buffer (apply masks)
---@param bufnr? number Buffer number (default: current)
---@param sync? boolean If true, apply masks synchronously (for paste protection)
function M.shelter_buffer(bufnr, sync)
	bufnr = bufnr or nvim_get_current_buf()

	-- Check if feature is enabled
	if not state.is_enabled("files") then
		return
	end

	-- Check if buffer is valid
	if not nvim_buf_is_valid(bufnr) then
		return
	end

	-- Get buffer name
	local bufname = nvim_buf_get_name(bufnr)
	if bufname == "" or not is_env_file(bufname) then
		return
	end

	-- Clear existing marks
	clear_extmarks(bufnr)

	-- Get buffer content
	local lines = nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table_concat(lines, "\n")

	-- Generate masks (includes pre-computed line_offsets from Rust)
	local result = masking.generate_masks(content, bufname)

	-- line_offsets must be provided by Rust - no fallbacks
	local line_offsets = result.line_offsets
	assert(line_offsets and #line_offsets > 0, "shelter.nvim: line_offsets not provided by native parser")

	-- Apply masks (sync mode for paste protection)
	apply_masks(bufnr, result.masks, line_offsets, sync)
end

---Shelter a preview buffer (for picker integrations)
---Unlike shelter_buffer, this doesn't check "files" feature state
---and accepts filename directly instead of using buffer name
---@param bufnr number Buffer number
---@param filename string Filename for env file detection
function M.shelter_preview_buffer(bufnr, filename)
	-- Check if buffer is valid
	if not nvim_buf_is_valid(bufnr) then
		return
	end

	-- Use filename directly for env file check (preview buffers may not have buffer names set)
	if not filename or not is_env_file(filename) then
		return
	end

	-- Clear existing marks
	clear_extmarks(bufnr)

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

	-- Apply masks
	apply_masks(bufnr, result.masks, line_offsets)
end

---Unshelter a buffer (remove masks)
---@param bufnr? number Buffer number (default: current)
function M.unshelter_buffer(bufnr)
	bufnr = bufnr or nvim_get_current_buf()

	-- Reset conceal options
	local winid = nvim_get_current_win()
	pcall(api.nvim_win_set_option, winid, "conceallevel", 0)
	pcall(api.nvim_win_set_option, winid, "concealcursor", "")

	clear_extmarks(bufnr)
	restore_completion(bufnr)
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

---Peek a line temporarily (reveal for PEEK_DURATION milliseconds)
---@param bufnr? number Buffer number (default: current)
---@param line_num? number Line number (default: current cursor line)
function M.peek_line(bufnr, line_num)
	bufnr = bufnr or nvim_get_current_buf()
	line_num = line_num or api.nvim_win_get_cursor(0)[1]

	if not nvim_buf_is_valid(bufnr) then
		return
	end

	-- Cancel existing timer
	if peek_timer then
		peek_timer:stop()
		peek_timer:close()
		peek_timer = nil
	end

	-- Reveal the line
	state.reveal_line(line_num)
	M.refresh_buffer(bufnr)

	-- Set timer to hide after duration
	local uv = vim.uv or vim.loop
	peek_timer = uv.new_timer()
	peek_timer:start(PEEK_DURATION, 0, vim.schedule_wrap(function()
		M.hide_line(bufnr, line_num)
		if peek_timer then
			peek_timer:stop()
			peek_timer:close()
			peek_timer = nil
		end
	end))
end

---Hide a peeked line
---@param bufnr? number Buffer number (default: current)
---@param line_num number Line number to hide
function M.hide_line(bufnr, line_num)
	bufnr = bufnr or nvim_get_current_buf()
	if not nvim_buf_is_valid(bufnr) then
		return
	end
	state.hide_line(line_num)
	M.refresh_buffer(bufnr)
end

---Toggle peek for current line
---@param bufnr? number Buffer number (default: current)
---@param line_num? number Line number (default: current cursor line)
function M.toggle_peek(bufnr, line_num)
	bufnr = bufnr or nvim_get_current_buf()
	line_num = line_num or api.nvim_win_get_cursor(0)[1]

	if state.is_line_revealed(line_num) then
		M.hide_line(bufnr, line_num)
	else
		M.peek_line(bufnr, line_num)
	end
end

-- Autocommand group
local augroup = nil

---Get file patterns for autocmds from config
---@return string[]
local function get_watch_patterns()
	local cfg = config.get()
	local patterns = {}

	for _, pattern in ipairs(cfg.env_file_patterns or {}) do
		-- Add pattern as-is and with **/ prefix for nested files
		patterns[#patterns + 1] = pattern
		patterns[#patterns + 1] = "**/" .. pattern
	end

	return patterns
end

---Setup buffer options for sheltering
---@param bufnr number
---@param winid number
local function setup_buffer_options(bufnr, winid)
	-- Set conceal options for proper masking display
	api.nvim_win_set_option(winid, "conceallevel", 2)
	api.nvim_win_set_option(winid, "concealcursor", "nvic")

	-- Disable completion if configured
	local files_config = config.get_files_config()
	if files_config.disable_cmp then
		vim.b[bufnr].completion = false

		-- Disable nvim-cmp if available
		local has_cmp, cmp = pcall(require, "cmp")
		if has_cmp then
			cmp.setup.buffer({ enabled = false })
		end

		-- Disable blink-cmp if available (uses buffer variable)
		vim.b[bufnr].blink_cmp_enabled = false
	end
end

---Re-enable completion after unsheltering
---@param bufnr number
restore_completion = function(bufnr)
	local files_config = config.get_files_config()
	if files_config.disable_cmp then
		vim.b[bufnr].completion = true

		-- Re-enable nvim-cmp if available
		local has_cmp, cmp = pcall(require, "cmp")
		if has_cmp then
			cmp.setup.buffer({ enabled = true })
		end

		-- Re-enable blink-cmp
		vim.b[bufnr].blink_cmp_enabled = true
	end
end

---Setup paste override to protect sheltered content
---This ensures that pasted content is immediately masked without any flash of real values
setup_paste_override = function()
	if original_paste then
		return -- Already set up
	end

	original_paste = vim.paste
	vim.paste = function(lines, phase)
		local bufnr = nvim_get_current_buf()
		local bufname = nvim_buf_get_name(bufnr)
		local filename = fn.fnamemodify(bufname, ":t")

		-- Only intercept for env files when files feature is enabled
		if not is_env_file(filename) or not state.is_enabled("files") then
			return original_paste(lines, phase)
		end

		-- Convert string to lines if needed
		if type(lines) == "string" then
			lines = vim.split(lines, "\n", { plain = true })
		end

		if not lines or #lines == 0 then
			return true
		end

		-- Get cursor position and current line
		local cursor = api.nvim_win_get_cursor(0)
		local row, col = cursor[1], cursor[2]
		local current_line = api.nvim_get_current_line()
		local pre = current_line:sub(1, col)
		local post = current_line:sub(col + 1)

		-- Build new lines
		local new_lines = {}
		if #lines == 1 then
			new_lines[1] = pre .. (lines[1] or "") .. post
		else
			new_lines[1] = pre .. (lines[1] or "")
			for i = 2, #lines - 1 do
				new_lines[i] = lines[i] or ""
			end
			if #lines > 1 then
				new_lines[#lines] = (lines[#lines] or "") .. post
			end
		end

		-- Set flag to prevent TextChanged from interfering
		paste_in_progress = true

		-- Temporarily prevent screen updates during paste+mask operation
		local old_lazyredraw = vim.o.lazyredraw
		vim.o.lazyredraw = true

		-- Set the new lines (creates proper undo entry)
		pcall(api.nvim_buf_set_lines, bufnr, row - 1, row, false, new_lines)

		-- Update cursor position
		local new_row = row + #new_lines - 1
		local new_col = #new_lines == 1 and col + (#lines[1] or 0) or (#lines[#lines] or 0)
		pcall(api.nvim_win_set_cursor, 0, { new_row, new_col })

		-- Immediately re-apply masks SYNCHRONOUSLY to prevent any flash of real values
		-- Get full buffer content for masking
		local all_lines = nvim_buf_get_lines(bufnr, 0, -1, false)
		local content = table_concat(all_lines, "\n")

		-- Generate and apply masks synchronously (clears and re-applies in one go)
		local result = masking.generate_masks(content, bufname)
		if result.line_offsets and #result.line_offsets > 0 then
			apply_masks(bufnr, result.masks, result.line_offsets, true) -- sync=true
		end

		-- Restore lazyredraw and force a single redraw with masked content
		vim.o.lazyredraw = old_lazyredraw

		-- Clear the flag
		paste_in_progress = false

		return true
	end
end

---Restore original paste function
restore_paste_override = function()
	if original_paste then
		vim.paste = original_paste
		original_paste = nil
	end
end

---Setup buffer integration
function M.setup()
	-- Create autocommand group
	augroup = nvim_create_augroup("ShelterBuffer", { clear = true })

	-- Initialize feature state from config
	local cfg = config.get()
	-- Support both boolean and table config for files module
	local files_enabled = cfg.modules.files ~= false and cfg.modules.files ~= nil
	state.set_initial("files", files_enabled)

	-- Initialize pattern cache
	local engine = require("shelter.masking.engine")
	engine.init()

	-- Setup paste override for protection
	setup_paste_override()

	local watch_patterns = get_watch_patterns()

	-- BufReadCmd intercepts file reading BEFORE content is displayed
	-- This prevents the flash of unmasked values
	nvim_create_autocmd("BufReadCmd", {
		pattern = watch_patterns,
		group = augroup,
		callback = function(ev)
			local bufnr = ev.buf
			local filename = ev.file

			-- Guard: check if buffer already has content (prevent duplicate reads)
			local existing_lines = nvim_buf_get_lines(bufnr, 0, -1, false)
			if #existing_lines > 1 or (#existing_lines == 1 and existing_lines[1] ~= "") then
				-- Buffer already has content, just apply masks
				if state.is_enabled("files") then
					clear_extmarks(bufnr)
					local winid = nvim_get_current_win()
					setup_buffer_options(bufnr, winid)
					M.shelter_buffer(bufnr)
				end
				return true
			end

			-- Actually read the file
			local ok, err = pcall(function()
				vim.cmd("keepalt read " .. fn.fnameescape(filename))
				-- Remove the empty first line created by :read
				api.nvim_buf_set_lines(bufnr, 0, 1, false, {})

				-- Set filetype
				local ft = vim.filetype.match({ filename = filename })

				if ft then
					vim.bo[bufnr].filetype = ft
				else
					vim.bo[bufnr].filetype = "sh"
				end

				vim.bo[bufnr].modified = false
			end)

			if not ok then
				vim.notify("shelter.nvim: Failed to read file: " .. tostring(err), vim.log.levels.ERROR)
				return true
			end

			-- Apply masking immediately before displaying
			if state.is_enabled("files") then
				local winid = nvim_get_current_win()
				setup_buffer_options(bufnr, winid)
				M.shelter_buffer(bufnr)
			end

			return true
		end,
	})

	-- Handle buffer enter for already-loaded buffers
	nvim_create_autocmd("BufEnter", {
		pattern = watch_patterns,
		group = augroup,
		callback = function(ev)
			if state.is_enabled("files") then
				local winid = nvim_get_current_win()
				setup_buffer_options(ev.buf, winid)
				M.shelter_buffer(ev.buf)
			end
		end,
	})

	nvim_create_autocmd("BufLeave", {
		pattern = watch_patterns,
		group = augroup,
		callback = function(ev)
			local files_config = config.get_files_config()
			if files_config.shelter_on_leave then
				-- Reset revealed lines when leaving buffer
				state.reset_revealed_lines()

				-- Re-enable all initially enabled features
				state.enable_all_user_modules()

				-- Re-apply shelter to the buffer we're leaving
				if state.is_enabled("files") and nvim_buf_is_valid(ev.buf) then
					M.shelter_buffer(ev.buf)
				end
			end
		end,
	})

	-- TextChanged (non-insert) - applies to undo/redo/external changes
	-- Apply masks synchronously to prevent flash during undo/redo
	nvim_create_autocmd("TextChanged", {
		pattern = watch_patterns,
		group = augroup,
		callback = function(ev)
			-- Skip if paste operation is handling masking synchronously
			if paste_in_progress then
				return
			end

			if not state.is_enabled("files") then
				return
			end

			-- Clear cache on text change
			local engine = require("shelter.masking.engine")
			engine.clear_caches()

			-- Apply masks synchronously for undo/redo operations
			M.shelter_buffer(ev.buf, true) -- sync=true
		end,
	})

	-- TextChangedI (insert mode) - apply synchronously to prevent any flash
	-- Env files are typically small, so synchronous masking is performant
	nvim_create_autocmd("TextChangedI", {
		pattern = watch_patterns,
		group = augroup,
		callback = function(ev)
			-- Skip if paste operation is handling masking synchronously
			if paste_in_progress then
				return
			end

			if not state.is_enabled("files") then
				return
			end

			-- Clear cache on text change
			local engine = require("shelter.masking.engine")
			engine.clear_caches()

			-- Apply masks synchronously to prevent any flash of keystrokes
			M.shelter_buffer(ev.buf, true) -- sync=true
		end,
	})

	-- InsertLeave - ensure masks are applied when exiting insert mode
	nvim_create_autocmd("InsertLeave", {
		pattern = watch_patterns,
		group = augroup,
		callback = function(ev)
			if not state.is_enabled("files") then
				return
			end

			-- Clear cache and apply masks synchronously
			local engine = require("shelter.masking.engine")
			engine.clear_caches()
			M.shelter_buffer(ev.buf, true) -- sync=true
		end,
	})
end

---Cleanup buffer integration
function M.cleanup()
	if augroup then
		api.nvim_del_augroup_by_id(augroup)
		augroup = nil
	end

	-- Cleanup peek timer
	if peek_timer then
		peek_timer:stop()
		peek_timer:close()
		peek_timer = nil
	end
	state.reset_revealed_lines()

	-- Restore original paste function
	restore_paste_override()
end

return M
