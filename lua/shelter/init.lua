---@class Shelter
---shelter.nvim - EDF-compliant dotenv file masking for Neovim
---
---@usage
---```lua
---require("shelter").setup({
---  mask_char = "*",
---  default_mode = "full",
---  modules = {
---    files = true,  -- or { shelter_on_leave = true, disable_cmp = true }
---    telescope_previewer = false,
---    fzf_previewer = false,
---    snacks_previewer = false,
---  },
---})
---```
local M = {}

local config = require("shelter.config")
local state = require("shelter.state")

---@type boolean
local is_setup = false

---Setup shelter.nvim
---@param opts? ShelterUserConfig
function M.setup(opts)
  -- Configure
  config.setup(opts)

  -- Check if native library is available
  local native_ok, native = pcall(require, "shelter.native")
  if not native_ok then
    vim.notify(
      "shelter.nvim: Native library not found. Run :ShelterBuild to install.",
      vim.log.levels.ERROR
    )
    return
  end

  if not native.is_available() then
    vim.notify(
      "shelter.nvim: Failed to load native library. Run :ShelterBuild to reinstall.",
      vim.log.levels.ERROR
    )
    return
  end

  -- Setup integrations
  local cfg = config.get()
  local integrations = require("shelter.integrations")
  integrations.setup_all(cfg.modules)

  -- Create user commands
  M._setup_commands()

  is_setup = true
end

-- Module name aliases for convenience
local MODULE_ALIASES = {
  buffer = "files",
  telescope = "telescope_previewer",
  fzf = "fzf_previewer",
  snacks = "snacks_previewer",
}

-- Valid module names
local VALID_MODULES = {
  "files",
  "telescope_previewer",
  "fzf_previewer",
  "snacks_previewer",
}

---Normalize module name (handle aliases)
---@param name string|nil
---@return string|nil
local function normalize_module(name)
  if not name then
    return nil
  end
  return MODULE_ALIASES[name] or name
end

---Check if module name is valid
---@param name string
---@return boolean
local function is_valid_module(name)
  return vim.tbl_contains(VALID_MODULES, name)
end

---Handle toggle command
---@param target string|nil Module name or nil for all
function M._handle_toggle(target)
  local module = normalize_module(target)

  if module then
    -- Toggle specific module
    if not is_valid_module(module) then
      vim.notify("shelter.nvim: Unknown module: " .. target, vim.log.levels.ERROR)
      return
    end
    local enabled = state.toggle(module)
    vim.notify(
      string.format("shelter.nvim: %s %s", module, enabled and "enabled" or "disabled"),
      vim.log.levels.INFO
    )
  else
    -- Toggle all user-enabled modules
    local enabled = state.toggle_all_user_modules()
    vim.notify(
      string.format("shelter.nvim: All modules %s", enabled and "enabled" or "disabled"),
      vim.log.levels.INFO
    )
  end
end

---Handle enable command
---@param target string|nil Module name or nil for all
function M._handle_enable(target)
  local module = normalize_module(target)

  if module then
    -- Enable specific module
    if not is_valid_module(module) then
      vim.notify("shelter.nvim: Unknown module: " .. target, vim.log.levels.ERROR)
      return
    end
    state.set_enabled(module, true)
    vim.notify("shelter.nvim: " .. module .. " enabled", vim.log.levels.INFO)
  else
    -- Enable all user modules
    state.enable_all_user_modules()
    vim.notify("shelter.nvim: All modules enabled", vim.log.levels.INFO)
  end
end

---Handle disable command
---@param target string|nil Module name or nil for all
function M._handle_disable(target)
  local module = normalize_module(target)

  if module then
    -- Disable specific module
    if not is_valid_module(module) then
      vim.notify("shelter.nvim: Unknown module: " .. target, vim.log.levels.ERROR)
      return
    end
    state.set_enabled(module, false)
    vim.notify("shelter.nvim: " .. module .. " disabled", vim.log.levels.INFO)
  else
    -- Disable all modules
    state.disable_all_user_modules()
    vim.notify("shelter.nvim: All modules disabled", vim.log.levels.INFO)
  end
end

---Create user commands
function M._setup_commands()
  -- :Shelter <subcommand> [args]
  vim.api.nvim_create_user_command("Shelter", function(opts)
    local args = vim.split(opts.args, "%s+", { trimempty = true })
    local subcommand = args[1]
    local target = args[2]

    if subcommand == "toggle" then
      M._handle_toggle(target)
    elseif subcommand == "enable" then
      M._handle_enable(target)
    elseif subcommand == "disable" then
      M._handle_disable(target)
    elseif subcommand == "peek" then
      M.peek()
    elseif subcommand == "build" then
      M.build()
    elseif subcommand == "info" then
      M.info()
    else
      vim.notify(
        "shelter.nvim: Unknown subcommand. Use: toggle, enable, disable, peek, build, info",
        vim.log.levels.ERROR
      )
    end
  end, {
    nargs = "+",
    complete = function(arglead, cmdline, _)
      local args = vim.split(cmdline, "%s+", { trimempty = true })

      if #args <= 2 then
        -- Complete subcommand
        local subcommands = { "toggle", "enable", "disable", "peek", "build", "info" }
        return vim.tbl_filter(function(cmd)
          return cmd:find(arglead, 1, true) == 1
        end, subcommands)
      elseif #args == 3 and vim.tbl_contains({ "toggle", "enable", "disable" }, args[2]) then
        -- Complete module name
        local modules = { "files", "telescope_previewer", "fzf_previewer", "snacks_previewer" }
        return vim.tbl_filter(function(mod)
          return mod:find(arglead, 1, true) == 1
        end, modules)
      end

      return {}
    end,
    desc = "Shelter command: toggle, enable, disable, peek, build, info",
  })
