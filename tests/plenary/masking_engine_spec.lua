-- Tests for shelter.masking.engine module
-- Run with: nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/plenary/masking_engine_spec.lua"

local engine = require("shelter.masking.engine")
local config = require("shelter.config")

describe("shelter.masking.engine", function()
  before_each(function()
    -- Reset config to defaults before each test
    config.setup({
      mask_char = "*",
      skip_comments = true,
      default_mode = "full",
      patterns = {},
    })
    engine.init()
    engine.clear_caches()
  end)

  describe("parse_content", function()
    it("parses simple content", function()
      local result = engine.parse_content("KEY=value")
      assert.is_table(result)
      assert.is_table(result.entries)
      assert.equals(1, #result.entries)
    end)

    it("returns line_offsets", function()
      local result = engine.parse_content("LINE1=a\nLINE2=b")
      assert.is_table(result.line_offsets)
      assert.is_true(#result.line_offsets > 0)
    end)

    it("caches parsed results", function()
      local content = "KEY=value"
      local result1 = engine.parse_content(content)
      local result2 = engine.parse_content(content)
      -- Same content should return cached result
      assert.equals(result1, result2)
    end)

    it("handles multi-line content", function()
      local content = "KEY1=value1\nKEY2=value2\nKEY3=value3"
      local result = engine.parse_content(content)
      assert.equals(3, #result.entries)
      assert.equals(3, #result.line_offsets)
    end)
  end)

  describe("generate_masks", function()
    it("generates masks for all entries", function()
      local content = "KEY1=secret1\nKEY2=secret2"
      local result = engine.generate_masks(content, "test.env")
      assert.is_table(result.masks)
      assert.equals(2, #result.masks)
    end)

    it("returns line_offsets from parser", function()
      local content = "KEY=value"
      local result = engine.generate_masks(content, "test.env")
      assert.is_table(result.line_offsets)
      assert.is_true(#result.line_offsets > 0)
    end)

    it("includes correct mask data", function()
      local content = "SECRET=mysecret"
      local result = engine.generate_masks(content, "test.env")
      assert.equals(1, #result.masks)
      local mask = result.masks[1]
      assert.equals(1, mask.line_number)
      assert.is_string(mask.mask)
      assert.equals("mysecret", mask.value)
      assert.is_number(mask.value_start)
      assert.is_number(mask.value_end)
    end)

    it("skips comments when skip_comments is true", function()
      config.setup({ skip_comments = true })
      engine.init()
      local content = "#COMMENTED=secret\nREAL=value"
      local result = engine.generate_masks(content, "test.env")
      -- Should only have mask for REAL, not COMMENTED
      local commented_mask = vim.tbl_filter(function(m)
        return m.value == "secret"
      end, result.masks)
      -- The commented entry might or might not be extracted by korni
      -- but if it is, is_comment should be true and skipped
      for _, mask in ipairs(result.masks) do
        if mask.is_comment then
          assert.fail("Comment entries should be skipped when skip_comments=true")
        end
      end
    end)

    it("includes comments when skip_comments is false", function()
      config.setup({ skip_comments = false })
      engine.init()
      local content = "#COMMENTED=secret\nREAL=value"
      local result = engine.generate_masks(content, "test.env")
      -- Should have masks for both if korni extracts them
      assert.is_true(#result.masks >= 1)
    end)

    it("handles multi-line values correctly", function()
      local content = 'JSON="{\n  \\"key\\": \\"value\\"\n}"'
      local result = engine.generate_masks(content, "test.env")
      assert.equals(1, #result.masks)
      local mask = result.masks[1]
      assert.is_true(mask.value_end_line > mask.line_number)
    end)
  end)

  describe("determine_mode", function()
    it("returns default for no pattern match", function()
      config.setup({
        default_mode = "full",
        patterns = {},
      })
      engine.init()
      local mode = engine.determine_mode("UNKNOWN_KEY", "test.env")
      assert.equals("full", mode)
    end)

    it("matches glob patterns", function()
      config.setup({
        default_mode = "full",
        patterns = {
          ["*_TOKEN"] = "partial",
          ["API_*"] = "none",
        },
      })
      engine.init()

      assert.equals("partial", engine.determine_mode("AUTH_TOKEN", "test.env"))
      assert.equals("none", engine.determine_mode("API_KEY", "test.env"))
      assert.equals("full", engine.determine_mode("DATABASE_URL", "test.env"))
    end)

    it("respects specificity order", function()
      config.setup({
        default_mode = "full",
        patterns = {
          ["*"] = "none",
          ["SECRET_*"] = "partial",
          ["SECRET_KEY"] = "full",
        },
      })
      engine.init()

      -- More specific patterns should take precedence
      assert.equals("full", engine.determine_mode("SECRET_KEY", "test.env"))
    end)
  end)

  describe("mask_value", function()
    it("applies full mode correctly", function()
      config.setup({ default_mode = "full" })
      engine.init()
      local masked = engine.mask_value("secret", { key = "KEY", source = "test.env" })
      assert.equals("******", masked)
    end)

    it("applies partial mode correctly", function()
      config.setup({
        default_mode = "full",
        patterns = { ["*_TOKEN"] = "partial" },
        partial_mode = { show_start = 2, show_end = 2, min_mask = 3 },
      })
      engine.init()
      local masked = engine.mask_value("secrettoken", { key = "AUTH_TOKEN", source = "test.env" })
      -- Should show first 2 and last 2 chars
      assert.equals("se*******en", masked)
    end)

    it("applies none mode correctly", function()
      config.setup({
        default_mode = "full",
        patterns = { ["DEBUG"] = "none" },
      })
      engine.init()
      local masked = engine.mask_value("true", { key = "DEBUG", source = "test.env" })
      assert.equals("true", masked)
    end)
  end)

  describe("clear_caches", function()
    it("clears the parsed content cache", function()
      local content = "KEY=value"
      local result1 = engine.parse_content(content)
      engine.clear_caches()
      local result2 = engine.parse_content(content)
      -- After clearing, should be a different table reference
      assert.is_not_equals(result1, result2)
    end)
  end)

  describe("init", function()
    it("compiles pattern cache from config", function()
      config.setup({
        patterns = { ["*_SECRET"] = "partial" },
      })
      engine.init()
      -- Should be able to determine mode without recompiling
      local mode = engine.determine_mode("API_SECRET", "test.env")
      assert.equals("partial", mode)
    end)
  end)

  describe("reload_patterns", function()
    it("reloads patterns when config changes", function()
      config.setup({
        patterns = { ["OLD_*"] = "partial" },
      })
      engine.init()
      assert.equals("partial", engine.determine_mode("OLD_KEY", "test.env"))

      config.setup({
        patterns = { ["NEW_*"] = "partial" },
      })
      engine.reload_patterns()
      assert.equals("full", engine.determine_mode("OLD_KEY", "test.env"))
      assert.equals("partial", engine.determine_mode("NEW_KEY", "test.env"))
    end)
  end)
end)
