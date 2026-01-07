-- Quick test script for native library
-- Run with: nvim --headless -u NONE -l tests/test_native.lua

vim.opt.runtimepath:append('.')

local ok, native = pcall(require, 'shelter.native')
if not ok then
  print('ERROR: Could not load native library: ' .. tostring(native))
  vim.cmd('cq 1')
end

print('Native library version: ' .. native.version())

-- Test quote_type parsing
local test_cases = {
  { input = "KEY='secret'", expected_quote_type = 1, desc = "single quoted" },
  { input = 'KEY="secret"', expected_quote_type = 2, desc = "double quoted" },
  { input = "KEY=secret", expected_quote_type = 0, desc = "unquoted" },
}

local all_passed = true
for _, tc in ipairs(test_cases) do
  local result = native.parse(tc.input)
  local entry = result.entries[1]
  if entry.quote_type ~= tc.expected_quote_type then
    print(string.format('FAIL: %s - expected quote_type=%d, got %d',
      tc.desc, tc.expected_quote_type, entry.quote_type))
    all_passed = false
  else
    print(string.format('PASS: %s - quote_type=%d', tc.desc, entry.quote_type))
  end
end

-- Test value_start/value_end span
local span_test = native.parse("KEY='secret'")
local entry = span_test.entries[1]
print(string.format('Span test: value_start=%d, value_end=%d, value="%s"',
  entry.value_start, entry.value_end, entry.value))

-- For KEY='secret':
-- K E Y = ' s e c r e t  '
-- 0 1 2 3 4 5 6 7 8 9 10 11
-- value_start should be 4 (opening quote position)
-- value_end should be 12 (past closing quote)
if entry.value_start == 4 and entry.value_end == 12 then
  print('PASS: value span includes quotes')
else
  print(string.format('FAIL: expected value_start=4, value_end=12, got start=%d, end=%d',
    entry.value_start, entry.value_end))
  all_passed = false
end

if all_passed then
  print('\nAll native tests passed!')
else
  print('\nSome tests failed!')
  vim.cmd('cq 1')
end

vim.cmd('qa!')
