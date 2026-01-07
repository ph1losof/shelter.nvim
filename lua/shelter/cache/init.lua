---@class ShelterCache
---Cache management module
local M = {}

local lru = require("shelter.cache.lru")

M.LRU = lru

return M
