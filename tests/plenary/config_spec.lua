-- Tests for shelter.config module
-- Run with: nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/plenary/config_spec.lua"

local config = require("shelter.config")

describe("shelter.config", function()
	before_each(function()
		-- Reset to defaults before each test
		config.setup({})
	end)

	describe("setup", function()
		it("uses default values when no options provided", function()
			config.setup({})
			local cfg = config.get()

			assert.equals("*", cfg.mask_char)
			assert.is_true(cfg.skip_comments)
			assert.equals("full", cfg.default_mode)
			assert.equals("Comment", cfg.highlight_group)
		end)

		it("merges user options with defaults", function()
			config.setup({
				mask_char = "#",
				skip_comments = false,
			})
			local cfg = config.get()

			assert.equals("#", cfg.mask_char)
			assert.is_false(cfg.skip_comments)
			assert.equals("full", cfg.default_mode) -- Default preserved
		end)

		it("sets custom patterns", function()
			config.setup({
				patterns = {
					["*_SECRET"] = "partial",
					["API_*"] = "none",
				},
			})
			local cfg = config.get()

			assert.equals("partial", cfg.patterns["*_SECRET"])
			assert.equals("none", cfg.patterns["API_*"])
		end)

		it("sets modes configuration", function()
			config.setup({
				modes = {
					partial = {
						show_start = 5,
						show_end = 5,
						min_mask = 5,
					},
				},
			})
			local cfg = config.get()

			assert.is_table(cfg.modes.partial)
			assert.equals(5, cfg.modes.partial.show_start)
			assert.equals(5, cfg.modes.partial.show_end)
			assert.equals(5, cfg.modes.partial.min_mask)
		end)

		it("sets env file patterns", function()
			config.setup({
				env_file_patterns = { ".env", ".env.local", "secrets" },
			})
			local cfg = config.get()

			assert.equals(3, #cfg.env_file_patterns)
			assert.equals(".env", cfg.env_file_patterns[1])
		end)

		it("sets module toggles", function()
			config.setup({
				modules = {
					files = false,
					peek = true,
					telescope_previewer = true,
				},
			})
			local cfg = config.get()

			assert.is_false(cfg.modules.files)
			assert.is_true(cfg.modules.peek)
			assert.is_true(cfg.modules.telescope_previewer)
		end)

		it("sets custom mode definitions", function()
			config.setup({
				modes = {
					custom = {
						description = "Custom mode",
						apply = function()
							return "custom"
						end,
					},
				},
			})
			local cfg = config.get()

			assert.is_table(cfg.modes.custom)
			assert.equals("Custom mode", cfg.modes.custom.description)
			assert.is_function(cfg.modes.custom.apply)
		end)
	end)

	describe("get", function()
		it("returns current configuration", function()
			config.setup({ mask_char = "X" })
			local cfg = config.get()
			assert.equals("X", cfg.mask_char)
		end)
	end)

	describe("get_value", function()
		it("returns specific config value", function()
			config.setup({ mask_char = "X" })
			assert.equals("X", config.get_value("mask_char"))
		end)

		it("returns nil for missing key", function()
			assert.is_nil(config.get_value("nonexistent"))
		end)
	end)

	describe("is_module_enabled", function()
		it("returns true for enabled modules", function()
			config.setup({
				modules = { files = true },
			})
			assert.is_true(config.is_module_enabled("files"))
		end)

		it("returns false for disabled modules", function()
			config.setup({
				modules = { telescope_previewer = false },
			})
			assert.is_false(config.is_module_enabled("telescope_previewer"))
		end)
	end)

	describe("validate", function()
		it("validates string types", function()
			-- Should not error with valid config
			assert.has_no.errors(function()
				config.setup({
					mask_char = "*",
					highlight_group = "Comment",
				})
			end)
		end)

		it("validates boolean types", function()
			assert.has_no.errors(function()
				config.setup({
					skip_comments = true,
				})
			end)
		end)

		it("validates table types", function()
			assert.has_no.errors(function()
				config.setup({
					patterns = { ["*"] = "full" },
					env_file_patterns = { ".env" },
					modes = {},
				})
			end)
		end)

		it("validates modes table entries", function()
			assert.has_no.errors(function()
				config.setup({
					modes = {
						full = { mask_char = "#" },
						custom = {
							apply = function()
								return "x"
							end,
						},
					},
				})
			end)
		end)
	end)

	describe("default values", function()
		it("has correct default mask_char", function()
			config.setup({})
			assert.equals("*", config.get().mask_char)
		end)

		it("has correct default skip_comments", function()
			config.setup({})
			assert.is_true(config.get().skip_comments)
		end)

		it("has correct default env_file_patterns", function()
			config.setup({})
			local patterns = config.get().env_file_patterns
			assert.is_table(patterns)
			assert.is_true(vim.tbl_contains(patterns, ".env"))
		end)

		it("has correct default modes table", function()
			config.setup({})
			local modes = config.get().modes
			assert.is_table(modes)
		end)

		it("has correct default_mode", function()
			config.setup({})
			assert.equals("full", config.get().default_mode)
		end)
	end)
end)
