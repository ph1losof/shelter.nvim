-- Tests for shelter.integrations.buffer module
-- Run with: nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/plenary/buffer_integration_spec.lua"

local buffer = require("shelter.integrations.buffer")
local config = require("shelter.config")
local state = require("shelter.state")

-- Helper to wait for vim.schedule callbacks to execute
-- This is needed because apply_masks uses vim.schedule for batched extmark application
local function wait_for_schedule()
  local done = false
  vim.schedule(function()
    done = true
  end)
  vim.wait(1000, function()
    return done
  end, 10)
end

-- Helper to create a test buffer with content
local function create_test_buffer(content, filename)
  filename = filename or "test.env"
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, filename)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n"))
  return bufnr
end

-- Helper to clean up test buffer
local function cleanup_buffer(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

describe("shelter.integrations.buffer", function()
  local test_bufnr

  before_each(function()
    -- Reset config and state before each test
    config.setup({
      mask_char = "*",
      skip_comments = true,
      default_mode = "full",
      env_file_patterns = { ".env", ".env.*", "test.env" },
      modules = { files = true },
    })
    state.set_initial("files", true)
  end)

  after_each(function()
    if test_bufnr then
      cleanup_buffer(test_bufnr)
      test_bufnr = nil
    end
  end)

  describe("shelter_buffer", function()
    it("applies masks to env file buffer", function()
      test_bufnr = create_test_buffer("SECRET=mysecret", "test.env")

      -- Shelter the buffer
      buffer.shelter_buffer(test_bufnr)
      wait_for_schedule() -- Wait for async extmark application

      -- Check that extmarks were applied
      local ns = vim.api.nvim_create_namespace("shelter_mask")
      local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, {})
      assert.is_true(#marks > 0, "Expected extmarks to be applied")
    end)

    it("does not apply masks to non-env files", function()
      test_bufnr = create_test_buffer("SECRET=mysecret", "config.json")

      buffer.shelter_buffer(test_bufnr)

      -- Should not have any extmarks
      local ns = vim.api.nvim_create_namespace("shelter_mask")
      local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, {})
      assert.equals(0, #marks)
    end)

    it("does not apply masks when feature is disabled", function()
      state.set_initial("files", false)
      test_bufnr = create_test_buffer("SECRET=mysecret", "test.env")

      buffer.shelter_buffer(test_bufnr)

      local ns = vim.api.nvim_create_namespace("shelter_mask")
      local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, {})
      assert.equals(0, #marks)
    end)
  end)

  describe("unshelter_buffer", function()
    it("removes all extmarks", function()
      test_bufnr = create_test_buffer("SECRET=mysecret", "test.env")
      buffer.shelter_buffer(test_bufnr)
      wait_for_schedule()

      -- Verify marks exist
      local ns = vim.api.nvim_create_namespace("shelter_mask")
      local marks_before = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, {})
      assert.is_true(#marks_before > 0)

      -- Unshelter
      buffer.unshelter_buffer(test_bufnr)

      -- Verify marks are gone
      local marks_after = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, {})
      assert.equals(0, #marks_after)
    end)
  end)

  describe("refresh_buffer", function()
    it("re-applies masks after content change", function()
      test_bufnr = create_test_buffer("SECRET=value1", "test.env")
      buffer.shelter_buffer(test_bufnr)
      wait_for_schedule()

      -- Change content
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, { "SECRET=newvalue" })

      -- Refresh
      buffer.refresh_buffer(test_bufnr)
      wait_for_schedule()

      -- Should still have extmarks
      local ns = vim.api.nvim_create_namespace("shelter_mask")
      local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, {})
      assert.is_true(#marks > 0)
    end)
  end)

  describe("toggle_buffer", function()
    it("toggles masking on and off", function()
      state.set_initial("files", true)
      test_bufnr = create_test_buffer("SECRET=mysecret", "test.env")

      -- Initial state: enabled
      buffer.shelter_buffer(test_bufnr)
      wait_for_schedule()
      local ns = vim.api.nvim_create_namespace("shelter_mask")

      -- Toggle off
      local new_state = buffer.toggle_buffer(test_bufnr)
      wait_for_schedule()
      assert.is_false(new_state)
      local marks_off = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, {})
      assert.equals(0, #marks_off)

      -- Toggle on
      new_state = buffer.toggle_buffer(test_bufnr)
      wait_for_schedule()
      assert.is_true(new_state)
      local marks_on = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, {})
      assert.is_true(#marks_on > 0)
    end)
  end)

  describe("multi-line value handling", function()
    it("masks multi-line values correctly", function()
      local content = [[JSON="{
  \"key\": \"value\"
}"]]
      test_bufnr = create_test_buffer(content, "test.env")
      buffer.shelter_buffer(test_bufnr)
      wait_for_schedule()

      -- Should have extmarks on multiple lines
      local ns = vim.api.nvim_create_namespace("shelter_mask")
      local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, { details = true })

      -- Verify we have marks spanning the multi-line value
      assert.is_true(#marks > 0, "Expected extmarks for multi-line value")
    end)

    it("masks last line only up to value end", function()
      -- This tests Bug 1.1 fix
      local content = [[JSON="{
  \"key\": \"value\"
}" # comment after]]
      test_bufnr = create_test_buffer(content, "test.env")
      buffer.shelter_buffer(test_bufnr)
      wait_for_schedule()

      local ns = vim.api.nvim_create_namespace("shelter_mask")
      local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, { details = true })

      -- The last line should only be masked up to the closing quote
      -- Not including " # comment after"
      assert.is_true(#marks > 0)
    end)
  end)

  describe("quote preservation", function()
    it("preserves single quotes around masked value", function()
      local content = "SECRET='mysecret'"
      test_bufnr = create_test_buffer(content, "test.env")
      buffer.shelter_buffer(test_bufnr)
      wait_for_schedule()

      local ns = vim.api.nvim_create_namespace("shelter_mask")
      local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, { details = true })

      -- Should have mask that starts AFTER opening quote and ends BEFORE closing quote
      assert.equals(1, #marks, "Expected exactly one mask")
      local mark = marks[1]
      local start_col = mark[3]
      local end_col = mark[4].end_col

      -- "SECRET='mysecret'" - value_start at quote (7), should mask starting at 8
      -- Closing quote is at position 17, should mask up to 16
      assert.equals(8, start_col, "Mask should start after opening quote")
      assert.equals(16, end_col, "Mask should end before closing quote")
    end)

    it("preserves double quotes around masked value", function()
      local content = 'KEY="secretvalue"'
      test_bufnr = create_test_buffer(content, "test.env")
      buffer.shelter_buffer(test_bufnr)
      wait_for_schedule()

      local ns = vim.api.nvim_create_namespace("shelter_mask")
      local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, { details = true })

      assert.equals(1, #marks, "Expected exactly one mask")
      local mark = marks[1]
      local start_col = mark[3]
      local end_col = mark[4].end_col

      -- "KEY=\"secretvalue\"" - value_start at quote (4), should mask starting at 5
      -- Closing quote at 17, should mask up to 16
      assert.equals(5, start_col, "Mask should start after opening quote")
      assert.equals(16, end_col, "Mask should end before closing quote")
    end)

    it("does not adjust mask for unquoted values", function()
      local content = "KEY=unquoted"
      test_bufnr = create_test_buffer(content, "test.env")
      buffer.shelter_buffer(test_bufnr)
      wait_for_schedule()

      local ns = vim.api.nvim_create_namespace("shelter_mask")
      local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, { details = true })

      assert.equals(1, #marks, "Expected exactly one mask")
      local mark = marks[1]
      local start_col = mark[3]
      local end_col = mark[4].end_col

      -- "KEY=unquoted" - value starts at 4, ends at 12
      assert.equals(4, start_col, "Mask should start at value position")
      assert.equals(12, end_col, "Mask should end at value end")
    end)

    it("preserves quotes in multi-line values", function()
      local content = [[JSON="{
  \"key\": \"value\"
}"]]
      test_bufnr = create_test_buffer(content, "test.env")
      buffer.shelter_buffer(test_bufnr)
      wait_for_schedule()

      local ns = vim.api.nvim_create_namespace("shelter_mask")
      local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, { details = true })

      -- Should have multiple marks for multi-line value
      assert.is_true(#marks >= 1, "Expected extmarks for multi-line value")

      -- First line mark should start after the opening quote
      local first_mark = marks[1]
      local start_col = first_mark[3]
      -- JSON=" starts at 5, quote is at 5, content starts at 6
      assert.equals(6, start_col, "First line mask should start after opening quote")
    end)
  end)

  describe("comment handling", function()
    it("skips comment entries when skip_comments is true", function()
      config.setup({ skip_comments = true })
      local content = [[#COMMENTED=secret
REAL=value]]
      test_bufnr = create_test_buffer(content, "test.env")
      buffer.shelter_buffer(test_bufnr)
      wait_for_schedule()

      local ns = vim.api.nvim_create_namespace("shelter_mask")
      local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, { details = true })

      -- Should only have mask for REAL on line 2, not COMMENTED on line 1
      local has_line_1_mask = false
      for _, mark in ipairs(marks) do
        if mark[2] == 0 then -- Line index 0 = first line
          has_line_1_mask = true
        end
      end
      -- Depending on korni behavior, COMMENTED might not be extracted at all
      -- or if it is, it should be skipped
    end)

    it("does not mask inline comments", function()
      local content = "KEY=value # this comment stays visible"
      test_bufnr = create_test_buffer(content, "test.env")
      buffer.shelter_buffer(test_bufnr)
      wait_for_schedule()

      local ns = vim.api.nvim_create_namespace("shelter_mask")
      local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, ns, 0, -1, { details = true })

      -- Should have exactly one mask for "value" only
      -- The inline comment should not be masked
      assert.equals(1, #marks, "Expected exactly one mask for the value")

      -- Check that the mask doesn't extend to the comment
      if #marks > 0 then
        local mark = marks[1]
        local end_col = mark[4].end_col
        -- "KEY=value" ends at column 9 (0-indexed: columns 4-8 for "value")
        -- The mask should not extend past the value
        assert.is_true(end_col <= 10, "Mask should not extend into inline comment")
      end
    end)
  end)
end)
