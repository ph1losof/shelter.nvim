# shelter.nvim

EDF-compliant dotenv file masking for Neovim with a Rust-native core.

## Features

- **Buffer Masking**: Automatically mask values in `.env` files
- **Line Peek**: Temporarily reveal values with `:ShelterPeek`
- **Previewer Support**: Mask values in Telescope, FZF-lua, and Snacks.nvim previewers
- **Extensible Mode System**: Factory pattern with built-in `full`, `partial`, `none` modes + custom modes
- **Pattern Matching**: Configure different modes for different keys/files
- **Native Performance**: Rust-powered parsing and masking via LuaJIT FFI

## Requirements

- Neovim 0.9+
- LuaJIT (included with Neovim)
- For building from source: Rust toolchain

## Installation

### lazy.nvim

```lua
{
  "philosofonusus/shelter.nvim",
  build = "lua build.lua",
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
  "philosofonusus/shelter.nvim",
  run = "lua build.lua",
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
      min_mask = 3,           -- Minimum mask characters
      fallback_mode = "full", -- Mode for short values: "full" | "none"
    },
    none = {},                -- No options needed
  },

  -- File patterns to match as env files
  env_file_patterns = { ".env", ".env.*", ".envrc" },

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
    files = true,               -- Buffer masking
    peek = false,               -- Line peek
    telescope_previewer = false,
    fzf_previewer = false,
    snacks_previewer = false,
  },

  -- Buffer settings
  buffer = {
    shelter_on_leave = true,    -- Re-shelter when leaving buffer
  },
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:ShelterToggle [enable\|disable]` | Toggle masking on/off |
| `:ShelterPeek` | Temporarily reveal current line value |
| `:ShelterBuild` | Build/download native library |
| `:ShelterInfo` | Show plugin info and status |

## Mode System

shelter.nvim uses an extensible factory pattern for masking modes. All modes (including built-ins) implement the same interface.

### Built-in Modes

#### `full` (default)
Replaces all characters with mask character.
```
"secret123" -> "*********"
```

#### `partial`
Shows start/end characters, masks the middle.
```
"mysecretvalue" -> "mys*******lue"
```

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
          return ctx.value:gsub(":[^@]+@", ":****@")
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

The `apply` function receives a context object:

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

## API

```lua
local shelter = require("shelter")

-- Check if masking is enabled
shelter.is_enabled("files")

-- Toggle a feature
shelter.toggle("files")

-- Get modes module
local modes = shelter.modes()

-- Register custom mode
shelter.register_mode("custom", {
  description = "Custom mode",
  apply = function(self, ctx) return "***" end,
})

-- Mask a value directly
shelter.mask_value("secret", { mode = "partial" })

-- Peek at current line
shelter.peek()
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
                  │  ShelterModeBase │
                  │  ───────────────  │
                  │  - apply()       │
                  │  - validate()    │
                  │  - configure()   │
                  │  - get_option()  │
                  │  - clone()       │
                  └─────────────────┘
```

## EDF Compliance

shelter.nvim uses [korni](https://github.com/philosofonusus/korni) for EDF 1.0.1 compliant parsing:

- Strict UTF-8 validation
- Proper quote handling (single, double, none)
- Escape sequence processing
- Multi-line value support
- Export prefix recognition

## License

MIT
