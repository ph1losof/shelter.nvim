---@class ShelterModuleValidation
---Module validation utilities for shelter.nvim
local M = {}

---Module name aliases for convenience
M.ALIASES = {
	buffer = "files",
	telescope = "telescope_previewer",
	fzf = "fzf_previewer",
	snacks = "snacks_previewer",
}

---Valid module names
M.VALID_MODULES = {
	"files",
	"telescope_previewer",
	"fzf_previewer",
	"snacks_previewer",
}

---Normalize module name (handle aliases)
---@param name string|nil
---@return string|nil
function M.normalize(name)
	if not name then
		return nil
	end
	return M.ALIASES[name] or name
end

---Check if module name is valid
---@param name string
---@return boolean
function M.is_valid(name)
	return vim.tbl_contains(M.VALID_MODULES, name)
end

---Execute operation with validation
---@param target string|nil Raw module name from user
---@param single_op fun(module: string) Operation for single module
---@param all_op fun() Operation for all modules
---@return boolean success
function M.with_validation(target, single_op, all_op)
	local module = M.normalize(target)

	if module then
		if not M.is_valid(module) then
			vim.notify("shelter.nvim: Unknown module: " .. target, vim.log.levels.ERROR)
			return false
		end
		single_op(module)
	else
		all_op()
	end
	return true
end

return M
