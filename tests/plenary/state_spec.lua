-- Tests for shelter.state module
-- Run with: nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/plenary/state_spec.lua"

local state = require("shelter.state")

describe("shelter.state", function()
  before_each(function()
    -- Reset state before each test
    state.reset_revealed_lines()
    state.set_initial("files", true)
    state.set_initial("peek", false)
  end)

  describe("is_enabled", function()
    it("returns initial state for feature", function()
      state.set_initial("files", true)
      assert.is_true(state.is_enabled("files"))

      state.set_initial("peek", false)
      assert.is_false(state.is_enabled("peek"))
    end)

    it("returns false for unknown features", function()
      assert.is_false(state.is_enabled("unknown_feature"))
    end)
  end)

  describe("set_initial", function()
    it("sets initial state for feature", function()
      state.set_initial("custom", true)
      assert.is_true(state.is_enabled("custom"))

      state.set_initial("custom", false)
      assert.is_false(state.is_enabled("custom"))
    end)
  end)

  describe("toggle", function()
    it("toggles feature state", function()
      state.set_initial("files", true)
      assert.is_true(state.is_enabled("files"))

      local new_state = state.toggle("files")
      assert.is_false(new_state)
      assert.is_false(state.is_enabled("files"))

      new_state = state.toggle("files")
      assert.is_true(new_state)
      assert.is_true(state.is_enabled("files"))
    end)

    it("returns new state", function()
      state.set_initial("files", true)
      local result = state.toggle("files")
      assert.is_false(result)

      result = state.toggle("files")
      assert.is_true(result)
    end)
  end)

  describe("reveal_line and is_line_revealed", function()
    it("reveals a specific line", function()
      assert.is_false(state.is_line_revealed(5))

      state.reveal_line(5)
      assert.is_true(state.is_line_revealed(5))
    end)

    it("handles multiple revealed lines", function()
      state.reveal_line(1)
      state.reveal_line(5)
      state.reveal_line(10)

      assert.is_true(state.is_line_revealed(1))
      assert.is_true(state.is_line_revealed(5))
      assert.is_true(state.is_line_revealed(10))
      assert.is_false(state.is_line_revealed(2))
    end)
  end)

  describe("hide_line", function()
    it("hides a previously revealed line", function()
      state.reveal_line(5)
      assert.is_true(state.is_line_revealed(5))

      state.hide_line(5)
      assert.is_false(state.is_line_revealed(5))
    end)

    it("does nothing for unrevealed lines", function()
      assert.is_false(state.is_line_revealed(5))
      state.hide_line(5) -- Should not error
      assert.is_false(state.is_line_revealed(5))
    end)
  end)

  describe("reset_revealed_lines", function()
    it("clears all revealed lines", function()
      state.reveal_line(1)
      state.reveal_line(5)
      state.reveal_line(10)

      state.reset_revealed_lines()

      assert.is_false(state.is_line_revealed(1))
      assert.is_false(state.is_line_revealed(5))
      assert.is_false(state.is_line_revealed(10))
    end)
  end)

  describe("get_revealed_lines", function()
    it("returns list of revealed lines", function()
      state.reveal_line(1)
      state.reveal_line(5)
      state.reveal_line(10)

      local revealed = state.get_revealed_lines()
      assert.is_table(revealed)

      -- Check that all revealed lines are in the list
      local found = { [1] = false, [5] = false, [10] = false }
      for _, line in ipairs(revealed) do
        found[line] = true
      end

      assert.is_true(found[1])
      assert.is_true(found[5])
      assert.is_true(found[10])
    end)

    it("returns empty table when no lines revealed", function()
      state.reset_revealed_lines()
      local revealed = state.get_revealed_lines()
      assert.is_table(revealed)
      assert.equals(0, #revealed)
    end)
  end)
end)
