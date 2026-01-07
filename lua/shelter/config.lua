---@class ShelterConfig
---Configuration module for shelter.nvim
local M = {}

---@class ShelterFilesModuleConfig
---Detailed configuration for the files module (buffer masking)
---@field shelter_on_leave? boolean Re-shelter when leaving buffer (default: true)
---@field disable_cmp? boolean Disable nvim-cmp/blink-cmp in sheltered buffers (default: true)

---@class ShelterModulesConfig
---@field files boolean|ShelterFilesModuleConfig Buffer masking (boolean or detailed config)
---@field telescope_previewer boolean Telescope preview masking
---@field fzf_previewer boolean FZF preview masking
---@field snacks_previewer boolean Snacks preview masking

---@class ShelterBufferConfig
---@field shelter_on_leave boolean Re-shelter when leaving buffer (deprecated, use modules.files.shelter_on_leave)

---@class ShelterModeConfig
---Mode configuration - can be options for built-in modes or custom mode definition
---@field apply? fun(self: table, ctx: table): string Custom apply function (makes this a mode definition)
---@field description? string Mode description
---@field schema? table<string, table> Option schema
---@field [string] any Mode-specific options

---@class ShelterUserConfig
---@field mask_char? string Character used for masking (default: "*")
---@field highlight_group? string Highlight group for masked text
---@field skip_comments? boolean Whether to skip masking in comments
---@field default_mode? "full"|"partial"|"none"|string Default masking mode
---@field modes? table<string, ShelterModeConfig> Mode configurations and custom mode definitions
---@field env_file_patterns? string[] Patterns to match env files
---@field patterns? table<string, string> Key patterns to mode mapping
---@field sources? table<string, string> Source file patterns to mode mapping
---@field modules? ShelterModulesConfig Module toggles
---@field buffer? ShelterBufferConfig Buffer-specific settings

---@type ShelterUserConfig
local DEFAULT_CONFIG = {
	mask_char = "*",
	highlight_group = "Comment",
	skip_comments = true,
	default_mode = "full",
	modes = {
		full = {
			mask_char = "*",
			preserve_length = true,
		},
		partial = {
			mask_char = "*",
			show_start = 3,
			show_end = 3,
			min_mask = 3,
			fallback_mode = "full",
		},
		none = {},
	},
	env_file_patterns = { ".env", ".env.*", ".envrc" },
	patterns = {},
	sources = {},
	modules = {
		files = true, -- Can be boolean or { shelter_on_leave = true, disable_cmp = true }
		telescope_previewer = false,
		fzf_previewer = false,
		snacks_previewer = false,
	},
	buffer = {
		shelter_on_leave = true, -- Deprecated, use modules.files.shelter_on_leave
	},
}

---@type ShelterUserConfig
local config = vim.deepcopy(DEFAULT_CONFIG)

---Setup configuration
---@param opts? ShelterUserConfig
function M.setup(opts)
	config = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULT_CONFIG), opts or {})
	M.validate()
end

---Get current configuration
---@return ShelterUserConfig
function M.get()
	return config
end

---Get a specific config value
---@param key string
---@return any
function M.get_value(key)
	return config[key]
end

---Validate configuration
function M.validate()
	vim.validate({
		mask_char = { config.mask_char, "string" },
		highlight_group = { config.highlight_group, "string" },
		skip_comments = { config.skip_comments, "boolean" },
		default_mode = { config.default_mode, "string" },
		env_file_patterns = { config.env_file_patterns, "table" },
		patterns = { config.patterns, "table" },
		sources = { config.sources, "table" },
		modules = { config.modules, "table" },
		buffer = { config.buffer, "table" },
		modes = { config.modes, "table" },
	})

	-- Validate modes table
	for name, mode_config in pairs(config.modes) do
		if type(mode_config) ~= "table" then
			error(string.format("shelter.nvim: Mode '%s' config must be a table", name))
		end
		if mode_config.apply and type(mode_config.apply) ~= "function" then
			error(string.format("shelter.nvim: Mode '%s' apply must be a function", name))
		end
	end
end

---Check if a module is enabled
---@param module string
---@return boolean
function M.is_module_enabled(module)
	local value = config.modules[module]
	-- For files module, both true and table mean enabled
	if module == "files" then
		return value == true or type(value) == "table"
	end
	return value == true
end

---Get files module configuration (normalized)
---Returns a table with shelter_on_leave and disable_cmp
---@return ShelterFilesModuleConfig
function M.get_files_config()
	local files = config.modules.files

	-- Default values
	local defaults = {
		shelter_on_leave = true,
		disable_cmp = true,
	}

	-- If files is boolean or nil, return defaults
	if type(files) ~= "table" then
		-- Check deprecated buffer.shelter_on_leave for backward compatibility
		if config.buffer and config.buffer.shelter_on_leave ~= nil then
			defaults.shelter_on_leave = config.buffer.shelter_on_leave
		end
		return defaults
	end

	-- Merge user config with defaults
	return vim.tbl_extend("force", defaults, files)
end

return M
