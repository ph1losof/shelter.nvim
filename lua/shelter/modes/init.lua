---@class ShelterModes
---Factory and registry for masking modes in shelter.nvim
---
---Usage:
---```lua
---local modes = require("shelter.modes")
---
----- Create a built-in mode with custom options
---local partial = modes.create("partial", { show_start = 2, show_end = 2 })
---
----- Register a custom mode
---modes.define("redact", {
---  description = "Replace with [REDACTED]",
---  apply = function(self, ctx)
---    return "[REDACTED]"
---  end,
---})
---
----- Use in masking
---local masked = modes.apply("partial", "secret_value", context)
---```
local M = {}

local Base = require("shelter.modes.base")

-- Built-in mode definitions
local builtins = {
	full = require("shelter.modes.builtin.full"),
	partial = require("shelter.modes.builtin.partial"),
	none = require("shelter.modes.builtin.none"),
}

---@type table<string, ShelterModeDefinition>
local definitions = {}

---@type table<string, ShelterModeBase>
local instances = {}

---@type boolean
local initialized = false

---Initialize the mode system with built-in modes
local function ensure_initialized()
	if initialized then
		return
	end

	-- Register built-in mode definitions
	for name, mod in pairs(builtins) do
		definitions[name] = mod.definition
	end

	initialized = true
end

---Define a new mode (adds to definitions registry)
---@param name string Mode name
---@param definition ShelterModeDefinition|table Mode definition
---@return boolean success
function M.define(name, definition)
	ensure_initialized()

	vim.validate({
		name = { name, "string" },
		definition = { definition, "table" },
	})

	-- Check for required fields
	if not definition.apply then
		error(string.format("shelter.nvim: Mode '%s' must have an 'apply' function", name))
	end

	-- Fill in defaults
	definition.name = definition.name or name
	definition.description = definition.description or string.format("Custom mode: %s", name)
	definition.schema = definition.schema or {}
	definition.default_options = definition.default_options or {}

	-- Check if trying to redefine a built-in
	if builtins[name] then
		vim.notify(
			string.format("shelter.nvim: Overriding built-in mode '%s' with custom definition", name),
			vim.log.levels.INFO
		)
	end

	definitions[name] = definition

	-- Clear any cached instance so it's recreated with new definition
	instances[name] = nil

	return true
end

---Undefine a custom mode
---@param name string Mode name
---@return boolean success
function M.undefine(name)
	ensure_initialized()

	-- Cannot remove built-in modes
	if builtins[name] then
		vim.notify(
			string.format("shelter.nvim: Cannot undefine built-in mode '%s'", name),
			vim.log.levels.WARN
		)
		return false
	end

	if definitions[name] then
		definitions[name] = nil
		instances[name] = nil
		return true
	end

	return false
end

---Create a mode instance with optional configuration
---@param name string Mode name
---@param options? table<string, any> Configuration options
---@return ShelterModeBase
function M.create(name, options)
	ensure_initialized()

	local def = definitions[name]
	if not def then
		error(string.format("shelter.nvim: Unknown mode '%s'. Available modes: %s", name, table.concat(M.list(), ", ")))
	end

	-- Check if builtin module has a create function
	if builtins[name] and builtins[name].create then
		return builtins[name].create(options)
	end

	-- Create from definition
	local mode = Base.new(def)
	if options then
		mode:configure(options)
	end

	return mode
end

---Get or create a cached mode instance
---For internal use - modes are cached per-name with default options
---@param name string Mode name
---@return ShelterModeBase
function M.get(name)
	ensure_initialized()

	if instances[name] then
		return instances[name]
	end

	local mode = M.create(name)
	instances[name] = mode
	return mode
end

---Configure a cached mode instance with new options
---@param name string Mode name
---@param options table<string, any> Configuration options
---@return ShelterModeBase
function M.configure(name, options)
	ensure_initialized()

	-- Get or create the cached instance
	local mode = M.get(name)

	-- Configure it
	mode:configure(options)

	return mode
end

---Apply a mode to mask a value
---@param name string Mode name
---@param value string Value to mask
---@param context table Context (key, source, line_number, quote_type, is_comment, config)
---@return string masked_value
function M.apply(name, value, context)
	ensure_initialized()

	-- Handle unknown modes gracefully
	if not M.exists(name) then
		vim.notify(
			string.format("shelter.nvim: Unknown mode '%s', falling back to 'full'", name),
			vim.log.levels.WARN
		)
		name = "full"
	end

	local mode = M.get(name)

	-- Ensure context has value
	context = context or {}
	context.value = value

	return mode:apply(context)
end

---Check if a mode exists
---@param name string Mode name
---@return boolean
function M.exists(name)
	ensure_initialized()
	return definitions[name] ~= nil
end

---Check if a mode is a built-in
---@param name string Mode name
---@return boolean
function M.is_builtin(name)
	return builtins[name] ~= nil
end

---Get list of all registered mode names
---@return string[]
function M.list()
	ensure_initialized()

	local names = {}
	for name, _ in pairs(definitions) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

---Get mode information
---@param name string Mode name
---@return table|nil
function M.info(name)
	ensure_initialized()

	if not M.exists(name) then
		return nil
	end

	local mode = M.get(name)
	local info = mode:info()
	info.is_builtin = M.is_builtin(name)
	return info
end

---Get all mode information
---@return table<string, table>
function M.info_all()
	ensure_initialized()

	local all = {}
	for _, name in ipairs(M.list()) do
		all[name] = M.info(name)
	end
	return all
end

---Setup modes from config
---@param config table Config with modes table
function M.setup(config)
	ensure_initialized()

	local modes_config = config.modes or {}

	for name, mode_opts in pairs(modes_config) do
		if type(mode_opts) == "table" then
			-- Check if this is a mode definition (has apply function) or just options
			if mode_opts.apply then
				-- Register as new mode
				M.define(name, mode_opts)
			else
				-- Configure existing mode
				if M.exists(name) then
					M.configure(name, mode_opts)
				else
					vim.notify(
						string.format("shelter.nvim: Cannot configure unknown mode '%s'", name),
						vim.log.levels.WARN
					)
				end
			end
		end
	end

	-- Set mask_char for all modes if specified globally
	if config.mask_char then
		for _, name in ipairs({ "full", "partial" }) do
			local mode = M.get(name)
			if mode.options.mask_char then
				mode.options.mask_char = config.mask_char
			end
		end
	end
end

---Reset all modes to default state
function M.reset()
	instances = {}
	definitions = {}
	initialized = false
	ensure_initialized()
end

---Get the definition for a mode (for advanced usage)
---@param name string Mode name
---@return ShelterModeDefinition|nil
function M.get_definition(name)
	ensure_initialized()
	return definitions[name]
end

-- Export base class for external mode authors
M.Base = Base

return M
