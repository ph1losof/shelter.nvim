---@class ShelterFullMode
---Full masking mode - replaces all characters with mask character
local Base = require("shelter.modes.base")

---@type ShelterModeDefinition
local definition = {
	name = "full",
	description = "Replace all characters with mask character",

	schema = {
		mask_char = {
			type = "string",
			default = "*",
			description = "Character used for masking",
		},
		preserve_length = {
			type = "boolean",
			default = true,
			description = "Whether to preserve original value length",
		},
		fixed_length = {
			type = "number",
			default = nil,
			min = 1,
			description = "Fixed output length (overrides preserve_length)",
		},
	},

	default_options = {
		mask_char = "*",
		preserve_length = true,
	},

	---@param self ShelterModeBase
	---@param ctx ShelterModeContext
	---@return string
	apply = function(self, ctx)
		local native_ok, native = pcall(require, "shelter.native")
		local mask_char = self:get_option("mask_char", "*")
		local fixed_length = self:get_option("fixed_length")

		-- Use fixed length if specified
		if fixed_length then
			if native_ok then
				return native.mask_fixed(ctx.value, mask_char, fixed_length)
			else
				return string.rep(mask_char, fixed_length)
			end
		end

		-- Full masking with preserved length
		if native_ok then
			return native.mask_full(ctx.value, mask_char)
		else
			-- Fallback: pure Lua implementation
			return string.rep(mask_char, #ctx.value)
		end
	end,

	---@param options table
	---@return boolean, string?
	validate = function(options)
		if options.mask_char and #options.mask_char ~= 1 then
			return false, "mask_char must be a single character"
		end
		return true
	end,
}

---Create a new full mode instance
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
