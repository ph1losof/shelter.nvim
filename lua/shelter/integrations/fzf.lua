---@class ShelterFzfIntegration
---FZF-lua previewer integration for shelter.nvim
local M = {}

local state = require("shelter.state")
local config = require("shelter.config")

---Check if a file is an env file
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

---Setup FZF previewer integration
function M.setup()
	-- Check if fzf-lua is available
	local ok = pcall(require, "fzf-lua")
	if not ok then
		return
	end

	state.set_initial("fzf_previewer", true)

	local builtin = require("fzf-lua.previewer.builtin")
	local buffer_or_file = builtin.buffer_or_file

	-- Store original function if not already stored
	if not state.get_original("fzf_preview_buf_post") then
		state.set_original("fzf_preview_buf_post", buffer_or_file.preview_buf_post)
	end

	-- Override preview_buf_post
	buffer_or_file.preview_buf_post = function(self, entry, min_winopts)
		-- Call original first
		local original = state.get_original("fzf_preview_buf_post")
		if original then
			original(self, entry, min_winopts)
		end

		-- Check if feature is enabled
		if not state.is_enabled("fzf_previewer") then
			return
		end

		-- Get buffer number
		local bufnr = self.preview_bufnr
		if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end

		-- Get filename from entry
		local filename = entry.path or entry.filename or entry.name
		if not filename then
			return
		end

		-- Apply masking if env file
		local basename = vim.fn.fnamemodify(filename, ":t")
		if M.is_env_file(filename) then
			local buffer = require("shelter.integrations.buffer")
			buffer.shelter_preview_buffer(bufnr, basename)
		end
	end
end

---Cleanup FZF integration
function M.cleanup()
	local ok, builtin = pcall(require, "fzf-lua.previewer.builtin")
	if not ok then
		return
	end

	local original = state.get_original("fzf_preview_buf_post")
	if original then
		builtin.buffer_or_file.preview_buf_post = original
		state.clear_original("fzf_preview_buf_post")
	end
end

return M
