-- Performance benchmark: shelter.nvim vs cloak.nvim
-- Run with: nvim --headless -u benchmarks/minimal_init.lua -l benchmarks/benchmark.lua
--
-- Output: JSON file (benchmark_results.json) with timing results
--
-- Benchmarks:
-- 1. Parsing: Raw parsing + mask generation (no buffer)
-- 2. Preview: Masking a preview buffer (Telescope scenario)
-- 3. Edit: Re-masking after text change (typing scenario)

local ITERATIONS = 1000
local SIZES = { 10, 50, 100, 500 }
local OUTPUT_FILE = "benchmark_results.json"

-- High resolution timer
local hrtime = vim.uv and vim.uv.hrtime or vim.loop.hrtime

---Generate synthetic .env content with N lines
---@param num_lines number
---@return string
local function generate_env_content(num_lines)
	local lines = {}
	for i = 1, num_lines do
		-- Realistic env line: VAR_0001=secret_value_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
		lines[i] = string.format("VAR_%04d=secret_value_%s", i, string.rep("x", 32))
	end
	return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- PARSING BENCHMARKS (raw engine performance)
--------------------------------------------------------------------------------

---Benchmark shelter.nvim masking engine (parsing only)
---@param content string
---@param iterations number
---@return number Average time in milliseconds
local function benchmark_shelter_parse(content, iterations)
	local engine = require("shelter.masking.engine")

	-- Warmup run (not timed)
	engine.clear_caches()
	engine.generate_masks(content, "test.env")

	-- Timed runs
	local total_time = 0
	for _ = 1, iterations do
		engine.clear_caches() -- Clear cache for fair comparison
		local start = hrtime()
		engine.generate_masks(content, "test.env")
		local elapsed = hrtime() - start
		total_time = total_time + elapsed
	end

	return (total_time / iterations) / 1e6 -- Convert ns to ms
end

---Benchmark cloak.nvim masking (parsing equivalent)
---@param content string
---@param iterations number
---@return number|nil Average time in milliseconds, or nil if cloak not available
local function benchmark_cloak_parse(content, iterations)
	local ok, cloak = pcall(require, "cloak")
	if not ok then
		return nil
	end

	-- Create a scratch buffer with env content
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n"))
	vim.api.nvim_set_current_buf(bufnr)
	vim.bo[bufnr].filetype = "dotenv"

	-- Get the pattern config cloak uses
	local pattern = cloak.opts.patterns[1]

	-- Warmup run (not timed)
	cloak.cloak(pattern)
	cloak.uncloak()

	-- Timed runs
	local total_time = 0
	for _ = 1, iterations do
		cloak.uncloak() -- Clear previous masking
		local start = hrtime()
		cloak.cloak(pattern)
		local elapsed = hrtime() - start
		total_time = total_time + elapsed
	end

	-- Cleanup
	vim.api.nvim_buf_delete(bufnr, { force = true })

	return (total_time / iterations) / 1e6 -- Convert ns to ms
end

--------------------------------------------------------------------------------
-- PREVIEW BENCHMARKS (Telescope preview scenario)
--------------------------------------------------------------------------------

---Benchmark shelter.nvim preview buffer masking
---@param content string
---@param iterations number
---@return number Average time in milliseconds
local function benchmark_shelter_preview(content, iterations)
	local buffer_mod = require("shelter.integrations.buffer")
	local extmarks = require("shelter.integrations.buffer.extmarks")

	-- Create a scratch buffer (simulates Telescope/FZF/Snacks preview buffer)
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n"))

	-- Warmup
	buffer_mod.shelter_preview_buffer(bufnr, "test.env", "dotenv")

	local total_time = 0
	for _ = 1, iterations do
		-- Clear extmarks before each run (simulates new preview)
		extmarks.clear(bufnr)
		local start = hrtime()
		buffer_mod.shelter_preview_buffer(bufnr, "test.env", "dotenv")
		local elapsed = hrtime() - start
		total_time = total_time + elapsed
	end

	vim.api.nvim_buf_delete(bufnr, { force = true })
	return (total_time / iterations) / 1e6
end

