---@class ShelterTelescopeIntegration
---Telescope previewer integration for shelter.nvim
local M = {}

local state = require("shelter.state")
local env_file = require("shelter.utils.env_file")

---Create a masked buffer previewer
---@param preview_type "file"|"grep"
---@return function
local function create_masked_previewer(preview_type)
	return function(opts)
		-- If feature disabled, use original previewer
		if not state.is_enabled("telescope_previewer") then
			local orig = preview_type == "file" and state.get_original("file_previewer")
				or state.get_original("grep_previewer")
			return orig and orig(opts)
		end

		local previewers = require("telescope.previewers")
		local from_entry = require("telescope.from_entry")
		local conf = require("telescope.config").values

		opts = opts or {}

		return previewers.new_buffer_previewer({
			title = opts.title or (preview_type == "file" and "File Preview" or "Preview"),

			get_buffer_by_name = function(_, entry)
				return preview_type == "file" and from_entry.path(entry, false) or entry.filename
			end,

			define_preview = function(self, entry)
				if not entry then
					return
				end

				local path = preview_type == "file" and from_entry.path(entry, false) or entry.filename
				if not path or path == "" then
					return
				end

				conf.buffer_previewer_maker(path, self.state.bufnr, {
					bufname = self.state.bufname,
					callback = function(bufnr)
						-- Handle grep line navigation
						if preview_type == "grep" and entry.lnum then
							vim.schedule(function()
								if vim.api.nvim_buf_is_valid(bufnr) then
									local line_count = vim.api.nvim_buf_line_count(bufnr)
									if entry.lnum <= line_count then
										pcall(vim.api.nvim_win_set_cursor, self.state.winid, { entry.lnum, entry.col or 0 })
										vim.api.nvim_win_call(self.state.winid, function()
											vim.cmd("normal! zz")
										end)
									end
								end
							end)
						end

						-- Apply masking if env file
						local filename = vim.fn.fnamemodify(path, ":t")
						if env_file.is_env_file(filename) then
							local buffer = require("shelter.integrations.buffer")
							buffer.shelter_preview_buffer(bufnr, filename)
						end
					end,
				})
			end,
		})
	end
end

---Setup telescope previewer integration
function M.setup()
	-- Check if telescope is available
	local ok, telescope_config = pcall(require, "telescope.config")
	if not ok then
		return
	end

	state.set_initial("telescope_previewer", true)

	local conf = telescope_config.values

	-- Store original previewers if not already stored
	if not state.get_original("file_previewer") then
		state.set_original("file_previewer", conf.file_previewer)
	end
	if not state.get_original("grep_previewer") then
		state.set_original("grep_previewer", conf.grep_previewer)
	end

	-- Replace with masked previewers
	conf.file_previewer = create_masked_previewer("file")
	conf.grep_previewer = create_masked_previewer("grep")
end

---Cleanup telescope integration
function M.cleanup()
	local ok, telescope_config = pcall(require, "telescope.config")
	if not ok then
		return
	end

	local conf = telescope_config.values

	local orig_file = state.get_original("file_previewer")
	if orig_file then
		conf.file_previewer = orig_file
		state.clear_original("file_previewer")
	end

	local orig_grep = state.get_original("grep_previewer")
	if orig_grep then
		conf.grep_previewer = orig_grep
		state.clear_original("grep_previewer")
	end
end

return M
