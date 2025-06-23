List = {}
List.__index = List

-- Constructor
function List.new()
  return setmetatable({ first = 0, last = -1 }, List)
end

-- Adds an element to the end of the list (similar to JavaScript's push)
-- Returns the new size of the list
function List:push(value)
  local last = self.last + 1
  self.last = last
  self[last] = value
  return self:size()   -- Return new length
end

-- Removes and returns the last element of the list (similar to JavaScript's pop)
function List:pop()
  if self:isEmpty() then
    error("List is empty")
  end
  local last = self.last
  local value = self[last]
  self[last] = nil   -- Allow garbage collection
  self.last = last - 1
  return value
end

-- Adds an element to the beginning of the list (similar to JavaScript's unshift)
-- Returns the new size of the list
function List:unshift(value)
  local first = self.first - 1
  self.first = first
  self[first] = value
  return self:size()   -- Return new length
end

-- Removes and returns the first element of the list (similar to JavaScript's shift)
function List:shift()
  if self:isEmpty() then
    error("List is empty")
  end
  local first = self.first
  local value = self[first]
  self[first] = nil   -- Allow garbage collection
  self.first = first + 1
  return value
end

-- Checks if the list is empty
function List:isEmpty()
  return self.first > self.last
end

-- Get the head
function List:head()
  return self[self.first]
end

-- Get the tail
function List:tail()
  return self[self.last]
end

-- Completely wipe out a table, recursively.
local function clear_table(t)
  for k in pairs(t) do
    if type(k) == "table" then
      clear_table(k)
    else
      t[k] = nil
    end
  end
end

-- Clear the list
function List:clear()
  clear_table(self)
  self.first = 0
  self.last = -1
end

-- Returns the current size of the list
function List:size()
  return self.last - self.first + 1
end

function List:index_of(value)
  for i = self.first, self.last do
    if self[i] == value then
      return i
    end
  end
  return nil
end

function List:get(index)
  return self[self.first + index]
end

-- Iterates over the list in order
function List:iterator()
  local i = self.first - 1
  return function()
    i = i + 1
    if i > self.last then return nil end
    return self[i]
  end
end

-- Define the __ipairs metamethod for Lua 5.3 and earlier
function List.__ipairs(list)
  -- Define an iterator that returns (index, value) pairs starting from 1
  local function list_ipairs_iterator(t, i)
    i = i + 1
    if i > t.last - t.first + 1 then
      return nil
    else
      return i, t[t.first + i - 1]
    end
  end
  return list_ipairs_iterator, list, 0
end

-- Modify the List class to include a generic for loop-compatible iterator for Lua 5.4 and later
function List:ipairs_custom()
  local i = self.first - 1
  return function()
    i = i + 1
    if i > self.last then return nil end
    return i - self.first + 1, self[i]
  end
end

-- Set the __ipairs metamethod in the metatable (effective in Lua 5.3 and earlier)
setmetatable(List, {
  __index = List,
  __ipairs = List.__ipairs   -- Lua 5.4 will ignore this

})

--[[
print("Iterating with built-in ipairs (Lua 5.3 and earlier):")
for index, value in ipairs(myList) do
  print(index, value)
end

print("\nIterating with custom iterator (Lua 5.4 and later):")
for index, value in myList:ipairs_custom() do
  print(index, value)
end
]]