---Benchmark cloak.nvim preview (same as parse, cloak doesn't distinguish)
---@param content string
---@param iterations number
---@return number|nil Average time in milliseconds
local function benchmark_cloak_preview(content, iterations)
	-- cloak.nvim uses the same mechanism for preview
	return benchmark_cloak_parse(content, iterations)
end

--------------------------------------------------------------------------------
-- EDIT BENCHMARKS (re-masking after text change)
--------------------------------------------------------------------------------

---Benchmark shelter.nvim re-masking after edit
---@param content string
---@param iterations number
---@return number Average time in milliseconds
local function benchmark_shelter_edit(content, iterations)
	local buffer_mod = require("shelter.integrations.buffer")
	local extmarks = require("shelter.integrations.buffer.extmarks")

	-- Create buffer and set up
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n"))
	vim.bo[bufnr].filetype = "dotenv"
	vim.api.nvim_set_current_buf(bufnr)

	-- Initial mask
	buffer_mod.shelter_buffer(bufnr, true)

	local total_time = 0
	for i = 1, iterations do
		-- Simulate edit (modify first line - like typing)
		vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { "MODIFIED_" .. i .. "=new_secret_value_xxxxx" })

		-- Clear extmarks (simulates what happens on re-mask)
		extmarks.clear(bufnr)

		local start = hrtime()
		buffer_mod.shelter_buffer(bufnr, true) -- sync=true
		local elapsed = hrtime() - start
		total_time = total_time + elapsed
	end

	vim.api.nvim_buf_delete(bufnr, { force = true })
	return (total_time / iterations) / 1e6
end

---Benchmark cloak.nvim re-masking after edit
---@param content string
---@param iterations number
---@return number|nil Average time in milliseconds
local function benchmark_cloak_edit(content, iterations)
	local ok, cloak = pcall(require, "cloak")
	if not ok then
		return nil
	end

	-- Create buffer
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n"))
	vim.api.nvim_set_current_buf(bufnr)
	vim.bo[bufnr].filetype = "dotenv"

	local pattern = cloak.opts.patterns[1]

	-- Initial mask
	cloak.cloak(pattern)

	local total_time = 0
	for i = 1, iterations do
		-- Simulate edit
		vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { "MODIFIED_" .. i .. "=new_secret_value_xxxxx" })

		-- cloak re-masks on TextChanged (uncloak + cloak)
		cloak.uncloak()
		local start = hrtime()
		cloak.cloak(pattern)
		local elapsed = hrtime() - start
		total_time = total_time + elapsed
	end

	vim.api.nvim_buf_delete(bufnr, { force = true })
	return (total_time / iterations) / 1e6
end

--------------------------------------------------------------------------------
-- MAIN RUNNER
--------------------------------------------------------------------------------

---Round to 3 decimal places
---@param n number
---@return number
local function round3(n)
	return math.floor(n * 1000) / 1000
end

---Main benchmark runner
local function run_benchmarks()
	local results = {
		metadata = {
			iterations = ITERATIONS,
			timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
			neovim_version = vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch,
		},
		benchmarks = {},
	}

	for _, size in ipairs(SIZES) do
		local content = generate_env_content(size)

		print(string.format("\n=== Benchmarking %d lines ===", size))

		-- Parsing benchmarks
		local shelter_parse = benchmark_shelter_parse(content, ITERATIONS)
		local cloak_parse = benchmark_cloak_parse(content, ITERATIONS)
		print(
			string.format(
				"  Parse:   shelter=%.3fms, cloak=%s",
				shelter_parse,
				cloak_parse and string.format("%.3fms", cloak_parse) or "N/A"
			)
		)

		-- Preview benchmarks
		local shelter_preview = benchmark_shelter_preview(content, ITERATIONS)
		local cloak_preview = benchmark_cloak_preview(content, ITERATIONS)
		print(
			string.format(
				"  Preview: shelter=%.3fms, cloak=%s",
				shelter_preview,
				cloak_preview and string.format("%.3fms", cloak_preview) or "N/A"
			)
		)

		-- Edit benchmarks
		local shelter_edit = benchmark_shelter_edit(content, ITERATIONS)
		local cloak_edit = benchmark_cloak_edit(content, ITERATIONS)
		print(
			string.format(
				"  Edit:    shelter=%.3fms, cloak=%s",
				shelter_edit,
				cloak_edit and string.format("%.3fms", cloak_edit) or "N/A"
			)
		)

		results.benchmarks[tostring(size)] = {
			lines = size,
			-- Parsing (raw engine)
			shelter_parse_ms = round3(shelter_parse),
			cloak_parse_ms = cloak_parse and round3(cloak_parse) or nil,
			-- Preview (Telescope/FZF)
			shelter_preview_ms = round3(shelter_preview),
			cloak_preview_ms = cloak_preview and round3(cloak_preview) or nil,
			-- Edit (re-masking)
			shelter_edit_ms = round3(shelter_edit),
			cloak_edit_ms = cloak_edit and round3(cloak_edit) or nil,
		}
	end

	-- Write JSON to file
	local json = vim.json.encode(results)
	local f = io.open(OUTPUT_FILE, "w")
	if f then
		f:write(json)
		f:close()
		print("\nResults written to " .. OUTPUT_FILE)
	else
		print("\nERROR: Could not write to " .. OUTPUT_FILE)
	end
end

-- Run and exit
run_benchmarks()
vim.cmd("qa!")
