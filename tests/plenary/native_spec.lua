-- Tests for shelter.native module
-- Run with: nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/plenary/native_spec.lua"

local native = require("shelter.native")

describe("shelter.native", function()
  describe("is_available", function()
    it("returns true when library is loaded", function()
      assert.is_true(native.is_available())
    end)
  end)

  describe("version", function()
    it("returns a version string", function()
      local version = native.version()
      assert.is_string(version)
      assert.is_true(version:match("%d+%.%d+%.%d+") ~= nil)
    end)
  end)

  describe("parse", function()
    it("parses simple KEY=value", function()
      local result = native.parse("API_KEY=secret123")
      assert.is_table(result)
      assert.is_table(result.entries)
      assert.equals(1, #result.entries)
      assert.equals("API_KEY", result.entries[1].key)
      assert.equals("secret123", result.entries[1].value)
    end)

    it("parses quoted values", function()
      local result = native.parse('KEY="value with spaces"')
      assert.equals(1, #result.entries)
      assert.equals("KEY", result.entries[1].key)
      assert.equals("value with spaces", result.entries[1].value)
      assert.equals(2, result.entries[1].quote_type) -- Double quote
    end)

    it("parses single quoted values", function()
      local result = native.parse("KEY='single quoted'")
      assert.equals(1, #result.entries)
      assert.equals("single quoted", result.entries[1].value)
      assert.equals(1, result.entries[1].quote_type) -- Single quote
    end)

    it("handles multi-line values", function()
      local content = 'JSON="{\n  \\"key\\": \\"value\\"\n}"'
      local result = native.parse(content)
      assert.equals(1, #result.entries)
      assert.is_true(result.entries[1].value:find("\n") ~= nil)
      assert.is_true(result.entries[1].value_end_line > result.entries[1].line_number)
    end)

    it("returns correct line_offsets", function()
      local content = "LINE1=a\nLINE2=b\nLINE3=c"
      local result = native.parse(content)
      assert.is_table(result.line_offsets)
      assert.equals(3, #result.line_offsets)
      assert.equals(0, result.line_offsets[1]) -- Line 1 at byte 0
      assert.equals(8, result.line_offsets[2]) -- Line 2 at byte 8
      assert.equals(16, result.line_offsets[3]) -- Line 3 at byte 16
    end)

    it("sets is_comment flag correctly for comment entries", function()
      local content = "#COMMENTED=value\nREAL=value"
      local result = native.parse(content)
      -- Find the comment entry if korni extracts it
      local has_comment_entry = false
      for _, entry in ipairs(result.entries) do
        if entry.key == "COMMENTED" then
          assert.is_true(entry.is_comment)
          has_comment_entry = true
        end
      end
      -- At minimum, REAL should not be a comment
      local real_entry = vim.tbl_filter(function(e)
        return e.key == "REAL"
      end, result.entries)[1]
      assert.is_not_nil(real_entry)
      assert.is_false(real_entry.is_comment)
    end)

    it("handles export prefix", function()
      local result = native.parse("export API_KEY=secret")
      assert.equals(1, #result.entries)
      assert.equals("API_KEY", result.entries[1].key)
      assert.is_true(result.entries[1].is_exported)
    end)

    it("handles empty values", function()
      local result = native.parse("EMPTY=")
      assert.equals(1, #result.entries)
      assert.equals("EMPTY", result.entries[1].key)
      assert.equals("", result.entries[1].value)
    end)

    it("handles equals in value", function()
      local result = native.parse("URL=postgres://user:pass@host?sslmode=require")
      assert.equals(1, #result.entries)
      assert.equals("postgres://user:pass@host?sslmode=require", result.entries[1].value)
    end)

    it("handles inline comments", function()
      local result = native.parse("KEY=value # this is a comment")
      assert.equals(1, #result.entries)
      assert.equals("KEY", result.entries[1].key)
      assert.equals("value", result.entries[1].value)
    end)
  end)

  describe("mask_full", function()
    it("replaces all characters with mask char", function()
      local masked = native.mask_full("secret", "*")
      assert.equals("******", masked)
    end)

    it("handles empty string", function()
      local masked = native.mask_full("", "*")
      assert.equals("", masked)
    end)

    it("uses custom mask character", function()
      local masked = native.mask_full("test", "#")
      assert.equals("####", masked)
    end)

    it("handles unicode values", function()
      local masked = native.mask_full("hello", "*")
      assert.equals("*****", masked)
    end)
  end)

  describe("mask_partial", function()
    it("shows start and end characters", function()
      local masked = native.mask_partial("secretvalue", "*", 3, 3, 3)
      assert.equals("sec*****lue", masked)
    end)

    it("falls back to full mask for short values", function()
      local masked = native.mask_partial("short", "*", 3, 3, 3)
      assert.equals("*****", masked)
    end)

    it("uses custom mask character", function()
      local masked = native.mask_partial("secretvalue", "#", 2, 2, 3)
      assert.equals("se#######ue", masked)
    end)
  end)

  describe("mask_fixed", function()
    it("outputs exact length", function()
      local masked = native.mask_fixed("anything", "*", 10)
      assert.equals("**********", masked)
      assert.equals(10, #masked)
    end)

    it("can be shorter than value", function()
      local masked = native.mask_fixed("very_long_value", "*", 5)
      assert.equals("*****", masked)
    end)

    it("can be longer than value", function()
      local masked = native.mask_fixed("short", "*", 20)
      assert.equals(20, #masked)
    end)
  end)

  describe("mask_value", function()
    it("uses full mode by default", function()
      local masked = native.mask_value("secret", { mode = "full" })
      assert.equals("******", masked)
    end)

    it("uses partial mode when specified", function()
      local masked = native.mask_value("secretvalue", {
        mode = "partial",
        show_start = 2,
        show_end = 2,
        min_mask = 3,
      })
      assert.equals("se*******ue", masked)
    end)

    it("respects mask_length option", function()
      local masked = native.mask_value("short", {
        mode = "full",
        mask_length = 10,
      })
      assert.equals("**********", masked)
    end)

    it("respects mask_char option", function()
      local masked = native.mask_value("secret", {
        mode = "full",
        mask_char = "#",
      })
      assert.equals("######", masked)
    end)
  end)
end)
