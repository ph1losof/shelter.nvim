# shelter.nvim

<div align="center">

![Neovim](https://img.shields.io/badge/NeoVim-%2357A143.svg?&style=for-the-badge&logo=neovim&logoColor=white)
![Lua](https://img.shields.io/badge/lua-%232C2D72.svg?style=for-the-badge&logo=lua&logoColor=white)
![Rust](https://img.shields.io/badge/rust-%23000000.svg?style=for-the-badge&logo=rust&logoColor=white)

**Protect sensitive values in your environment files with intelligent, blazingly fast masking.**

[Features](#features) •
[Installation](#installation) •
[Configuration](#configuration) •
[Performance](#performance)

</div>

---

## Highlights

| | |
|---|---|
| **Blazingly Fast** | 1.1x-5x faster than alternatives with Rust-native parsing |
| **Instant Feedback** | Zero debounce - masks update immediately as you type |
| **Smart Re-masking** | Only re-processes changed lines, not the entire buffer |
| **EDF Compliant** | Full support for quotes, escapes, and multi-line values |
| **Extensible** | Factory pattern mode system with unlimited custom modes |

---

## Table of Contents

<details>
<summary>Click to expand</summary>

- [Features](#features)
- [Installation](#installation)
  - [Requirements](#requirements)
  - [lazy.nvim](#lazynvim)
  - [packer.nvim](#packernvim)
- [Usage](#usage)
  - [Quick Start](#quick-start)
  - [Commands](#commands)
- [Configuration](#configuration)
  - [Full Options](#full-options)
  - [Mode Configuration](#mode-configuration)
  - [Pattern Matching](#pattern-matching)
- [Mode System](#mode-system)
  - [Built-in Modes](#built-in-modes)
  - [Custom Modes](#custom-modes)
  - [Mode Context](#mode-context)
- [Performance](#performance)
  - [Benchmarks](#benchmarks)
  - [Why So Fast?](#why-so-fast)
- [Comparison with cloak.nvim](#comparison-with-cloaknvim)
- [API Reference](#api-reference)
- [Architecture](#architecture)
- [License](#license)

</details>

---

## Features

<table>
<tr>
<td width="50%">

### Core

- **Buffer Masking** - Auto-mask values in `.env` files on open
- **Line Peek** - Reveal values temporarily with `:Shelter peek`
- **Quote Preservation** - Masks preserve surrounding quotes visually

</td>
<td width="50%">

### Integrations

- **Telescope** - Mask values in file previews
- **FZF-lua** - Mask values in file previews
- **Snacks.nvim** - Mask values in file previews
- **Completion** - Auto-disable nvim-cmp/blink-cmp

</td>
</tr>
</table>

---

## Installation

### Requirements

| Requirement | Version |
|-------------|---------|
| Neovim | 0.9+ |
| LuaJIT | Included with Neovim |
| Rust | For building native library |

### lazy.nvim

```lua
{
  "philosofonusus/shelter.nvim",
  build = "build.lua",
  config = function()
    require("shelter").setup({})
  end,
}
```

### packer.nvim

```lua
use {
  "philosofonusus/shelter.nvim",
  run = "build.lua",
  config = function()
    require("shelter").setup({})
  end,
}
```

---

## Usage

### Quick Start

<table>
<tr>
<td>

**Minimal**
```lua
require("shelter").setup({})
```

</td>
<td>

**With Telescope**
```lua
require("shelter").setup({
  modules = {
    files = true,
    telescope_previewer = true,
  },
})
```

</td>
<td>

**Partial Masking**
```lua
require("shelter").setup({
  default_mode = "partial",
})
```

</td>
</tr>
</table>

### Commands

| Command | Description |
|---------|-------------|
| `:Shelter toggle [module]` | Toggle masking on/off |
| `:Shelter enable [module]` | Enable masking |
| `:Shelter disable [module]` | Disable masking |
| `:Shelter peek` | Reveal current line (3 seconds) |
| `:Shelter info` | Show status and modes |
| `:Shelter build` | Rebuild native library |

**Available modules:** `files`, `telescope_previewer`, `fzf_previewer`, `snacks_previewer`

---

## Configuration

### Full Options

```lua
require("shelter").setup({
  -- Appearance
  mask_char = "*",                           -- Character used for masking
  highlight_group = "Comment",               -- Highlight group for masked text

  -- Behavior
  skip_comments = true,                      -- Skip masking in comment lines
  default_mode = "full",                     -- "full" | "partial" | "none" | custom
  env_filetypes = { "dotenv", "sh", "conf" }, -- Filetypes to mask

  -- Mode configurations (see Mode System section)
  modes = { ... },

  -- Pattern matching (see Pattern Matching section)
  patterns = { ... },
  sources = { ... },

  -- Module toggles
  modules = {
    files = {
      shelter_on_leave = true,               -- Re-shelter when leaving buffer
      disable_cmp = true,                    -- Disable completion in env files
    },
    telescope_previewer = false,
    fzf_previewer = false,
    snacks_previewer = false,
  },
})
```

### Mode Configuration

```lua
modes = {
  full = {
    mask_char = "*",
    preserve_length = true,
    -- fixed_length = 8,  -- Override with fixed length
  },
  partial = {
    show_start = 3,                          -- Characters visible at start
    show_end = 3,                            -- Characters visible at end
    min_mask = 3,                            -- Minimum masked characters
    fallback_mode = "full",                  -- For short values
  },
}
```

### Pattern Matching

#### Key Patterns (Glob Syntax)

```lua
patterns = {
  ["*_KEY"] = "full",        -- API_KEY, SECRET_KEY
  ["*_PUBLIC*"] = "none",    -- PUBLIC_KEY, MY_PUBLIC_VAR
  ["DB_*"] = "partial",      -- DB_HOST, DB_PASSWORD
  ["DEBUG"] = "none",        -- Exact match
}
```

#### Source File Patterns

```lua
sources = {
  [".env.local"] = "none",
  [".env.production"] = "full",
  [".env.*.local"] = "none",
}
```

#### Priority Order

1. Specific key pattern match
2. Specific source pattern match
3. Default mode

---

## Mode System

### Built-in Modes

| Mode | Input | Output | Description |
|------|-------|--------|-------------|
| `full` | `secret123` | `*********` | Mask all characters |
| `partial` | `secret123` | `sec****123` | Show start/end, mask middle |
| `none` | `secret123` | `secret123` | No masking |

### Custom Modes

```lua
require("shelter").setup({
  modes = {
    -- Simple: Replace with fixed text
    redact = {
      description = "Replace with [REDACTED]",
      apply = function(self, ctx)
        return "[REDACTED]"
      end,
    },

    -- Advanced: With configurable options
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

The `ctx` parameter passed to custom mode `apply` functions:

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

---

## Performance

### Benchmarks

<!-- BENCHMARK_START -->
### Performance Benchmarks

Measured on GitHub Actions (Ubuntu, averaged over 1000 iterations):

#### Parsing Performance

| Lines | shelter.nvim | cloak.nvim | Difference |
|-------|--------------|------------|------------|
| 10    | 0.01 ms      | 0.04 ms      | 3.4x faster |
| 50    | 0.06 ms      | 0.18 ms      | 3.0x faster |
| 100    | 0.15 ms      | 0.38 ms      | 2.6x faster |
| 500    | 0.56 ms      | 1.84 ms      | 3.3x faster |

#### Preview Performance (Telescope)

| Lines | shelter.nvim | cloak.nvim | Difference |
|-------|--------------|------------|------------|
| 10    | 0.01 ms      | 0.05 ms      | 4.2x faster |
| 50    | 0.07 ms      | 0.18 ms      | 2.5x faster |
| 100    | 0.15 ms      | 0.36 ms      | 2.4x faster |
| 500    | 0.52 ms      | 1.86 ms      | 3.5x faster |

#### Edit Re-masking Performance

| Lines | shelter.nvim | cloak.nvim | Difference |
|-------|--------------|------------|------------|
| 10    | 0.04 ms      | 0.05 ms      | 1.3x faster |
| 50    | 0.17 ms      | 0.21 ms      | 1.2x faster |
| 100    | 0.36 ms      | 0.36 ms      | ~same |
| 500    | 1.70 ms      | 1.79 ms      | 1.1x faster |

*Last updated: 2026-01-11*
<!-- BENCHMARK_END -->

### Why So Fast?

| Optimization | Description |
|--------------|-------------|
| **Rust-Native Parsing** | EDF parsing via LuaJIT FFI - no Lua pattern matching overhead |
| **Line-Specific Re-masking** | On edit, only affected lines are re-processed |
| **Zero Debounce** | Instant mask updates with `nvim_buf_attach` on_lines callback |
| **Pre-computed Offsets** | O(1) byte-to-line conversion from Rust |

---

## Comparison with cloak.nvim

| Feature | shelter.nvim | cloak.nvim |
|---------|--------------|------------|
| **Performance** | 1.1x-5x faster | Pure Lua |
| **Re-masking** | Line-specific (instant) | Full buffer |
| **Partial Masking** | Built-in mode | Pattern workaround |
| **Multi-line Values** | Full support | None |
| **Quote Handling** | EDF compliant | Pattern-dependent |
| **Preview Support** | Telescope, FZF, Snacks | Telescope only |
| **Completion Disable** | nvim-cmp + blink-cmp | nvim-cmp only |
| **Custom Modes** | Factory pattern | Lua patterns |
| **Runtime Info** | `:Shelter info` | None |
| **Build Step** | Requires Rust | None |
| **Any Filetype** | Env files only | Any filetype |
| **Lines of Code** | ~2500 LOC | ~300 LOC |

> **Choose shelter.nvim** for dotenv files with maximum performance and features.
>
> **Choose cloak.nvim** for any filetype with minimal setup.

---

## API Reference

```lua
local shelter = require("shelter")
```

| Category | Function | Description |
|----------|----------|-------------|
| **Setup** | `shelter.setup(opts)` | Initialize plugin with options |
| **State** | `shelter.is_enabled(module)` | Check if module is enabled |
| | `shelter.toggle(module)` | Toggle module on/off |
| | `shelter.get_config()` | Get current configuration |
| **Actions** | `shelter.peek()` | Reveal current line temporarily |
| | `shelter.info()` | Show plugin status |
| | `shelter.build()` | Rebuild native library |
| **Modes** | `shelter.register_mode(name, def)` | Register custom mode |
| | `shelter.mask_value(value, opts)` | Mask a value directly |

---

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

| Component | Responsibility |
|-----------|----------------|
| **Engine** | Coordinates parsing, mode selection, and mask generation |
| **Mode Factory** | Creates and manages masking mode instances |
| **Extmarks** | Applies masks via Neovim's extmark API with virtual text |
| **nvim_buf_attach** | Tracks line changes for instant re-masking |

---

## License

MIT
