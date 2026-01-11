# shelter.nvim

![CleanShot 2026-01-11 at 01 50 01](https://github.com/user-attachments/assets/02033038-51d4-40c7-a853-6972882a7bcf)

![Neovim](https://img.shields.io/badge/NeoVim-%2357A143.svg?&style=for-the-badge&logo=neovim&logoColor=white)
![Lua](https://img.shields.io/badge/lua-%232C2D72.svg?style=for-the-badge&logo=lua&logoColor=white)
![Rust](https://img.shields.io/badge/rust-%23000000.svg?style=for-the-badge&logo=rust&logoColor=white)

Protect sensitive values in your environment files with intelligent, blazingly fast masking.

[Installation](#installation) • [Quick Start](#quick-start) • [Configuration](#configuration) • [Modes](#modes) • [API](#api) • [Performance](#performance) • [vs cloak.nvim](#comparison-with-cloaknvim)

## Why shelter.nvim?

- **Fast** — Rust-native parsing, 1.1x-5x faster than alternatives
- **Instant** — Zero debounce, masks update as you type
- **Smart** — Only re-processes changed lines, not the entire buffer
- **Compliant** — Full EDF support for quotes, escapes, and multi-line values
- **Extensible** — Custom modes with a simple factory pattern

## Installation

**Requirements:** Neovim 0.9+, Rust (for building)

### lazy.nvim

```lua
{
  "philosofonusus/shelter.nvim",
  config = function()
    require("shelter").setup({})
  end,
}
```

The native library is built automatically on first setup if Rust is installed. If the auto-build fails, run `:ShelterBuild` manually.

### packer.nvim

```lua
use {
  "philosofonusus/shelter.nvim",
  config = function()
    require("shelter").setup({})
  end,
}
```

## Quick Start

```lua
-- Minimal setup
require("shelter").setup({})

-- With Telescope integration
require("shelter").setup({
  modules = {
    files = true,
    telescope_previewer = true,
  },
})

-- With partial masking (show first/last characters)
require("shelter").setup({
  default_mode = "partial",
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:Shelter toggle [module]` | Toggle masking on/off |
| `:Shelter enable [module]` | Enable masking |
| `:Shelter disable [module]` | Disable masking |
| `:Shelter peek` | Reveal current line temporarily |
| `:Shelter info` | Show status and modes |
| `:Shelter build` | Rebuild native library |

**Modules:** `files`, `telescope_previewer`, `fzf_previewer`, `snacks_previewer`

## Configuration

```lua
require("shelter").setup({
  -- Appearance
  mask_char = "*",
  highlight_group = "Comment",

  -- Behavior
  skip_comments = true,
  default_mode = "full",  -- "full", "partial", "none", or custom
  env_filetypes = { "dotenv", "sh", "conf" },

  -- Module toggles
  modules = {
    files = {
      shelter_on_leave = true,
      disable_cmp = true,
    },
    telescope_previewer = false,
    fzf_previewer = false,
    snacks_previewer = false,
  },
})
```

## Modes

### Built-in Modes

| Mode | Example | Description |
|------|---------|-------------|
| `full` | `secret123` → `*********` | Mask all characters |
| `partial` | `secret123` → `sec****123` | Show start/end |
| `none` | `secret123` → `secret123` | No masking |

### Mode Options

```lua
modes = {
  full = {
    mask_char = "*",
    preserve_length = true,
    -- fixed_length = 8,  -- Use fixed length instead
  },
  partial = {
    show_start = 3,
    show_end = 3,
    min_mask = 3,
    fallback_mode = "full",
  },
}
```

### Custom Modes

```lua
require("shelter").setup({
  modes = {
    redact = {
      description = "Replace with [REDACTED]",
      apply = function(self, ctx)
        return "[REDACTED]"
      end,
    },

    truncate = {
      description = "Truncate with suffix",
      schema = {
        max_length = { type = "number", default = 5 },
        suffix = { type = "string", default = "..." },
      },
      apply = function(self, ctx)
        local max = self.options.max_length
        if #ctx.value <= max then
          return ctx.value
        end
        return ctx.value:sub(1, max) .. self.options.suffix
      end,
    },
  },

  patterns = {
    ["*_TOKEN"] = "truncate",
  },
})
```

### Mode Context

The `ctx` parameter in custom modes:

```lua
---@class ShelterModeContext
---@field key string           -- Variable name (e.g., "API_KEY")
---@field value string         -- Original value
---@field source string|nil    -- File path
---@field line_number number   -- Line in file
---@field quote_type number    -- 0=none, 1=single, 2=double
---@field is_comment boolean   -- In a comment?
---@field config table         -- Plugin config
```

## Pattern Matching

### Key Patterns (Glob Syntax)

```lua
patterns = {
  ["*_KEY"] = "full",        -- API_KEY, SECRET_KEY
  ["*_PUBLIC*"] = "none",    -- PUBLIC_KEY, MY_PUBLIC_VAR
  ["DB_*"] = "partial",      -- DB_HOST, DB_PASSWORD
  ["DEBUG"] = "none",        -- Exact match
}
```

### Source File Patterns

```lua
sources = {
  [".env.local"] = "none",
  [".env.production"] = "full",
  [".env.*.local"] = "none",
}
```

**Priority:** Key pattern → Source pattern → Default mode

## API

```lua
local shelter = require("shelter")
```

| Function | Description |
|----------|-------------|
| `shelter.setup(opts)` | Initialize plugin |
| `shelter.is_enabled(module)` | Check if module is enabled |
| `shelter.toggle(module)` | Toggle module on/off |
| `shelter.get_config()` | Get current configuration |
| `shelter.peek()` | Reveal current line temporarily |
| `shelter.info()` | Show plugin status |
| `shelter.build()` | Rebuild native library |
| `shelter.register_mode(name, def)` | Register custom mode |
| `shelter.mask_value(value, opts)` | Mask a value directly |

## Performance

<!-- BENCHMARK_START -->
### Performance Benchmarks

Measured on GitHub Actions (Ubuntu, averaged over 1000 iterations):

#### Parsing Performance

| Lines | shelter.nvim | cloak.nvim | Difference |
|-------|--------------|------------|------------|
| 10    | 0.01 ms      | 0.04 ms      | 3.2x faster |
| 50    | 0.04 ms      | 0.17 ms      | 4.0x faster |
| 100    | 0.12 ms      | 0.32 ms      | 2.7x faster |
| 500    | 0.46 ms      | 1.69 ms      | 3.7x faster |

#### Preview Performance (Telescope)

| Lines | shelter.nvim | cloak.nvim | Difference |
|-------|--------------|------------|------------|
| 10    | 0.01 ms      | 0.04 ms      | 3.8x faster |
| 50    | 0.05 ms      | 0.16 ms      | 3.4x faster |
| 100    | 0.10 ms      | 0.33 ms      | 3.2x faster |
| 500    | 0.38 ms      | 1.75 ms      | 4.6x faster |

#### Edit Re-masking Performance

| Lines | shelter.nvim | cloak.nvim | Difference |
|-------|--------------|------------|------------|
| 10    | 0.03 ms      | 0.04 ms      | 1.3x faster |
| 50    | 0.15 ms      | 0.17 ms      | 1.2x faster |
| 100    | 0.31 ms      | 0.32 ms      | ~same |
| 500    | 1.52 ms      | 1.63 ms      | 1.1x faster |

*Last updated: 2026-01-11*
<!-- BENCHMARK_END -->

### Why So Fast?

- **Rust-Native Parsing** — EDF parsing via LuaJIT FFI, no Lua pattern overhead
- **Line-Specific Re-masking** — Only affected lines are re-processed
- **Zero Debounce** — Instant updates with `nvim_buf_attach`
- **Pre-computed Offsets** — O(1) byte-to-line conversion

## Comparison with cloak.nvim

| Feature | shelter.nvim | cloak.nvim |
|---------|--------------|------------|
| Performance | ✅ 1.1x-5x faster | 🟡 Pure Lua |
| Re-masking | ✅ Line-specific | 🟡 Full buffer |
| Partial masking | ✅ Built-in | 🟡 Pattern workaround |
| Multi-line values | ✅ Full support | ❌ None |
| Quote handling | ✅ EDF compliant | 🟡 Pattern-dependent |
| Preview support | ✅ Telescope, FZF, Snacks | 🟡 Telescope only |
| Completion disable | ✅ nvim-cmp + blink-cmp | 🟡 nvim-cmp only |
| Custom modes | ✅ Factory pattern | 🟡 Lua patterns |
| Build step | 🟡 Requires Rust | ✅ None |
| File types | 🟡 Env files only | ✅ Any filetype |

**Choose shelter.nvim** for dotenv files with maximum performance and features.

**Choose cloak.nvim** for any filetype with minimal setup.

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
│         EDF Parsing (korni) + Line Offsets              │
└─────────────────────────────────────────────────────────┘
```

- **Engine** — Coordinates parsing, mode selection, and mask generation
- **Mode Factory** — Creates and manages masking mode instances
- **Extmarks** — Applies masks via Neovim's extmark API
- **nvim_buf_attach** — Tracks line changes for instant re-masking

## License

MIT
