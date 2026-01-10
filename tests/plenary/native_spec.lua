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

  -- Note: Masking functions (mask_full, mask_partial, mask_fixed, mask_value)
  -- have been moved to pure Lua for better performance. See modes_spec.lua
  -- and masking_engine_spec.lua for masking tests.
end)
