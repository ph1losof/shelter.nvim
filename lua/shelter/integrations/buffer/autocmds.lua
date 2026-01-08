---@class ShelterAutocmds
---Autocmd management for buffer integration
local M = {}

local config = require("shelter.config")

-- Fast locals
local api = vim.api
local nvim_create_autocmd = api.nvim_create_autocmd
local nvim_create_augroup = api.nvim_create_augroup
local nvim_del_augroup_by_id = api.nvim_del_augroup_by_id

-- Autocommand group
local augroup = nil

---Get filetypes for autocmds from config
---@return string[]
local function get_env_filetypes()
	local cfg = config.get()
	return cfg.env_filetypes or { "sh", "dotenv", "conf" }
end

---@class ShelterAutocmdCallbacks
---@field on_filetype fun(ev: table) Called on FileType event
---@field on_buf_enter fun(ev: table) Called on BufEnter event
---@field on_buf_leave fun(ev: table) Called on BufLeave event
---@field on_text_changed fun(ev: table) Called on TextChanged event
---@field on_text_changed_i fun(ev: table) Called on TextChangedI event
---@field on_insert_leave fun(ev: table) Called on InsertLeave event

---Setup buffer autocmds
---@param callbacks ShelterAutocmdCallbacks
function M.setup(callbacks)
	-- Create autocommand group
	augroup = nvim_create_augroup("ShelterBuffer", { clear = true })

	local env_filetypes = get_env_filetypes()

	-- FileType autocmd - triggers when filetype is set (after file is loaded)
	nvim_create_autocmd("FileType", {
		pattern = env_filetypes,
		group = augroup,
		callback = callbacks.on_filetype,
	})

	-- BufEnter - re-apply masks when entering a buffer
	nvim_create_autocmd("BufEnter", {
		group = augroup,
		callback = callbacks.on_buf_enter,
	})

	-- BufLeave - re-shelter when leaving buffer
	nvim_create_autocmd("BufLeave", {
		group = augroup,
		callback = callbacks.on_buf_leave,
	})

	-- TextChanged (non-insert) - applies to undo/redo/external changes
	nvim_create_autocmd("TextChanged", {
		group = augroup,
		callback = callbacks.on_text_changed,
	})

	-- TextChangedI (insert mode)
	nvim_create_autocmd("TextChangedI", {
		group = augroup,
		callback = callbacks.on_text_changed_i,
	})

	-- InsertLeave - ensure masks are applied when exiting insert mode
	nvim_create_autocmd("InsertLeave", {
		group = augroup,
		callback = callbacks.on_insert_leave,
	})
end

---Cleanup autocmds
function M.cleanup()
	if augroup then
		nvim_del_augroup_by_id(augroup)
		augroup = nil
	end
end

return M
