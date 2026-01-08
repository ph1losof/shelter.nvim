---@class ShelterPeek
---Peek functionality for temporary line reveal
local M = {}

local state = require("shelter.state")

-- Peek timer and constants
local PEEK_DURATION = 3000 -- 3 seconds
local peek_timer = nil

---Peek a line temporarily (reveal for PEEK_DURATION milliseconds)
---@param bufnr number Buffer number
---@param line_num number Line number to reveal
---@param refresh_callback fun() Callback to refresh the buffer display
function M.peek_line(bufnr, line_num, refresh_callback)
	if not vim.api.nvim_buf_is_valid(bufnr) then
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
	refresh_callback()

	-- Set timer to hide after duration
	local uv = vim.uv or vim.loop
	peek_timer = uv.new_timer()
	peek_timer:start(
		PEEK_DURATION,
		0,
		vim.schedule_wrap(function()
			M.hide_line(bufnr, line_num, refresh_callback)
			if peek_timer then
				peek_timer:stop()
				peek_timer:close()
				peek_timer = nil
			end
		end)
	)
end

---Hide a peeked line
---@param bufnr number Buffer number
---@param line_num number Line number to hide
---@param refresh_callback fun() Callback to refresh the buffer display
function M.hide_line(bufnr, line_num, refresh_callback)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	state.hide_line(line_num)
	refresh_callback()
end

---Toggle peek for a line
---@param bufnr number Buffer number
---@param line_num number Line number
---@param refresh_callback fun() Callback to refresh the buffer display
function M.toggle_peek(bufnr, line_num, refresh_callback)
	if state.is_line_revealed(line_num) then
		M.hide_line(bufnr, line_num, refresh_callback)
	else
		M.peek_line(bufnr, line_num, refresh_callback)
	end
end

---Cleanup peek resources
function M.cleanup()
	if peek_timer then
		peek_timer:stop()
		peek_timer:close()
		peek_timer = nil
	end
	state.reset_revealed_lines()
end

return M
