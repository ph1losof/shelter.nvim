---@class ShelterNoneMode
---No masking mode - returns value as-is (for whitelisted keys)
local Base = require("shelter.modes.base")

---@type ShelterModeDefinition
local definition = {
	name = "none",
	description = "No masking - show value as-is",

	schema = {
		-- None mode has no options, but we support an optional transform
		transform = {
			type = "function",
			default = nil,
			description = "Optional transform function to apply to value (for advanced use)",
		},
	},

	default_options = {},

	---@param self ShelterModeBase
	---@param ctx ShelterModeContext
	---@return string
	apply = function(self, ctx)
		local transform = self.options.transform

		-- Apply optional transform if provided
		if transform and type(transform) == "function" then
			return transform(ctx.value, ctx)
		end

		-- No masking - return as-is
		return ctx.value
	end,

	---@param options table
	---@return boolean, string?
	validate = function(options)
		if options.transform and type(options.transform) ~= "function" then
			return false, "transform must be a function"
		end
		return true
	end,
}

---Create a new none mode instance
---@param options? table<string, any>
---@return ShelterModeBase
local function create(options)
	local mode = Base.new(definition)
	if options then
		mode:configure(options)
	end
	return mode
end

return {
	definition = definition,
	create = create,
}
