---@class ShelterUtils
---Utility modules for shelter.nvim
local M = {}

M.env_file = require("shelter.utils.env_file")
M.module_validation = require("shelter.utils.module_validation")
M.pattern_cache = require("shelter.utils.pattern_cache")
M.debounce = require("shelter.utils.debounce")

return M
