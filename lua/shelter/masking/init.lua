---@class ShelterMasking
---Masking module entry point
local M = {}

local engine = require("shelter.masking.engine")
local modes = require("shelter.modes")

-- Engine functions
M.parse_content = engine.parse_content
M.determine_mode = engine.determine_mode
M.mask_value = engine.mask_value
M.generate_masks = engine.generate_masks
M.generate_masks_incremental = engine.generate_masks_incremental
M.clear_caches = engine.clear_caches
M.init = engine.init
M.reload_patterns = engine.reload_patterns

-- Direct access to modes module
M.modes = modes

return M
