-- Update README.md with benchmark results
-- Run with: nvim --headless -u benchmarks/minimal_init.lua -l benchmarks/update_readme.lua
--
-- Reads benchmark_results.json and updates the Performance Benchmarks section in README.md

local RESULTS_FILE = "benchmark_results.json"
local README_FILE = "README.md"
local BENCHMARK_START_MARKER = "<!-- BENCHMARK_START -->"
local BENCHMARK_END_MARKER = "<!-- BENCHMARK_END -->"

---Read file contents
---@param path string
---@return string|nil
local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

---Write file contents
---@param path string
---@param content string
---@return boolean
local function write_file(path, content)
  local f = io.open(path, "w")
  if not f then
    return false
  end
  f:write(content)
  f:close()
  return true
end

---Calculate difference string
---@param shelter_ms number
---@param cloak_ms number|nil
---@return string
local function calc_diff(shelter_ms, cloak_ms)
  if not cloak_ms or shelter_ms <= 0 then
    return ""
  end
  local ratio = cloak_ms / shelter_ms
  if ratio > 1.05 then
    return string.format("%.1fx faster", ratio)
  elseif ratio < 0.95 then
    return string.format("%.1fx slower", 1 / ratio)
  else
    return "~same"
  end
end

---Format a benchmark row
---@param lines number
---@param shelter_ms number
---@param cloak_ms number|nil
---@return string
local function format_row(lines, shelter_ms, cloak_ms)
  local shelter = string.format("%.2f ms", shelter_ms)
  local cloak = cloak_ms and string.format("%.2f ms", cloak_ms) or "N/A"
  local diff = calc_diff(shelter_ms, cloak_ms)
  return string.format("| %d    | %s      | %s      | %s |", lines, shelter, cloak, diff)
end

---Generate a single benchmark table
---@param title string
---@param results table
---@param sizes number[]
---@param shelter_key string
---@param cloak_key string
---@return string[]
local function generate_table(title, results, sizes, shelter_key, cloak_key)
  local lines = {
    "#### " .. title,
    "",
    "| Lines | shelter.nvim | cloak.nvim | Difference |",
    "|-------|--------------|------------|------------|",
  }

  for _, size in ipairs(sizes) do
    local data = results.benchmarks[tostring(size)]
    local shelter_ms = data[shelter_key]
    local cloak_ms = data[cloak_key]
    table.insert(lines, format_row(size, shelter_ms, cloak_ms))
  end

  return lines
end

---Generate the complete benchmark section markdown
---@param results table
---@return string
local function generate_benchmark_section(results)
  local output = {
    BENCHMARK_START_MARKER,
    "### Performance Benchmarks",
    "",
    string.format("Measured on GitHub Actions (Ubuntu, averaged over %d iterations):", results.metadata.iterations),
    "",
  }

  -- Sort sizes
  local sizes = {}
  for size in pairs(results.benchmarks) do
    table.insert(sizes, tonumber(size))
  end
  table.sort(sizes)

  -- Parsing Performance table
  local parse_table = generate_table(
    "Parsing Performance",
    results, sizes,
    "shelter_parse_ms", "cloak_parse_ms"
  )
  for _, line in ipairs(parse_table) do
    table.insert(output, line)
  end
  table.insert(output, "")

  -- Preview Performance table
  local preview_table = generate_table(
    "Preview Performance (Telescope)",
    results, sizes,
    "shelter_preview_ms", "cloak_preview_ms"
  )
  for _, line in ipairs(preview_table) do
    table.insert(output, line)
  end
  table.insert(output, "")

  -- Edit Re-masking Performance table
  local edit_table = generate_table(
    "Edit Re-masking Performance",
    results, sizes,
    "shelter_edit_ms", "cloak_edit_ms"
  )
  for _, line in ipairs(edit_table) do
    table.insert(output, line)
  end
  table.insert(output, "")

  table.insert(output, string.format("*Last updated: %s*", results.metadata.timestamp:sub(1, 10)))
  table.insert(output, BENCHMARK_END_MARKER)

  return table.concat(output, "\n")
end

---Main function
local function main()
  -- Read benchmark results
  local results_json = read_file(RESULTS_FILE)
  if not results_json then
    io.stderr:write("Error: Could not read " .. RESULTS_FILE .. "\n")
    vim.cmd("cq 1")
    return
  end

  local ok, results = pcall(vim.json.decode, results_json)
  if not ok then
    io.stderr:write("Error: Invalid JSON in " .. RESULTS_FILE .. "\n")
    vim.cmd("cq 1")
    return
  end

  -- Read README
  local readme = read_file(README_FILE)
  if not readme then
    io.stderr:write("Error: Could not read " .. README_FILE .. "\n")
    vim.cmd("cq 1")
    return
  end

  -- Generate new benchmark section
  local new_section = generate_benchmark_section(results)

  -- Replace or append benchmark section
  local start_pos = readme:find(BENCHMARK_START_MARKER, 1, true)
  local end_pos = readme:find(BENCHMARK_END_MARKER, 1, true)

  local new_readme
  if start_pos and end_pos then
    -- Replace existing section
    new_readme = readme:sub(1, start_pos - 1) .. new_section .. readme:sub(end_pos + #BENCHMARK_END_MARKER)
  else
    -- Find the end of the comparison table section and insert after it
    local insert_after = readme:find("### When to Choose cloak.nvim", 1, true)
    if insert_after then
      local section_end = readme:find("\n## ", insert_after)
      if section_end then
        new_readme = readme:sub(1, section_end - 1) .. "\n\n" .. new_section .. "\n" .. readme:sub(section_end)
      else
        new_readme = readme .. "\n\n" .. new_section
      end
    else
      new_readme = readme .. "\n\n" .. new_section
    end
  end

  -- Write updated README
  if not write_file(README_FILE, new_readme) then
    io.stderr:write("Error: Could not write " .. README_FILE .. "\n")
    vim.cmd("cq 1")
    return
  end

  io.stderr:write("Successfully updated " .. README_FILE .. " with benchmark results\n")
  vim.cmd("qa!")
end

main()
