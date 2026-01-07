---@class ShelterPartialMode
---Partial masking mode - shows start/end characters, masks middle
local Base = require("shelter.modes.base")

---@type ShelterModeDefinition
local definition = {
	name = "partial",
	description = "Show start and end characters, mask the middle",

	schema = {
		mask_char = {
			type = "string",
			default = "*",
			description = "Character used for masking",
		},
		show_start = {
			type = "number",
			default = 3,
			min = 0,
			description = "Number of characters to show at start",
		},
		show_end = {
			type = "number",
			default = 3,
			min = 0,
			description = "Number of characters to show at end",
		},
		min_mask = {
			type = "number",
			default = 3,
			min = 1,
			description = "Minimum number of mask characters (if value is long enough)",
		},
		fallback_mode = {
			type = "string",
			default = "full",
			enum = { "full", "none" },
			description = "Mode to use when value is too short for partial masking",
		},
	},

	default_options = {
		mask_char = "*",
		show_start = 3,
		show_end = 3,
		min_mask = 3,
		fallback_mode = "full",
	},

	---@param self ShelterModeBase
	---@param ctx ShelterModeContext
	---@return string
	apply = function(self, ctx)
		local native_ok, native = pcall(require, "shelter.native")
		local mask_char = self:get_option("mask_char", "*")
		local show_start = self:get_option("show_start", 3)
		local show_end = self:get_option("show_end", 3)
		local min_mask = self:get_option("min_mask", 3)

		local value = ctx.value
		local value_len = #value

		-- Check if value is long enough for partial masking
		local min_length = show_start + show_end + min_mask
		if value_len < min_length then
			-- Use fallback mode for short values
			local fallback = self:get_option("fallback_mode", "full")
			if fallback == "none" then
				return value
			else
				-- Full mask
				if native_ok then
					return native.mask_full(value, mask_char)
				else
					return string.rep(mask_char, value_len)
				end
			end
		end

		-- Partial masking
		if native_ok then
			return native.mask_partial(value, mask_char, show_start, show_end, min_mask)
		else
			-- Fallback: pure Lua implementation
			local mask_len = value_len - show_start - show_end
			return value:sub(1, show_start) .. string.rep(mask_char, mask_len) .. value:sub(-show_end)
		end
	end,

	---@param options table
	---@return boolean, string?
	validate = function(options)
		if options.mask_char and #options.mask_char ~= 1 then
			return false, "mask_char must be a single character"
		end
		if options.show_start and options.show_start < 0 then
			return false, "show_start must be >= 0"
		end
		if options.show_end and options.show_end < 0 then
			return false, "show_end must be >= 0"
		end
		return true
	end,
}

---Create a new partial mode instance
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
