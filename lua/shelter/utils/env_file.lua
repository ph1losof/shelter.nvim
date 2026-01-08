---@class ShelterEnvFileUtils
---Shared env file detection utilities for shelter.nvim
local M = {}

local config = require("shelter.config")

---Check if a filename matches env file patterns
---@param filename string
---@return boolean
function M.is_env_file(filename)
	local cfg = config.get()
	local basename = vim.fn.fnamemodify(filename, ":t")

	for _, pattern in ipairs(cfg.env_file_patterns or {}) do
		local lua_pattern = pattern:gsub("%*", ".*")
		lua_pattern = "^" .. lua_pattern .. "$"
		if basename:match(lua_pattern) then
			return true
		end
	end

	return false
end

---Check if a filetype is an env filetype
---@param filetype string
---@return boolean
function M.is_env_filetype(filetype)
	if not filetype or filetype == "" then
		return false
	end

	local cfg = config.get()
	for _, ft in ipairs(cfg.env_filetypes or {}) do
		if filetype == ft then
			return true
		end
	end

	return false
end

---Check if a buffer is an env file (by filetype)
---@param bufnr number
---@return boolean
function M.is_env_buffer(bufnr)
	local filetype = vim.bo[bufnr].filetype
	return M.is_env_filetype(filetype)
end

return M