end

---Build or download the native library
function M.build()
  vim.notify("shelter.nvim: Building native library...", vim.log.levels.INFO)

  -- Get plugin directory
  local source = debug.getinfo(1, "S").source:sub(2)
  local plugin_dir = vim.fn.fnamemodify(source, ":h:h:h")
  local crate_dir = plugin_dir .. "/crates/shelter-core"

  -- Try to build with cargo
  local cmd = string.format("cd %s && cargo build --release", vim.fn.shellescape(crate_dir))

  vim.fn.jobstart(cmd, {
    on_exit = function(_, code)
      if code == 0 then
        -- Copy library to lib directory
        local uname = vim.uv.os_uname()
        local lib_name = uname.sysname == "Darwin" and "libshelter_core.dylib"
          or uname.sysname == "Windows" and "shelter_core.dll"
          or "libshelter_core.so"

        local src = plugin_dir .. "/../../target/release/" .. lib_name
        local dst = plugin_dir .. "/lib/" .. lib_name

        vim.fn.mkdir(plugin_dir .. "/lib", "p")
        vim.fn.system({ "cp", src, dst })

        vim.schedule(function()
          vim.notify("shelter.nvim: Build successful!", vim.log.levels.INFO)
        end)
      else
        vim.schedule(function()
          vim.notify("shelter.nvim: Build failed. Make sure Rust is installed.", vim.log.levels.ERROR)
        end)
      end
    end,
    stdout_buffered = true,
    stderr_buffered = true,
  })
end

---Show plugin info
function M.info()
  local info = { "shelter.nvim" }

  -- Native library status
  local native_ok, native = pcall(require, "shelter.native")
  if native_ok and native.is_available() then
    table.insert(info, string.format("  Native library: v%s", native.version()))
  else
    table.insert(info, "  Native library: NOT FOUND")
  end

  -- Feature status
  table.insert(info, "  Features:")
  table.insert(info, string.format("    files: %s", state.is_enabled("files") and "enabled" or "disabled"))
  table.insert(info, string.format("    telescope_previewer: %s", state.is_enabled("telescope_previewer") and "enabled" or "disabled"))
  table.insert(info, string.format("    fzf_previewer: %s", state.is_enabled("fzf_previewer") and "enabled" or "disabled"))
  table.insert(info, string.format("    snacks_previewer: %s", state.is_enabled("snacks_previewer") and "enabled" or "disabled"))

  -- Registered modes
  local modes = require("shelter.modes")
  local mode_list = modes.list()
  table.insert(info, "  Masking modes:")
  for _, mode_name in ipairs(mode_list) do
    local mode_info = modes.info(mode_name)
    if mode_info then
      local builtin_marker = mode_info.is_builtin and " (builtin)" or " (custom)"
      table.insert(info, string.format("    - %s%s: %s", mode_name, builtin_marker, mode_info.description or ""))
    end
  end

  vim.notify(table.concat(info, "\n"), vim.log.levels.INFO)
end

---Check if shelter is setup
---@return boolean
function M.is_setup()
  return is_setup
end

---Get configuration
---@return ShelterUserConfig
function M.get_config()
  return config.get()
end

---Check if a feature is enabled
---@param feature string
---@return boolean
function M.is_enabled(feature)
  return state.is_enabled(feature)
end

---Toggle a feature
---@param feature string
---@return boolean new_state
function M.toggle(feature)
  return state.toggle(feature)
end

---Register a custom masking mode
---@param name string Mode name
---@param definition ShelterModeDefinition|table Mode definition
---@return boolean success
function M.register_mode(name, definition)
  local modes = require("shelter.modes")
  return modes.define(name, definition)
end

---Get the modes module for advanced usage
---@return ShelterModes
function M.modes()
  return require("shelter.modes")
end

---Mask a value directly
---@param value string Value to mask
---@param opts? ShelterMaskOpts Options
---@return string masked
function M.mask_value(value, opts)
  local native = require("shelter.native")
  return native.mask_value(value, opts)
end

---Peek at current line (temporarily reveal for 3 seconds)
function M.peek()
  local buffer = require("shelter.integrations.buffer")
  buffer.peek_line()
end

return M
