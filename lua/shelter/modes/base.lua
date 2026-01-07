---@class ShelterModeBase
---Base class for all masking modes in shelter.nvim
---Implements the factory pattern - all modes (built-in and custom) extend this
local M = {}
M.__index = M

---@alias ShelterModeApplyFn fun(self: ShelterModeBase, ctx: ShelterModeContext): string

---@class ShelterOptionSchema
---@field type "string"|"number"|"boolean"|"table"|"function" Expected type
---@field default any Default value
---@field min? number Minimum value (for numbers)
---@field max? number Maximum value (for numbers)
---@field enum? any[] Valid values (for enums)
---@field description? string Option description

---@class ShelterModeContext
---@field key string Environment variable key
---@field value string Original value to mask
---@field source string|nil Source file path
---@field line_number number Line in file
---@field quote_type number 0=none, 1=single, 2=double
---@field is_comment boolean Whether in a comment
---@field config table Full plugin config

---@class ShelterModeDefinition
---@field name string Unique mode identifier
---@field description string Human-readable description
---@field apply ShelterModeApplyFn|fun(ctx: ShelterModeContext): string Mask function
---@field validate? fun(options: table): boolean, string? Validate options
---@field schema? table<string, ShelterOptionSchema> Option schema
---@field default_options? table<string, any> Default option values
---@field on_register? fun(mode: ShelterModeBase) Called when mode is registered
---@field on_configure? fun(mode: ShelterModeBase, options: table) Called when options change

---@class ShelterModeBase
---@field name string Unique mode identifier
---@field description string Human-readable description
---@field options table<string, any> Current options
---@field schema table<string, ShelterOptionSchema> Option schema
---@field _apply ShelterModeApplyFn Internal apply function
---@field _validate? fun(options: table): boolean, string? Internal validate function
---@field _on_configure? fun(mode: ShelterModeBase, options: table) Configure callback

---Create a new mode instance
---@param definition ShelterModeDefinition
---@return ShelterModeBase
function M.new(definition)
	vim.validate({
		name = { definition.name, "string" },
		description = { definition.description, "string" },
		apply = { definition.apply, "function" },
	})

	local self = setmetatable({}, M)

	self.name = definition.name
	self.description = definition.description
	self.schema = definition.schema or {}
	self.options = vim.deepcopy(definition.default_options or {})
	self._validate = definition.validate
	self._on_configure = definition.on_configure

	-- Wrap apply function to support both method and function styles
	local original_apply = definition.apply
	self._apply = function(mode, ctx)
		-- Inject mode options into context for convenience
		ctx.mode_options = mode.options
		return original_apply(mode, ctx)
	end

	-- Call on_register if provided
	if definition.on_register then
		definition.on_register(self)
	end

	return self
end

---Apply this mode to mask a value
---@param ctx ShelterModeContext
---@return string masked_value
function M:apply(ctx)
	return self._apply(self, ctx)
end

---Validate options against schema
---@param options table Options to validate
---@return boolean valid
---@return string? error_message
function M:validate(options)
	-- Run custom validation first if provided
	if self._validate then
		local ok, err = self._validate(options)
		if not ok then
			return false, err
		end
	end

	-- Schema validation
	for key, schema in pairs(self.schema) do
		local value = options[key]

		-- Check if required (no default and not nil)
		if value == nil and schema.default == nil then
			-- Optional fields with no default are ok as nil
		elseif value ~= nil then
			-- Type check
			if schema.type and type(value) ~= schema.type then
				return false, string.format("Option '%s' must be %s, got %s", key, schema.type, type(value))
			end

			-- Number bounds
			if schema.type == "number" then
				if schema.min and value < schema.min then
					return false, string.format("Option '%s' must be >= %d", key, schema.min)
				end
				if schema.max and value > schema.max then
					return false, string.format("Option '%s' must be <= %d", key, schema.max)
				end
			end

			-- Enum validation
			if schema.enum then
				local valid = false
				for _, enum_val in ipairs(schema.enum) do
					if value == enum_val then
						valid = true
						break
					end
				end
				if not valid then
					return false, string.format("Option '%s' must be one of: %s", key, table.concat(schema.enum, ", "))
				end
			end
		end
	end

	return true
end

---Configure mode with new options
---@param options table<string, any> New options to merge
---@return ShelterModeBase self
function M:configure(options)
	-- Validate first
	local ok, err = self:validate(options)
	if not ok then
		error(string.format("shelter.nvim: Invalid options for mode '%s': %s", self.name, err))
	end

	-- Apply schema defaults, then merge user options
	for key, schema in pairs(self.schema) do
		if self.options[key] == nil and schema.default ~= nil then
			self.options[key] = schema.default
		end
	end

	self.options = vim.tbl_deep_extend("force", self.options, options)

	-- Call on_configure callback if provided
	if self._on_configure then
		self._on_configure(self, options)
	end

	return self
end

---Get mode information
---@return table
function M:info()
	return {
		name = self.name,
		description = self.description,
		options = vim.deepcopy(self.options),
		schema = self.schema,
	}
end

---Create a copy of this mode with different options
---@param options? table<string, any> New options
---@return ShelterModeBase
function M:clone(options)
	local clone = setmetatable({}, M)
	clone.name = self.name
	clone.description = self.description
	clone.schema = self.schema
	clone.options = vim.deepcopy(self.options)
	clone._apply = self._apply
	clone._validate = self._validate
	clone._on_configure = self._on_configure

	if options then
		clone:configure(options)
	end

	return clone
end

---Get an option value with fallback to default
---@param key string Option key
---@param fallback? any Fallback if not found
---@return any
function M:get_option(key, fallback)
	local value = self.options[key]
	if value ~= nil then
		return value
	end

	local schema = self.schema[key]
	if schema and schema.default ~= nil then
		return schema.default
	end

	return fallback
end

return M
