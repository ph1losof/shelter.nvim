# shelter.nvim

![CleanShot 2026-01-11 at 01 50 01](https://github.com/user-attachments/assets/02033038-51d4-40c7-a853-6972882a7bcf)

![Neovim](https://img.shields.io/badge/NeoVim-%2357A143.svg?&style=for-the-badge&logo=neovim&logoColor=white)
![Lua](https://img.shields.io/badge/lua-%232C2D72.svg?style=for-the-badge&logo=lua&logoColor=white)
![Rust](https://img.shields.io/badge/rust-%23000000.svg?style=for-the-badge&logo=rust&logoColor=white)

Protect sensitive values in your environment files with intelligent, blazingly fast masking.

[Installation](#installation) • [Quick Start](#quick-start) • [Configuration](#configuration) • [Modules](#modules) • [Modes](#modes) • [ecolog Integration](#ecolog-integration) • [API](#api) • [vs cloak.nvim](#comparison-with-cloaknvim)

## Why shelter.nvim?

- **Secure** — Never leak API keys in meetings, screen shares, or pair programming sessions
- **Fast** — Rust-native parsing, 3-12x faster than alternatives
- **Instant** — Zero debounce, masks update as you type
- **Smart** — Only re-processes changed lines, not the entire buffer
- **Compliant** — Full EDF support for quotes, escapes, and multi-line values
- **Extensible** — Custom modes with a simple factory pattern

## Installation

**Requirements:** Neovim 0.9+, Rust (for building)

### lazy.nvim

```lua
{
  "ph1losof/shelter.nvim",
  lazy = false,
  config = function()
    require("shelter").setup({})
  end,
}
```

The native library is built automatically on first setup if Rust is installed. If the auto-build fails, then run `:ShelterBuild` manually.

### packer.nvim

```lua
use {
  "ph1losof/shelter.nvim",
  config = function()
    require("shelter").setup({})
  end,
}
```

## Quick Start

```lua
-- Minimal setup - masks all .env files in buffers
require("shelter").setup({})

-- With picker integration (Telescope, FZF, Snacks)
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

-- With ecolog.nvim integration
require("shelter").setup({
  modules = {
    files = true,
    ecolog = true,  -- Mask LSP completions and hover
  },
})
```

## Commands

| Command                     | Description                     |
| --------------------------- | ------------------------------- |
| `:Shelter toggle [module]`  | Toggle masking on/off           |
| `:Shelter enable [module]`  | Enable masking                  |
| `:Shelter disable [module]` | Disable masking                 |
| `:Shelter peek`             | Reveal value while cursor is on it |
| `:Shelter info`             | Show status and modes           |
| `:Shelter build`            | Rebuild native library          |

## Configuration

### Full Configuration Reference

```lua
require("shelter").setup({
  -- Appearance
  mask_char = "*",              -- Character used for masking
  highlight_group = "Comment",  -- Highlight group for masked text

  -- Behavior
  skip_comments = true,         -- Don't mask commented lines
  default_mode = "full",        -- "full", "partial", "none", or custom
  env_filetypes = { "dotenv", "edf", "sh", "conf" },  -- Filetypes to mask

  -- Module toggles (see Modules section for details)
  modules = {
    files = true,               -- Buffer masking
    telescope_previewer = false,
    fzf_previewer = false,
    snacks_previewer = false,
    ecolog = false,             -- ecolog.nvim integration
  },

  -- Pattern-based mode selection
  patterns = {
    ["*_KEY"] = "full",         -- Full mask for API keys
    ["*_PUBLIC*"] = "none",     -- Don't mask public values
    ["DEBUG"] = "none",         -- Don't mask debug flags
  },

  -- Source file-based mode selection
  sources = {
    [".env.local"] = "none",       -- Don't mask local dev file
    [".env.production"] = "full",  -- Full mask for production
  },

  -- Mode configuration (see Modes section)
  modes = {
    full = { preserve_length = true },
    partial = { show_start = 3, show_end = 3 },
  },
})
```

### A note on filetypes

Neovim's default filetype detection doesn't assign `dotenv` to `.env` files out of
the box; variants like `.env.local` or `.env.production` can also be inconsistent
or detected correctly only after the file is opened.

This matters because we rely on Neovim's filetype detection, so if a file you'd
like to shelter is not explicitly mapped to a filetype, shelter.nvim may not be active
at all or may not work correctly in previews.

Custom mappings can be added using the `vim.filetype.add` API. For example, you
can create a file in your Neovim runtime path (usually `~/.config/nvim/filetype.lua`)
and add the following:

```lua
vim.filetype.add({
  -- Mappings based on file extension
  extension = {
    env = "dotenv",
  },
  -- Mappings based on FULL filename
  filename = {
    [".env"] = "dotenv",
    ["env"] = "dotenv",
  },
  -- Mappings based on filename pattern match
  pattern = {
    -- Match filenames like ".env.development", "env.local" and so on
    [".?env.*"] = "dotenv",
  },
})
```

This can be done with any filetype you want, but don't forget to add them to the
`env_filetypes` configuration option as well!

## Modules

Modules control which contexts shelter.nvim masks values in.

### files

Buffer masking for `.env` files opened in Neovim.

```lua
modules = {
  files = true,  -- Simple enable

  -- Or with options:
  files = {
    shelter_on_leave = true,  -- Re-mask when leaving buffer (default: true)
    disable_cmp = true,       -- Disable completion in .env files (default: true)
  },
}
```

**Features:**
- Instant masking as you type
- Line-specific updates (only changed lines re-masked)
- Peek functionality to reveal current value while cursor stays on it
- Optional completion disable to prevent plugins from exposing values

### telescope_previewer

Mask values in Telescope file previews.

```lua
modules = {
  telescope_previewer = true,
}
```

When enabled, `.env` files shown in Telescope's preview window will have their values masked.

### fzf_previewer

Mask values in fzf-lua file previews.

```lua
modules = {
  fzf_previewer = true,
}
```

### snacks_previewer

Mask values in Snacks.nvim file previews.

```lua
modules = {
  snacks_previewer = true,
}
```

### ecolog

Integration with [ecolog.nvim](https://github.com/ph1losof/ecolog.nvim) for LSP-based environment variable management.

```lua
modules = {
  ecolog = true,  -- Enable all contexts

  -- Or with fine-grained control:
  ecolog = {
    cmp = true,     -- Mask completion item values (default: true)
    peek = true,    -- Mask hover/peek content (default: true)
    picker = true,  -- Mask variable picker entries (default: true)
  },
}
```

See [ecolog Integration](#ecolog-integration) for detailed setup.

## Modes

### Built-in Modes

| Mode      | Example                    | Description         |
| --------- | -------------------------- | ------------------- |
| `full`    | `secret123` → `*********`  | Mask all characters |
| `partial` | `secret123` → `sec****123` | Show start/end      |
| `none`    | `secret123` → `secret123`  | No masking          |

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
    fallback_mode = "full",  -- Use full mode for short values
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

## ecolog Integration

shelter.nvim provides deep integration with [ecolog.nvim](https://github.com/ph1losof/ecolog.nvim), an LSP-powered environment variable manager.

### Why Use Both?

- **ecolog.nvim** provides LSP features: completion, hover, go-to-definition, diagnostics
- **shelter.nvim** ensures values are never exposed, even in LSP responses

Without shelter.nvim, when you trigger completion or hover in ecolog, the actual values are visible. With the integration enabled, values are masked everywhere while still being functional.

### Setup

Install both plugins:

```lua
-- lazy.nvim
{
  "ph1losof/ecolog.nvim",
  config = function()
    require("ecolog").setup({
      lsp = { backend = "auto" },
    })
  end,
},
{
  "ph1losof/shelter.nvim",
  config = function()
    require("shelter").setup({
      modules = {
        files = true,           -- Buffer masking
        telescope_previewer = true,
        ecolog = {
          cmp = true,           -- Mask completion values
          peek = true,          -- Mask hover content
          picker = true,        -- Mask picker entries
        },
      },
    })
  end,
},
```

### How It Works

shelter.nvim intercepts ecolog-lsp responses at the LSP client level:

1. **Completion** (`cmp`): When you type `process.env.`, completion items show masked values
2. **Hover** (`peek`): When you hover over a variable, the value is masked
3. **Picker** (`picker`): The variable browser shows masked values

**Copying/Peeking Values:** Even with masking enabled, you can still copy the real value using ecolog's copy commands. shelter.nvim hooks into ecolog's `on_variable_peek` hook to provide the unmasked value when explicitly requested.

### Runtime Control

Toggle ecolog contexts independently:

```lua
local shelter = require("shelter")

-- Toggle all ecolog contexts
shelter.toggle("ecolog")

-- Toggle specific contexts
shelter.integrations.ecolog.toggle("cmp")
shelter.integrations.ecolog.toggle("peek")
shelter.integrations.ecolog.toggle("picker")
```

## API

```lua
local shelter = require("shelter")
```

| Function                           | Description                     |
| ---------------------------------- | ------------------------------- |
| `shelter.setup(opts)`              | Initialize plugin               |
| `shelter.is_enabled(module)`       | Check if module is enabled      |
| `shelter.toggle(module)`           | Toggle module on/off            |
| `shelter.get_config()`             | Get current configuration       |
| `shelter.peek()`                   | Reveal value while cursor is on it |
| `shelter.info()`                   | Show plugin status              |
| `shelter.build()`                  | Rebuild native library          |
| `shelter.register_mode(name, def)` | Register custom mode            |
| `shelter.mask_value(value, opts)`  | Mask a value directly           |

## Comparison with cloak.nvim and camouflage.nvim

### Feature Comparison

| Feature                | shelter.nvim                   | cloak.nvim                   | camouflage.nvim              |
| ---------------------- | ------------------------------ | ---------------------------- | ---------------------------- |
| **Performance**        | 3-12x faster (Rust-native)     | Pure Lua                     | Pure Lua + TreeSitter        |
| **Re-masking**         | Line-specific (incremental)    | Full buffer re-parse         | Full buffer re-parse         |
| **Partial masking**    | Built-in mode                  | Manual pattern workaround    | Multiple styles (stars, dotted, scramble) |
| **Multi-line values**  | Full support                   | Not supported                | Supported                    |
| **Quote handling**     | EDF compliant                  | Pattern-dependent            | Basic                        |
| **Preview support**    | Telescope, FZF, Snacks         | Telescope only               | Telescope, Snacks            |
| **Completion disable** | nvim-cmp + blink-cmp           | nvim-cmp only                | nvim-cmp                     |
| **Custom modes**       | Factory pattern                | Lua patterns                 | Custom parsers               |
| **LSP integration**    | ecolog-plugin                  | None                         | None                         |
| **Build step**         | Requires Rust                  | None                         | None                         |
| **File types**         | Env files only                 | Any filetype                 | 13+ formats (env, json, yaml, toml, etc.) |
| **Leak-free masking**  | Yes — zero-gap architecture    | [No — flashes values on open/paste](https://github.com/laytan/cloak.nvim/issues/25) | Debounce-based (may flash)   |
| **Security features**  | N/A                            | N/A                          | Have I Been Pwned checking   |

<!-- BENCHMARK_START -->
### Performance Benchmarks

Measured on GitHub Actions (Ubuntu, averaged over 10000 iterations):

#### Parsing Performance

| Lines | shelter.nvim | cloak.nvim | camouflage.nvim | Pure Lua | vs cloak | vs camouflage | vs Pure Lua |
|-------|--------------|------------|-----------------|-----------------|----------|---------------|---------|
| 10    | 0.01 ms      | 0.04 ms      | 0.07 ms      | 0.02 ms      | 3.4x faster | 6.4x faster | 1.5x faster |
| 50    | 0.06 ms      | 0.17 ms      | 0.31 ms      | 0.10 ms      | 3.1x faster | 5.7x faster | 1.7x faster |
| 100    | 0.10 ms      | 0.33 ms      | 0.61 ms      | 0.19 ms      | 3.1x faster | 5.9x faster | 1.8x faster |
| 500    | 0.48 ms      | 1.63 ms      | 3.12 ms      | 0.97 ms      | 3.4x faster | 6.4x faster | 2.0x faster |

#### Preview Performance (Telescope)

| Lines | shelter.nvim | cloak.nvim | camouflage.nvim | Pure Lua | vs cloak | vs camouflage | vs Pure Lua |
|-------|--------------|------------|-----------------|-----------------|----------|---------------|---------|
| 10    | 0.01 ms      | 0.04 ms      | 0.07 ms      | 0.02 ms      | 5.6x faster | 10.0x faster | 2.6x faster |
| 50    | 0.02 ms      | 0.17 ms      | 0.31 ms      | 0.09 ms      | 7.3x faster | 13.0x faster | 3.7x faster |
| 100    | 0.04 ms      | 0.34 ms      | 0.61 ms      | 0.20 ms      | 8.5x faster | 15.3x faster | 5.0x faster |
| 500    | 0.18 ms      | 1.66 ms      | 3.14 ms      | 0.97 ms      | 9.2x faster | 17.4x faster | 5.4x faster |

#### Edit Re-masking Performance

| Lines | shelter.nvim | cloak.nvim | camouflage.nvim | Pure Lua | vs cloak | vs camouflage | vs Pure Lua |
|-------|--------------|------------|-----------------|-----------------|----------|---------------|---------|
| 10    | 0.02 ms      | 0.04 ms      | 0.08 ms      | 0.02 ms      | 2.6x faster | 4.8x faster | 1.3x faster |
| 50    | 0.03 ms      | 0.17 ms      | 0.32 ms      | 0.11 ms      | 5.4x faster | 10.0x faster | 3.3x faster |
| 100    | 0.05 ms      | 0.35 ms      | 0.65 ms      | 0.17 ms      | 6.8x faster | 12.8x faster | 3.4x faster |
| 500    | 0.31 ms      | 1.59 ms      | 3.13 ms      | 1.07 ms      | 5.2x faster | 10.2x faster | 3.5x faster |

*Last updated: 2026-02-22*
<!-- BENCHMARK_END -->

### Why So Fast?

- **Rust-Native Parsing** — EDF parsing via LuaJIT FFI, no Lua pattern overhead
- **Line-Specific Re-masking** — Only affected lines are re-processed
- **Zero Debounce** — Instant updates with `nvim_buf_attach`
- **Pre-computed Offsets** — O(1) byte-to-line conversion

### Why Leak-Free?

Unlike cloak.nvim and camouflage.nvim, shelter.nvim is architecturally designed to never expose sensitive values — not even for a single frame. cloak.nvim has an [open issue](https://github.com/laytan/cloak.nvim/issues/25) where values are briefly flashed on file open and when pasting in insert mode. This happens because it relies on event-driven re-cloaking with inherent timing gaps.

shelter.nvim avoids this entirely:

- **Synchronous `nvim_buf_attach`** — Masks are applied in the `on_lines` callback before Neovim renders the next frame, so changed lines are never displayed unmasked
- **Pre-populated cache** — Initial buffer load parses and masks content before the buffer is displayed
- **No debounce** — Re-masking is instant and synchronous, not deferred via timers or `vim.schedule`

This means shelter.nvim is safe for screen sharing, recordings, and any scenario where even a brief flash of a secret is unacceptable.

The benchmarks also include a **Pure Lua** baseline — simple Lua pattern matching with extmarks and full buffer parsing on every change. This represents the best you can physically achieve without a dedicated plugin or separate optimisations. Even this minimal approach is slower than shelter.nvim at scale because it still has to iterate every line in Lua and call into the Neovim API per match. Any future plugin that aims to match shelter.nvim's performance would need to move beyond pure Lua — either via a native binary, SIMD-accelerated parsing, or similarly complex incremental update strategies.

### When to Choose

**Choose shelter.nvim** for dotenv files with maximum performance and features.

**Choose cloak.nvim** for any filetype with minimal setup.

**Choose camouflage.nvim** for multi-format support (JSON, YAML, TOML, etc.) with password breach checking.

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
- **EDF** — File format specification that korni uses to parse `.env` files

## Related Projects

- **[ecolog.nvim](https://github.com/ph1losof/ecolog.nvim)** — LSP-powered environment variable management
- **[ecolog-lsp](https://github.com/ph1losof/ecolog-lsp)** — The Language Server providing env var analysis
- **[ecolog-spec](https://github.com/ph1losof/ecolog-spec)** — EDF Specification
- **[korni](https://github.com/ph1losof/korni)** — Zero-copy `.env` file parser (used internally)

## License

MIT
