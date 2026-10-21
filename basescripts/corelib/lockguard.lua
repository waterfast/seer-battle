-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later

-- Mutex lib for ktabletop, work on Lua 5.4+
-- Providing something like std::lock_guard that release the lock in RAII manner,
-- using the to-be-closed local variable feature introduced by Lua 5.4
-- See the example at end of this file.

local async = require "corelib.async"
local co = coroutine
local tablib = require "corelib.tablib"

local function lock(mu)
  local owner = co.running()
  if not mu.locked then
    mu.locked, mu.owner = true, owner
    return
  end

  -- I don't think I will write topological sorting for full deadlock detection
  assert(mu.owner ~= owner, "Mutex: deadlock detected")

  local entry = { owner = owner }
  mu[#mu + 1] = entry
  async.await(async.wrap(function(cb)
    entry.cb = cb

    -- cancel of acquiring lock: remove from queue
    return function()
      tablib.removeOne(mu, entry)
    end
  end)())
end

local function unlock(mu)
  if not mu.locked then return end
  local owner = co.running()
  if mu.owner ~= owner then
    kt.log.warn("unlocking mutex from another coroutine")
  end

  local entry = table.remove(mu, 1)
  if entry then
    -- keep locked = true here. another Mutex:lock() is returned by calling cb()
    mu.owner = entry.owner
    entry.cb()
  else
    mu.locked, mu.owner = nil, nil
  end
end

local mt = { __close = unlock }

do return function(mutex)
  lock(mutex)
  return setmetatable(mutex, mt)
end end

------------------------------------------------------------------------------------
-- note: file has ended here. Below is example code explaining how to use this lib
------------------------------------------------------------------------------------

-- Define a mutex by just create an empty table. it will be used as the waiting queue.
local mutex = {}
local lockguard = require "corelib.lockguard"

-- In your code:
local function foo()
  -- WARN: lock guard MUST be a to-be-closed value!!! DO NOT FORGET THE <close> ATTRIBUTE!
  local guard <close> = lockguard(mutex)
  -- do something...
end

foo()
