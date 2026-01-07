-- Tests for shelter.modes module
-- Run with: nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/plenary/modes_spec.lua"

local modes = require("shelter.modes")
local Base = require("shelter.modes.base")

describe("shelter.modes", function()
	-- Reset modes before each test to ensure clean state
	before_each(function()
		modes.reset()
	end)

	describe("built-in modes", function()
		it("has full mode registered", function()
			assert.is_true(modes.exists("full"))
			assert.is_true(modes.is_builtin("full"))
		end)

		it("has partial mode registered", function()
			assert.is_true(modes.exists("partial"))
			assert.is_true(modes.is_builtin("partial"))
		end)

		it("has none mode registered", function()
			assert.is_true(modes.exists("none"))
			assert.is_true(modes.is_builtin("none"))
		end)

		it("lists all built-in modes", function()
			local list = modes.list()
			assert.is_true(vim.tbl_contains(list, "full"))
			assert.is_true(vim.tbl_contains(list, "partial"))
			assert.is_true(vim.tbl_contains(list, "none"))
		end)
	end)

	describe("full mode", function()
		it("masks entire value", function()
			local ctx = { key = "TEST", value = "secret123", line_number = 1 }
			local result = modes.apply("full", ctx.value, ctx)
			assert.equals("*********", result)
			assert.equals(#ctx.value, #result)
		end)

		it("respects custom mask_char", function()
			modes.configure("full", { mask_char = "#" })
			local ctx = { key = "TEST", value = "secret", line_number = 1 }
			local result = modes.apply("full", ctx.value, ctx)
			assert.equals("######", result)
		end)

		it("handles empty value", function()
			local ctx = { key = "TEST", value = "", line_number = 1 }
			local result = modes.apply("full", ctx.value, ctx)
			assert.equals("", result)
		end)

		it("can create with fixed_length option", function()
			local full_mode = modes.create("full", { fixed_length = 5 })
			local ctx = { key = "TEST", value = "verylongsecret", line_number = 1 }
			local result = full_mode:apply(ctx)
			assert.equals("*****", result)
			assert.equals(5, #result)
		end)
	end)

	describe("partial mode", function()
		it("shows start and end characters", function()
			local ctx = { key = "TEST", value = "mysecretvalue", line_number = 1 }
			local result = modes.apply("partial", ctx.value, ctx)
			-- Default: show_start=3, show_end=3, min_mask=3
			assert.equals("mys*******lue", result)
		end)

		it("falls back to full for short values", function()
			local ctx = { key = "TEST", value = "abc", line_number = 1 }
			local result = modes.apply("partial", ctx.value, ctx)
			-- Too short for partial, should mask fully
			assert.equals("***", result)
		end)

		it("respects custom show_start and show_end", function()
			modes.configure("partial", { show_start = 2, show_end = 2, min_mask = 2 })
			local ctx = { key = "TEST", value = "mysecretvalue", line_number = 1 }
			local result = modes.apply("partial", ctx.value, ctx)
			assert.equals("my*********ue", result)
		end)

		it("can use none as fallback for short values", function()
			local partial = modes.create("partial", { fallback_mode = "none", min_mask = 5 })
			local ctx = { key = "TEST", value = "hi", line_number = 1 }
			local result = partial:apply(ctx)
			-- Too short, fallback to none
			assert.equals("hi", result)
		end)
	end)

	describe("none mode", function()
		it("returns value unchanged", function()
			local ctx = { key = "TEST", value = "secret123", line_number = 1 }
			local result = modes.apply("none", ctx.value, ctx)
			assert.equals("secret123", result)
		end)

		it("supports optional transform function", function()
			local none = modes.create("none", {
				transform = function(value)
					return "[" .. value .. "]"
				end,
			})
			local ctx = { key = "TEST", value = "secret", line_number = 1 }
			local result = none:apply(ctx)
			assert.equals("[secret]", result)
		end)
	end)

	describe("custom modes", function()
		it("can define a simple custom mode", function()
			modes.define("redact", {
				description = "Replace with [REDACTED]",
				apply = function(self, ctx)
					return "[REDACTED]"
				end,
			})

			assert.is_true(modes.exists("redact"))
			assert.is_false(modes.is_builtin("redact"))

			local ctx = { key = "TEST", value = "secret", line_number = 1 }
			local result = modes.apply("redact", ctx.value, ctx)
			assert.equals("[REDACTED]", result)
		end)

		it("can define mode with options schema", function()
			modes.define("truncate", {
				description = "Truncate and add suffix",
				schema = {
					max_length = { type = "number", default = 5 },
					suffix = { type = "string", default = "..." },
				},
				default_options = {
					max_length = 5,
					suffix = "...",
				},
				apply = function(self, ctx)
					local max = self:get_option("max_length", 5)
					local suffix = self:get_option("suffix", "...")
					if #ctx.value <= max then
						return ctx.value
					end
					return ctx.value:sub(1, max) .. suffix
				end,
			})

			local ctx = { key = "TEST", value = "very_long_secret", line_number = 1 }
			local result = modes.apply("truncate", ctx.value, ctx)
			assert.equals("very_...", result)
		end)

		it("can configure custom mode options", function()
			modes.define("prefix", {
				description = "Add prefix to value",
				schema = {
					prefix = { type = "string", default = "***" },
				},
				default_options = { prefix = "***" },
				apply = function(self, ctx)
					return self:get_option("prefix") .. ctx.value
				end,
			})

			modes.configure("prefix", { prefix = "SECRET: " })
			local ctx = { key = "TEST", value = "foo", line_number = 1 }
			local result = modes.apply("prefix", ctx.value, ctx)
			assert.equals("SECRET: foo", result)
		end)

		it("can undefine custom modes", function()
			modes.define("temp_mode", {
				description = "Temporary mode",
				apply = function()
					return "temp"
				end,
			})

			assert.is_true(modes.exists("temp_mode"))
			modes.undefine("temp_mode")
			assert.is_false(modes.exists("temp_mode"))
		end)

		it("cannot undefine built-in modes", function()
			local result = modes.undefine("full")
			assert.is_false(result)
			assert.is_true(modes.exists("full"))
		end)
	end)

	describe("mode factory (create)", function()
		it("creates independent mode instances", function()
			local mode1 = modes.create("full", { mask_char = "#" })
			local mode2 = modes.create("full", { mask_char = "@" })

			local ctx = { key = "TEST", value = "abc", line_number = 1 }
			assert.equals("###", mode1:apply(ctx))
			assert.equals("@@@", mode2:apply(ctx))
		end)

		it("errors on unknown mode", function()
			assert.has_error(function()
				modes.create("nonexistent")
			end)
		end)
	end)

	describe("mode cloning", function()
		it("can clone a mode with new options", function()
			local original = modes.create("full", { mask_char = "*" })
			local cloned = original:clone({ mask_char = "#" })

			local ctx = { key = "TEST", value = "abc", line_number = 1 }
			assert.equals("***", original:apply(ctx))
			assert.equals("###", cloned:apply(ctx))
		end)
	end)

	describe("mode info", function()
		it("returns mode information", function()
			local info = modes.info("full")
			assert.is_table(info)
			assert.equals("full", info.name)
			assert.equals("Replace all characters with mask character", info.description)
			assert.is_true(info.is_builtin)
		end)

		it("returns nil for unknown modes", function()
			local info = modes.info("nonexistent")
			assert.is_nil(info)
		end)

		it("returns all mode info", function()
			local all = modes.info_all()
			assert.is_table(all)
			assert.is_table(all.full)
			assert.is_table(all.partial)
			assert.is_table(all.none)
		end)
	end)

	describe("setup from config", function()
		it("configures modes from config table", function()
			modes.setup({
				modes = {
					partial = { show_start = 1, show_end = 1 },
				},
			})

			local mode = modes.get("partial")
			assert.equals(1, mode:get_option("show_start"))
			assert.equals(1, mode:get_option("show_end"))
		end)

		it("registers custom modes from config", function()
			modes.setup({
				modes = {
					custom_test = {
						description = "Test mode from config",
						apply = function()
							return "from_config"
						end,
					},
				},
			})

			assert.is_true(modes.exists("custom_test"))
			local ctx = { key = "TEST", value = "x", line_number = 1 }
			assert.equals("from_config", modes.apply("custom_test", ctx.value, ctx))
		end)

		it("applies global mask_char to all modes", function()
			modes.setup({
				mask_char = "#",
			})

			local full_mode = modes.get("full")
			local partial_mode = modes.get("partial")
			assert.equals("#", full_mode:get_option("mask_char"))
			assert.equals("#", partial_mode:get_option("mask_char"))
		end)
	end)

	describe("error handling", function()
		it("falls back to full for unknown modes", function()
			-- apply should warn but not error
			local ctx = { key = "TEST", value = "secret", line_number = 1 }
			local result = modes.apply("nonexistent", ctx.value, ctx)
			assert.equals("******", result)
		end)

		it("validates mode options on configure", function()
			local partial = modes.create("partial")
			-- This should work
			partial:configure({ show_start = 2 })

			-- This should fail validation (mask_char must be single char)
			assert.has_error(function()
				partial:configure({ mask_char = "**" })
			end)
		end)
	end)
end)

describe("shelter.modes.base", function()
	describe("new", function()
		it("creates a mode from definition", function()
			local mode = Base.new({
				name = "test",
				description = "Test mode",
				apply = function(self, ctx)
					return "masked:" .. ctx.value
				end,
			})

			assert.equals("test", mode.name)
			assert.equals("Test mode", mode.description)
		end)

		it("requires name, description, and apply", function()
			assert.has_error(function()
				Base.new({ description = "test", apply = function() end })
			end)
			assert.has_error(function()
				Base.new({ name = "test", apply = function() end })
			end)
			assert.has_error(function()
				Base.new({ name = "test", description = "test" })
			end)
		end)
	end)

	describe("schema validation", function()
		it("validates number types", function()
			local mode = Base.new({
				name = "test",
				description = "test",
				schema = {
					count = { type = "number", min = 0, max = 10 },
				},
				apply = function()
					return ""
				end,
			})

			local ok, err = mode:validate({ count = 5 })
			assert.is_true(ok)

			ok, err = mode:validate({ count = -1 })
			assert.is_false(ok)
			assert.is_truthy(err:match(">="))

			ok, err = mode:validate({ count = 20 })
			assert.is_false(ok)
			assert.is_truthy(err:match("<="))
		end)

		it("validates enum values", function()
			local mode = Base.new({
				name = "test",
				description = "test",
				schema = {
					style = { type = "string", enum = { "a", "b", "c" } },
				},
				apply = function()
					return ""
				end,
			})

			local ok = mode:validate({ style = "a" })
			assert.is_true(ok)

			ok = mode:validate({ style = "invalid" })
			assert.is_false(ok)
		end)
	end)

	describe("get_option", function()
		it("returns option value", function()
			local mode = Base.new({
				name = "test",
				description = "test",
				default_options = { foo = "bar" },
				apply = function()
					return ""
				end,
			})

			assert.equals("bar", mode:get_option("foo"))
		end)

		it("returns schema default if option not set", function()
			local mode = Base.new({
				name = "test",
				description = "test",
				schema = {
					foo = { type = "string", default = "default_value" },
				},
				apply = function()
					return ""
				end,
			})

			assert.equals("default_value", mode:get_option("foo"))
		end)

		it("returns fallback if no default", function()
			local mode = Base.new({
				name = "test",
				description = "test",
				apply = function()
					return ""
				end,
			})

			assert.equals("fallback", mode:get_option("missing", "fallback"))
		end)
	end)
end)
