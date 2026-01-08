---@class ShelterPaste
---Paste protection for sheltered buffers
local M = {}

local state = require("shelter.state")
local env_file = require("shelter.utils.env_file")

-- Fast locals
local api = vim.api
local nvim_buf_get_name = api.nvim_buf_get_name
local nvim_buf_get_lines = api.nvim_buf_get_lines
local nvim_get_current_buf = api.nvim_get_current_buf
local table_concat = table.concat

-- Original paste function (for paste protection)
local original_paste = nil

-- Flag to prevent TextChanged from interfering during paste
local paste_in_progress = false

---Check if paste is in progress
---@return boolean
function M.is_paste_in_progress()
	return paste_in_progress
end

---Setup paste override to protect sheltered content
---@param apply_masks_fn fun(bufnr: number, masks: table, line_offsets: table, sync: boolean) Function to apply masks
---@param generate_masks_fn fun(content: string, source: string): table Function to generate masks
function M.setup(apply_masks_fn, generate_masks_fn)
	if original_paste then
		return -- Already set up
	end

	original_paste = vim.paste
	vim.paste = function(lines, phase)
		local bufnr = nvim_get_current_buf()
		local bufname = nvim_buf_get_name(bufnr)

		-- Only intercept for env filetypes when files feature is enabled
		if not env_file.is_env_buffer(bufnr) or not state.is_enabled("files") then
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
		local all_lines = nvim_buf_get_lines(bufnr, 0, -1, false)
		local content = table_concat(all_lines, "\n")

		-- Generate and apply masks synchronously
		local result = generate_masks_fn(content, bufname)
		if result.line_offsets and #result.line_offsets > 0 then
			apply_masks_fn(bufnr, result.masks, result.line_offsets, true) -- sync=true
		end

		-- Restore lazyredraw and force a single redraw with masked content
		vim.o.lazyredraw = old_lazyredraw

		-- Clear the flag
		paste_in_progress = false

		return true
	end
end

---Restore original paste function
function M.cleanup()
	if original_paste then
		vim.paste = original_paste
		original_paste = nil
	end
end

return M
