---@class ShelterLRUCache
---O(1) LRU cache using doubly-linked list with hash map
---All operations (get, put, remove) are O(1)
local M = {}
M.__index = M

---@class LRUNode
---@field key any
---@field value any
---@field prev LRUNode|nil
---@field next LRUNode|nil

---Create a new LRU cache
---@param max_size number Maximum number of entries
---@return ShelterLRUCache
function M.new(max_size)
	local self = setmetatable({}, M)
	self.max_size = max_size or 100
	self.size = 0

	-- Hash map: key -> node (O(1) lookup)
	self.cache = {}

	-- Sentinel nodes for O(1) list operations
	-- Using sentinels avoids nil checks in hot paths
	self.head = { key = nil, value = nil, prev = nil, next = nil }
	self.tail = { key = nil, value = nil, prev = nil, next = nil }
	self.head.next = self.tail
	self.tail.prev = self.head

	return self
end

---Remove a node from the linked list (O(1))
---@param node LRUNode
local function unlink_node(node)
	local prev = node.prev
	local next = node.next
	prev.next = next
	next.prev = prev
end

---Insert node right after head (most recently used) (O(1))
---@param self ShelterLRUCache
---@param node LRUNode
local function link_after_head(self, node)
	local head_next = self.head.next
	self.head.next = node
	node.prev = self.head
	node.next = head_next
	head_next.prev = node
end

---Get a value from the cache (O(1))
---@param key any
---@return any|nil
function M:get(key)
	local node = self.cache[key]
	if not node then
		return nil
	end

	-- Move to front (most recently used)
	unlink_node(node)
	link_after_head(self, node)

	return node.value
end

---Put a value in the cache (O(1))
---@param key any
---@param value any
function M:put(key, value)
	local node = self.cache[key]

	if node then
		-- Update existing: update value and move to front
		node.value = value
		unlink_node(node)
		link_after_head(self, node)
	else
		-- Create new node
		node = {
			key = key,
			value = value,
			prev = nil,
			next = nil,
		}

		-- Add to cache and list
		self.cache[key] = node
		link_after_head(self, node)
		self.size = self.size + 1

		-- Evict LRU if over capacity
		if self.size > self.max_size then
			-- Remove from tail (least recently used)
			local lru_node = self.tail.prev
			if lru_node ~= self.head then
				unlink_node(lru_node)
				self.cache[lru_node.key] = nil
				self.size = self.size - 1
			end
		end
	end
end

---Check if key exists (O(1))
---@param key any
---@return boolean
function M:has(key)
	return self.cache[key] ~= nil
end

---Remove a specific key (O(1))
---@param key any
---@return boolean removed
function M:remove(key)
	local node = self.cache[key]
	if not node then
		return false
	end

	unlink_node(node)
	self.cache[key] = nil
	self.size = self.size - 1
	return true
end

---Clear all entries (O(1))
function M:clear()
	self.cache = {}
	self.head.next = self.tail
	self.tail.prev = self.head
	self.size = 0
end

---Get current size (O(1))
---@return number
function M:get_size()
	return self.size
end

---Iterate over all entries from most to least recently used
---@return function iterator
function M:iter()
	local node = self.head
	return function()
		node = node.next
		if node ~= self.tail then
			return node.key, node.value
		end
		return nil
	end
end

return M
