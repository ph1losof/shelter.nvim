-- Tests for shelter.cache.lru module
-- Run with: nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/plenary/cache_spec.lua"

local lru = require("shelter.cache.lru")

describe("shelter.cache.lru", function()
  describe("new", function()
    it("creates a new LRU cache with specified capacity", function()
      local cache = lru.new(10)
      assert.is_table(cache)
      assert.equals(10, cache.max_size)
    end)

    it("uses default capacity when not specified", function()
      local cache = lru.new()
      assert.is_table(cache)
      assert.is_true(cache.max_size > 0)
    end)
  end)

  describe("put and get", function()
    it("stores and retrieves values", function()
      local cache = lru.new(10)
      cache:put("key1", "value1")
      assert.equals("value1", cache:get("key1"))
    end)

    it("returns nil for missing keys", function()
      local cache = lru.new(10)
      assert.is_nil(cache:get("nonexistent"))
    end)

    it("overwrites existing values", function()
      local cache = lru.new(10)
      cache:put("key", "old")
      cache:put("key", "new")
      assert.equals("new", cache:get("key"))
    end)

    it("stores table values correctly", function()
      local cache = lru.new(10)
      local value = { a = 1, b = 2 }
      cache:put("key", value)
      local retrieved = cache:get("key")
      assert.equals(1, retrieved.a)
      assert.equals(2, retrieved.b)
    end)
  end)

  describe("eviction", function()
    it("evicts oldest entries when capacity is exceeded", function()
      local cache = lru.new(3)
      cache:put("a", 1)
      cache:put("b", 2)
      cache:put("c", 3)
      cache:put("d", 4) -- Should evict "a"

      assert.is_nil(cache:get("a"))
      assert.equals(2, cache:get("b"))
      assert.equals(3, cache:get("c"))
      assert.equals(4, cache:get("d"))
    end)

    it("updates recency on get", function()
      local cache = lru.new(3)
      cache:put("a", 1)
      cache:put("b", 2)
      cache:put("c", 3)

      -- Access "a" to make it recently used
      cache:get("a")

      -- Add new entry, should evict "b" (oldest unused)
      cache:put("d", 4)

      assert.equals(1, cache:get("a")) -- Still present
      assert.is_nil(cache:get("b")) -- Evicted
      assert.equals(3, cache:get("c"))
      assert.equals(4, cache:get("d"))
    end)
  end)

  describe("clear", function()
    it("removes all entries", function()
      local cache = lru.new(10)
      cache:put("a", 1)
      cache:put("b", 2)
      cache:put("c", 3)

      cache:clear()

      assert.is_nil(cache:get("a"))
      assert.is_nil(cache:get("b"))
      assert.is_nil(cache:get("c"))
    end)

    it("resets size to zero", function()
      local cache = lru.new(10)
      cache:put("a", 1)
      cache:put("b", 2)

      cache:clear()

      assert.equals(0, cache.size)
    end)
  end)

  describe("size tracking", function()
    it("tracks size correctly on put", function()
      local cache = lru.new(10)
      assert.equals(0, cache.size)

      cache:put("a", 1)
      assert.equals(1, cache.size)

      cache:put("b", 2)
      assert.equals(2, cache.size)
    end)

    it("does not increment size on overwrite", function()
      local cache = lru.new(10)
      cache:put("key", "old")
      local size_before = cache.size

      cache:put("key", "new")
      assert.equals(size_before, cache.size)
    end)
  end)

  describe("performance", function()
    it("handles many entries efficiently", function()
      local cache = lru.new(1000)

      -- Insert 1000 entries
      for i = 1, 1000 do
        cache:put("key" .. i, "value" .. i)
      end

      -- All should be retrievable
      for i = 1, 1000 do
        assert.equals("value" .. i, cache:get("key" .. i))
      end
    end)

    it("handles rapid put/get cycles", function()
      local cache = lru.new(100)

      for _ = 1, 10000 do
        local key = "key" .. math.random(200)
        cache:put(key, math.random())
        cache:get(key)
      end

      -- Should not error and size should be at capacity
      assert.equals(100, cache.size)
    end)
  end)
end)
