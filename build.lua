#!/usr/bin/env lua
-- shelter.nvim build script
-- Run this to download pre-built binaries or build from source

local uv = vim.uv or vim.loop or require("luv")

local M = {}

-- Platform detection
local function get_platform()
  local uname = uv.os_uname()
  local sysname = uname.sysname
  local machine = uname.machine

  if sysname == "Darwin" then
    if machine == "arm64" then
      return "aarch64-apple-darwin", "libshelter_core.dylib"
    else
      return "x86_64-apple-darwin", "libshelter_core.dylib"
    end
  elseif sysname == "Linux" then
    return "x86_64-unknown-linux-gnu", "libshelter_core.so"
  elseif sysname:match("Windows") then
    return "x86_64-pc-windows-msvc", "shelter_core.dll"
  end

  return nil, nil
end

-- Get plugin directory
local function get_plugin_dir()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":h")
end

-- Check if library exists
local function library_exists()
  local plugin_dir = get_plugin_dir()
  local _, lib_name = get_platform()
  if not lib_name then
    return false
  end

  local lib_path = plugin_dir .. "/lib/" .. lib_name
  return vim.fn.filereadable(lib_path) == 1
end

-- Build from source
local function build_from_source()
  local plugin_dir = get_plugin_dir()
  local crate_dir = plugin_dir .. "/crates/shelter-core"

  print("Building shelter-core from source...")

  local handle = io.popen(string.format("cd %q && cargo build --release 2>&1", crate_dir))
  if not handle then
    print("ERROR: Failed to run cargo build")
    return false
  end

  local output = handle:read("*a")
  local success = handle:close()

  if not success then
    print("ERROR: Build failed:")
    print(output)
    return false
  end

  -- Copy library to lib directory
  local platform, lib_name = get_platform()
  if not platform then
    print("ERROR: Unsupported platform")
    return false
  end

  local src = plugin_dir .. "/../../target/release/" .. lib_name
  local dst_dir = plugin_dir .. "/lib"
  local dst = dst_dir .. "/" .. lib_name

  os.execute(string.format("mkdir -p %q", dst_dir))
  local copy_success = os.execute(string.format("cp %q %q", src, dst))

  if copy_success then
    print("SUCCESS: Library built and installed to " .. dst)
    return true
  else
    print("ERROR: Failed to copy library")
    return false
  end
end

-- Download pre-built binary
local function download_binary(version)
  version = version or "v0.1.0"
  local platform, lib_name = get_platform()

  if not platform then
    print("ERROR: Unsupported platform")
    return false
  end

  local plugin_dir = get_plugin_dir()
  local dst_dir = plugin_dir .. "/lib"
  local dst = dst_dir .. "/" .. lib_name

  -- GitHub release URL
  local url = string.format(
    "https://github.com/philosofonusus/shelter.nvim/releases/download/%s/%s-%s",
    version,
    lib_name,
    platform
  )

  print("Downloading " .. url .. "...")

  os.execute(string.format("mkdir -p %q", dst_dir))

  -- Try curl first, then wget
  local download_cmd = string.format("curl -fsSL -o %q %q 2>/dev/null || wget -q -O %q %q", dst, url, dst, url)
  local success = os.execute(download_cmd)

  if success then
    print("SUCCESS: Library downloaded to " .. dst)
    return true
  else
    print("WARN: Download failed, falling back to source build...")
    return build_from_source()
  end
end

-- Main entry point
function M.ensure_binary()
  if library_exists() then
    print("shelter-core library already installed")
    return true
  end

  -- Try download first, fall back to build
  return download_binary() or build_from_source()
end

-- Export for require()
M.build_from_source = build_from_source
M.download_binary = download_binary
M.library_exists = library_exists
M.get_platform = get_platform

-- If run directly
if arg and arg[0]:match("build%.lua$") then
  M.ensure_binary()
end

return M
