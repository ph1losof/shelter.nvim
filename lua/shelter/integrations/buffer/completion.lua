---@class ShelterCompletion
---Completion control for sheltered buffers
local M = {}

local config = require("shelter.config")

---Disable completion for a sheltered buffer
---@param bufnr number
function M.disable(bufnr)
	local files_config = config.get_files_config()
	if not files_config.disable_cmp then
		return
	end

	vim.b[bufnr].completion = false

	-- Disable nvim-cmp if available
	local has_cmp, cmp = pcall(require, "cmp")
	if has_cmp then
		cmp.setup.buffer({ enabled = false })
	end

	-- Disable blink-cmp if available (uses buffer variable)
	vim.b[bufnr].blink_cmp_enabled = false
end

---Restore completion for a buffer
---@param bufnr number
function M.restore(bufnr)
	local files_config = config.get_files_config()
	if not files_config.disable_cmp then
		return
	end

	vim.b[bufnr].completion = true

	-- Re-enable nvim-cmp if available
	local has_cmp, cmp = pcall(require, "cmp")
	if has_cmp then
		cmp.setup.buffer({ enabled = true })
	end

	-- Re-enable blink-cmp
	vim.b[bufnr].blink_cmp_enabled = true
end

return M
