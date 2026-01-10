# shelter.nvim

EDF-compliant dotenv file masking for Neovim with a Rust-native core.

<div align="center">

![Neovim](https://img.shields.io/badge/NeoVim-%2357A143.svg?&style=for-the-badge&logo=neovim&logoColor=white)
![Lua](https://img.shields.io/badge/lua-%232C2D72.svg?style=for-the-badge&logo=lua&logoColor=white)
![Rust](https://img.shields.io/badge/rust-%23000000.svg?style=for-the-badge&logo=rust&logoColor=white)

**Protect sensitive values in your environment files with intelligent, high-performance masking.**

</div>

## Table of Contents

- [Features](#features)
- [Comparison with cloak.nvim](#comparison-with-cloaknvim)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Mode System](#mode-system)
  - [Built-in Modes](#built-in-modes)
  - [Custom Modes](#custom-modes)
  - [Mode Context](#mode-context)
  - [Programmatic API](#programmatic-api)
- [Pattern Matching](#pattern-matching)
- [API Reference](#api-reference)
- [Architecture](#architecture)
- [EDF Compliance](#edf-compliance)
- [License](#license)

## Features

- **Buffer Masking**: Automatically mask values in `.env` files when opened
- **Line Peek**: Temporarily reveal values with `:Shelter peek` (auto-hides after 3 seconds)
- **Previewer Support**: Mask values in Telescope, FZF-lua, and Snacks.nvim previewers
- **Extensible Mode System**: Factory pattern with built-in `full`, `partial`, `none` modes + unlimited custom modes
- **Pattern Matching**: Configure different masking modes for different keys or source files
- **CMP Integration**: Automatically disables nvim-cmp/blink-cmp in env file buffers to prevent value leakage
- **Native Performance**: Rust-powered parsing and masking via LuaJIT FFI
- **EDF Compliance**: Proper handling of quotes, escapes, multiline values, and comments

## Comparison with cloak.nvim

| Feature               | shelter.nvim                                                        | [cloak.nvim](https://github.com/laytan/cloak.nvim)   |
| --------------------- | ------------------------------------------------------------------- | ---------------------------------------------------- |
| Partial Value Masking | ✅ Built-in `partial` mode (`abc***xyz`)                            | 🟡 Prefix only via `replace` patterns                |
| Per-Key Masking Modes | ✅ Glob patterns map to modes (`*_SECRET` -> full, `DEBUG` -> none) | 🟡 Lua patterns with replace, but same masking style |
| Per-Source File Modes | ✅ Different modes per env file (`.env.prod` vs `.env.local`)       | 🟡 Separate pattern entries per file_pattern         |
| Custom Mode System    | ✅ Full factory pattern with programmatic API                       | 🟡 Via Lua replace patterns only                     |
| Preview Protection    | ✅ Telescope, FZF-lua, and Snacks.nvim previewers                   | 🟡 Only Telescope previewer (0.2.x+)                 |
| Completion Disable    | ✅ Supports both blink-cmp and nvim-cmp, configurable               | 🟡 Only nvim-cmp, always disabled                    |
| Multi-line Values     | ✅ Full EDF-compliant support                                       | ❌ No support                                        |
| Quote/Escape Handling | ✅ Full EDF support (single, double, escapes)                       | 🟡 Pattern-dependent                                 |
| Line Peek             | ✅ Timed auto-hide (3 seconds)                                      | ✅ Until cursor moves                                |
| Mask on Leave         | ✅ Configurable                                                     | ✅ Configurable                                      |
| Hide True Length      | ✅ Via mode options (`fixed_length`)                                | ✅ Built-in (`cloak_length`)                         |
| Custom Highlights     | ✅ Configurable highlight group                                     | ✅ Configurable highlight group                      |
| Performance           | ✅ Rust-native parsing via LuaJIT FFI, optimized for large files    | 🟡 Pure Lua, simpler implementation                  |
| Runtime Info          | ✅ `:Shelter info` shows status and modes                           | ❌ No runtime introspection                          |
| Lines of Code         | 🟡 ~2500+ LOC (Lua + Rust)                                          | ✅ ~300 LOC                                          |
| Build Step            | 🟡 Requires Rust toolchain                                          | ✅ None, pure Lua                                    |
| Setup Complexity      | 🟡 More options, but sensible defaults                              | ✅ Minimal configuration                             |
| Filetype Support      | 🟡 Env file syntax only                                             | ✅ Any filetype via patterns                         |

### When to Choose shelter.nvim

Choose shelter.nvim if you work with **dotenv files**. It's built specifically for dotenv syntax, offers maximum integrations (Telescope, FZF-lua, Snacks.nvim), and provides proper handling of multi-line variables, quotes, and escape sequences.

### When to Choose cloak.nvim

Choose cloak.nvim if you need to mask values in **any filetype** (not just env files), want a **pure-Lua solution** with no build step, or prefer minimal setup with Lua pattern syntax.

<!-- BENCHMARK_START -->
### Performance Benchmarks

Measured on GitHub Actions (Ubuntu, averaged over 10 iterations):

| Lines | shelter.nvim | cloak.nvim | Difference |
|-------|--------------|------------|------------|
| 10    | 0.10 ms      | 0.08 ms      | 1.3x slower |
| 50    | 0.11 ms      | 0.21 ms      | 2.0x faster |
| 100    | 0.19 ms      | 0.41 ms      | 2.1x faster |
| 500    | 0.82 ms      | 1.85 ms      | 2.3x faster |

*Last updated: 2026-01-10*
<!-- BENCHMARK_END -->

## Requirements

- Neovim 0.9+
- LuaJIT (included with Neovim)
- For building from source: Rust toolchain

## Installation

### lazy.nvim

```lua
{
  "ph1losof/shelter.nvim",
  build = "build.lua",
  config = function()
    require("shelter").setup({
      -- Configuration here
    })
  end,
}
```

### packer.nvim

```lua
use {
  "ph1losof/shelter.nvim",
  run = "build.lua",
  config = function()
    require("shelter").setup()
  end,
}
```

## Configuration

```lua
require("shelter").setup({
  -- Character used for masking (default: "*")
  mask_char = "*",

  -- Highlight group for masked text
  highlight_group = "Comment",

  -- Skip masking values in comment lines
  skip_comments = true,

  -- Default masking mode: "full" | "partial" | "none" | custom
  default_mode = "full",

  -- Mode configurations (built-in modes have sensible defaults)
  modes = {
    full = {
      mask_char = "*",        -- Override global mask_char for this mode
      preserve_length = true, -- Mask same length as value
      -- fixed_length = 8,    -- Or use fixed output length
    },
    partial = {
      mask_char = "*",
      show_start = 3,         -- Characters to show at start
      show_end = 3,           -- Characters to show at end
      min_mask = 3,           -- Minimum masked characters
      fallback_mode = "full", -- Mode for short values: "full" | "none"
    },
    none = {},                -- No options needed
  },

  -- Filetypes to mask (default: {"dotenv", "edf"}, configurable)
  env_filetypes = { "dotenv", "edf" },

  -- Key patterns to mode mapping (glob patterns)
  patterns = {
    ["*_PUBLIC"] = "none",    -- Public keys visible
    ["*_SECRET"] = "full",    -- Secrets fully masked
    ["DB_*"] = "partial",     -- DB vars partially masked
  },

  -- Source file patterns to mode mapping
  sources = {
    [".env.local"] = "none",       -- Local env visible
    [".env.production"] = "full",  -- Production fully masked
  },

  -- Module toggles
  modules = {
    -- Buffer masking: true, false, or detailed config
    files = {
      shelter_on_leave = true,  -- Re-shelter when leaving buffer
      disable_cmp = true,       -- Disable completion in env buffers
    },
    telescope_previewer = false,
    fzf_previewer = false,
    snacks_previewer = false,
  },
})
```

### Minimal Configuration

```lua
-- Just enable buffer masking with defaults
require("shelter").setup({})

-- Enable with Telescope previewer support
require("shelter").setup({
  modules = {
    files = true,
    telescope_previewer = true,
  },
})

-- Partial masking by default
require("shelter").setup({
  default_mode = "partial",
  modes = {
    partial = {
      show_start = 4,
      show_end = 4,
    },
  },
})
```

## Commands

| Command                     | Description                                            |
| --------------------------- | ------------------------------------------------------ |
| `:Shelter toggle [module]`  | Toggle masking on/off (optionally for specific module) |
| `:Shelter enable [module]`  | Enable masking                                         |
| `:Shelter disable [module]` | Disable masking                                        |
| `:Shelter peek`             | Temporarily reveal current line value (3 seconds)      |
| `:Shelter build`            | Build/rebuild native library                           |
| `:Shelter info`             | Show plugin status and registered modes                |

### Module Names

- `files` - Buffer masking (alias: `buffer`)
- `telescope_previewer` - Telescope preview masking (alias: `telescope`)
- `fzf_previewer` - FZF-lua preview masking (alias: `fzf`)
- `snacks_previewer` - Snacks preview masking (alias: `snacks`)

### Examples

```vim
:Shelter toggle              " Toggle all modules
:Shelter toggle files        " Toggle only buffer masking
:Shelter enable telescope    " Enable telescope previewer
:Shelter peek                " Reveal current line for 3 seconds
:Shelter info                " Show status and modes
```

## Mode System

shelter.nvim uses an extensible factory pattern for masking modes. All modes (including built-ins) implement the same interface, making it easy to create custom masking behaviors.

### Built-in Modes

#### `full` (default)

Replaces all characters with mask character.

```
"secret123" -> "*********"
```

Options:

- `mask_char` - Character to use (default: `*`)
- `preserve_length` - Keep original length (default: `true`)
- `fixed_length` - Use fixed output length instead

#### `partial`

Shows start/end characters, masks the middle.

```
"mysecretvalue" -> "mys*******lue"
```

Options:

- `mask_char` - Character to use (default: `*`)
- `show_start` - Characters to show at start (default: `3`)
- `show_end` - Characters to show at end (default: `3`)
- `min_mask` - Minimum masked characters (default: `3`)
- `fallback_mode` - Mode for short values: `"full"` or `"none"`

#### `none`

No masking - shows value as-is. Useful for whitelisted keys.

### Custom Modes

Define custom modes inline in your config:

```lua
require("shelter").setup({
  modes = {
    -- Simple custom mode
    redact = {
      description = "Replace with [REDACTED]",
      apply = function(self, ctx)
        return "[REDACTED]"
      end,
    },

    -- Custom mode with options
    truncate = {
      description = "Show first N chars with suffix",
      schema = {
        max_length = { type = "number", default = 5 },
        suffix = { type = "string", default = "..." },
      },
      default_options = {
        max_length = 5,
        suffix = "...",
      },
      apply = function(self, ctx)
        local max = self:get_option("max_length")
        local suffix = self:get_option("suffix")
        if #ctx.value <= max then
          return ctx.value
        end
        return ctx.value:sub(1, max) .. suffix
      end,
    },

    -- Context-aware mode
    smart = {
      description = "Context-aware masking",
      apply = function(self, ctx)
        -- Different masking based on source file
        if ctx.source and ctx.source:match("%.prod") then
          return string.rep("*", #ctx.value)
        end
        -- Show URL structure but mask credentials
        if ctx.key:match("_URL$") then
          return ctx.value:gsub(":([^@]+)@", ":****@")
        end
        return ctx.value
      end,
    },
  },

  patterns = {
    ["*_SENSITIVE"] = "redact",
    ["*_TOKEN"] = "truncate",
    ["*_URL"] = "smart",
  },
})
```

### Mode Context

The `apply` function receives a context object with all available information:

```lua
---@class ShelterModeContext
---@field key string           -- Environment variable key
---@field value string         -- Original value to mask
---@field source string|nil    -- Source file path
---@field line_number number   -- Line in file
---@field quote_type number    -- 0=none, 1=single, 2=double
---@field is_comment boolean   -- Whether in a comment
---@field config table         -- Full plugin config
---@field mode_options table   -- Current mode options
```

### Programmatic API

```lua
local modes = require("shelter.modes")

-- Create independent mode instances
local full = modes.create("full", { mask_char = "#" })
local partial = modes.create("partial", { show_start = 2, show_end = 2 })

-- Apply to a value
local ctx = { key = "SECRET", value = "mysecret", line_number = 1 }
local masked = full:apply(ctx)  -- "########"

-- Register mode at runtime
modes.define("custom", {
  description = "My custom mode",
  apply = function(self, ctx)
    return "masked:" .. #ctx.value
  end,
})

-- Configure existing mode
modes.configure("partial", { show_start = 1, show_end = 1 })

-- Query modes
modes.exists("full")      -- true
modes.is_builtin("full")  -- true
modes.list()              -- { "full", "none", "partial", ... }
modes.info("partial")     -- { name, description, options, schema, is_builtin }
```

## Pattern Matching

shelter.nvim uses glob-style patterns for flexible key and source file matching.

### Key Patterns

Match environment variable names:

```lua
patterns = {
  ["*_KEY"] = "full",         -- API_KEY, SECRET_KEY, etc.
  ["*_PUBLIC*"] = "none",     -- PUBLIC_KEY, MY_PUBLIC_VAR
  ["DB_*"] = "partial",       -- DB_HOST, DB_PASSWORD, DB_USER
  ["AWS_*"] = "full",         -- AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
  ["DEBUG"] = "none",         -- Exact match
}
```

### Source Patterns

Match source file names:

```lua
sources = {
  [".env.local"] = "none",         -- Development, show all
  [".env.development"] = "partial", -- Dev, partial masking
  [".env.production"] = "full",    -- Prod, full masking
  [".env.*.local"] = "none",       -- Any local override
}
```

### Pattern Priority

1. Specific key pattern match
2. Specific source pattern match
3. Default mode

## API Reference

```lua
local shelter = require("shelter")

-- Setup
shelter.setup(opts)              -- Configure and initialize

-- State
shelter.is_setup()               -- Check if initialized
shelter.is_enabled("files")      -- Check if module is enabled
shelter.toggle("files")          -- Toggle module, returns new state
shelter.get_config()             -- Get current configuration

-- Modes
shelter.modes()                  -- Get modes module
shelter.register_mode(name, def) -- Register custom mode
shelter.mask_value(value, opts)  -- Mask a value directly

-- Actions
shelter.peek()                   -- Reveal current line temporarily
shelter.build()                  -- Build native library
shelter.info()                   -- Show plugin info
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    shelter.nvim (Lua)                   │
├─────────────────────────────────────────────────────────┤
│  Config │ State │ Mode Factory │ Engine │ Integrations │
└─────────────────────────────────────────────────────────┘
                          │ LuaJIT FFI
                          ▼
┌─────────────────────────────────────────────────────────┐
│               shelter-core (Rust cdylib)                │
├─────────────────────────────────────────────────────────┤
│  EDF Parsing (korni) + Masking Primitives               │
└─────────────────────────────────────────────────────────┘
```

### Mode System Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    Mode Factory                          │
├──────────────────────────────────────────────────────────┤
│  modes.create()  │  modes.define()  │  modes.configure() │
└──────────────────────────────────────────────────────────┘
                           │
           ┌───────────────┼───────────────┐
           ▼               ▼               ▼
    ┌───────────┐   ┌───────────┐   ┌───────────┐
    │ FullMode  │   │PartialMode│   │ NoneMode  │
    └───────────┘   └───────────┘   └───────────┘
           │               │               │
           └───────────────┴───────────────┘
                           │
                           ▼
                  ┌─────────────────┐
                  │ ShelterModeBase │
                  │ ─────────────── │
                  │  - apply()      │
                  │  - validate()   │
                  │  - configure()  │
                  │  - get_option() │
                  │  - clone()      │
                  └─────────────────┘
```

## EDF Compliance

shelter.nvim uses [korni](https://github.com/philosofonusus/korni) for EDF 1.0.1 compliant parsing:

- Strict UTF-8 validation
- Proper quote handling (single, double, none)
- Escape sequence processing (`\n`, `\t`, `\\`, etc.)
- Multi-line value support
- Export prefix recognition (`export VAR=value`)
- Comment line detection and handling

## License

MIT
