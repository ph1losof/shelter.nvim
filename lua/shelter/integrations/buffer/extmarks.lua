---@class ShelterExtmarks
---Extmark management for buffer masking
local M = {}

local config = require("shelter.config")
local state = require("shelter.state")

-- Fast locals for hot path
local api = vim.api
local nvim_buf_is_valid = api.nvim_buf_is_valid
local nvim_buf_get_lines = api.nvim_buf_get_lines
local nvim_buf_set_extmark = api.nvim_buf_set_extmark
local nvim_buf_clear_namespace = api.nvim_buf_clear_namespace
local nvim_create_namespace = api.nvim_create_namespace
local string_rep = string.rep
local math_max = math.max
local math_min = math.min

-- Namespace for extmarks
local ns_id = nil

---Get or create the namespace
---@return number
function M.get_namespace()
	if not ns_id then
		ns_id = nvim_create_namespace("shelter_mask")
	end
	return ns_id
end

---Clear all extmarks in a buffer
---@param bufnr number
function M.clear(bufnr)
	local ns = M.get_namespace()
	nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

---Apply masks to a buffer using batched extmark application
---@param bufnr number
---@param masks ShelterMaskedLine[]
---@param line_offsets number[] Pre-computed line offsets from Rust
---@param sync? boolean If true, apply synchronously (for paste protection)
function M.apply_masks(bufnr, masks, line_offsets, sync)
	local ns = M.get_namespace()
	local cfg = config.get()
	local hl_group = cfg.highlight_group or "Comment"
	local mask_char = cfg.mask_char or "*"

	-- Get all lines for calculating column positions
	local lines = nvim_buf_get_lines(bufnr, 0, -1, false)

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
						col_start = col_start + 1
					end
					col_end = #current_line
				elseif i == end_line_idx - start_line_idx then
					-- LAST line: mask only up to value_end, excluding closing quote
					local last_line_offset = line_offsets[mask_info.value_end_line] or 0
					col_start = 0
					col_end = math_max(0, mask_info.value_end - last_line_offset)
					if is_quoted then
						col_end = col_end - 1
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

return M
