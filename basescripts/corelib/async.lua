-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later

-- Async lib for kt. For Lua 5.5
-- Build on top of Qt event loop, but can be easily moved to other event loop system.
-- Can wrap Boost-style async functions, that is, have a callback as its last param
--   which looks like `fun(errCode, value)`.
-- Reference: GameEvent system from `Freekill'.

local co = coroutine
local unpack = table.unpack
local pack = table.pack

local tablib = require "corelib.tablib"

-- private markers
local ASYNC = { "ASYNC" }
local AWAIT = { "AWAIT" }
local AWAIT_GROUP = { "AWAIT_GROUP" }

local CANCELLED = "Operation canceled"

---@alias Awaitable AsyncFunction|CppAsyncFunction
---@alias Resumable AsyncFunction|AwaitGroup

-- AsyncScheduler handles results yielded from an async function.
-- async functions should be started from main coroutine.
local scheduler = {
  ---@type table<thread, AsyncFunction>
  coroutineMap = setmetatable({}, { __mode = "k" }),
}

---@param fn Awaitable
---@param awaiter (AsyncFunction|AwaitGroup)?
function scheduler:startAwaitee(fn, awaiter)
  if fn[ASYNC] then
    ---@cast fn AsyncFunction
    self.coroutineMap[fn.coro] = fn
    if awaiter then fn.caller = awaiter end
    fn.state = "running"
    return self:resume(fn, unpack(fn.args, 1, fn.args.n))
  elseif fn[AWAIT] then
    ---@cast fn CppAsyncFunction
    assert(awaiter ~= nil)
    fn(function(err, v)
      if fn.cancelled or fn.completed then return end
      fn.completed = true
      awaiter.callee = nil
      if err then
        fn.errmsg = err
      else
        fn.results = {v}
      end
      return self:resume(awaiter, fn, not err, err or v)
    end)
  end
end

---@param fn Resumable
function scheduler:resume(fn, ...)
  local _, ret = fn:step(...)
  if ret == nil then return end

  assert(ret[ASYNC] or ret[AWAIT] or ret[AWAIT_GROUP], "unexpected yield result " .. tostring(ret))
  if ret[ASYNC] or ret[AWAIT] then
    return self:startAwaitee(ret, fn)
  elseif ret[AWAIT_GROUP] then
    ---@cast ret AwaitGroup
    return self:resume(ret)
  end
end

---@return AsyncFunction?
function scheduler:current()
  local current = co.running()
  return self.coroutineMap[current]
end

-- await on an Awaitable
-- return true and callback results, or false plus error message
---@param fn Awaitable
---@return boolean, ...
function scheduler:await(fn, ...)
  local f = self:current()
  assert(f, "cannot await outside async function")
  if f.cancelled then
    return false, CANCELLED
  end
  if not (type(fn) == "table" and (fn[ASYNC] or fn[AWAIT])) then
    -- accidentally await on normal functions; return
    return true, fn, ...
  end

  f.callee = fn

  -- will be resumed by scheduler:finish or a callback, and return to caller of await.
  local packed = pack(co.yield(fn))
  table.remove(packed, 1)
  return unpack(packed)
end

---@param fn AsyncFunction
function scheduler:finish(fn)
  self.coroutineMap[fn.coro] = nil
  local a = fn.caller
  if not a then
    if fn.state == "error" and fn.errmsg ~= CANCELLED then
      warn(debug.traceback(fn.coro, fn.errmsg))
    end
    return
  end

  -- async.await(func(...)); resume exection of my caller
  ---@cast a -nil
  a.callee = nil
  if fn.state == "done" then
    return self:resume(a, fn, true, unpack(fn.results, 1, fn.results.n))
  else
    local errmsg = fn.errmsg
    if not fn.cancelled then
      errmsg = debug.traceback(fn.coro, errmsg)
    end
    return self:resume(a, fn, false, errmsg)
  end
end

---@param fn AsyncFunction|CppAsyncFunction
function scheduler:cancel(fn)
  if type(fn) ~= "table" or not (fn[ASYNC] or fn[AWAIT]) then
    return
  end
  if fn.cancelled then return end
  fn.cancelled = true
  -- cancel all callees recursively
  if fn.callee then
    self:cancel(fn.callee)
    fn.callee = nil
  elseif fn.waitGroup then
    fn.waitGroup:cancelAll()
    fn.waitGroup = nil
  end

  if fn[ASYNC] then
    if co.running() == fn.coro then
      -- will make co.resume return false, CANCELLED
      error(CANCELLED)
    elseif fn.state ~= "done" and fn.state ~= "error" then
      -- 不依赖宿主在取消后再回调；主动关闭等待任务，让 GameEvent 的清理链继续执行。
      self:resume(fn)
    end
  elseif fn[AWAIT] and type(fn.cancelFunc) == "function" then
    fn.cancelFunc(CANCELLED)
  end
end

-- Async functions is implemented with a table containing __call metamethod.
-- That table contains useful field for other async related stuff.

--- A running async function.
---@class AsyncFunction
---@field coro thread
---@field args table
---@field state "pending"|"running"|"done"|"error"
---@field results any[]
---@field errmsg string?
---@field caller (AsyncFunction|AwaitGroup)?
---@field callee Awaitable?
---@field cancelled boolean?
---@field waitGroup AwaitGroup?
---@field scope TaskScope?
---@field key any
local AsyncFunction = {}
AsyncFunction.__index = AsyncFunction

function AsyncFunction.new(fn, args)
  local current = co.running()
  return setmetatable({
    [ASYNC] = true,
    coro = co.create(fn),
    args = args,
    caller = scheduler.coroutineMap[current],
    state = "pending",
  }, AsyncFunction)
end

function AsyncFunction:__call()
  return scheduler:startAwaitee(self)
end

function AsyncFunction:step(...)
  local coro = self.coro

  -- when trying to resume a canceled function, finish it immediately
  if self.cancelled then
    self.state, self.errmsg = "error", CANCELLED
    local status = co.status(coro)
    if status == "dead" then
      return
    elseif status == "suspended" then
      co.close(coro)
    end
    scheduler:finish(self)
    return
  end

  -- fn usually call async.await inside it.
  -- awaiting something or finishing exection will make co.resume return.
  local packed = pack(co.resume(coro, ...))
  local status = co.status(coro)
  local ok = packed[1]
  local ret = packed[2]

  if status == "dead" then
    if not ok then
      self.state = "error"
      if ret ~= CANCELLED then
        self.errmsg = ret
      end
    else
      self.state = "done"
      self.results = pack(unpack(packed, 2, packed.n))
    end
    scheduler:finish(self)
    return
  end

  return ok, ret
end

---@class TaskScope
---@field tasks table<AsyncFunction, true>
---@field named table<any, AsyncFunction>
---@field destroyed boolean
local TaskScope = {}
TaskScope.__index = TaskScope

---@return TaskScope
function TaskScope.new()
  return setmetatable({
    tasks = setmetatable({}, { __mode = "k" }),
    named = setmetatable({}, { __mode = "v" }),
    destroyed = false,
  }, TaskScope)
end

---@param fn fun()
---@param key any
function TaskScope:spawn(fn, key)
  assert(not self.destroyed, "cannot spawn a task into a destroyed TaskScope")
  assert(scheduler:current() == nil, "TaskScope:spawn must be called from sync context")

  if key ~= nil then
    local prev = self.named[key]
    assert(prev == nil or prev.state == "done" or prev.state == "error",
      "duplicate task key " .. tostring(key))
  end

  local task = AsyncFunction.new(fn, pack())
  task.scope = self
  task.key = key
  self.tasks[task] = true
  if key ~= nil then self.named[key] = task end
  task()
end

---@param key any
---@return AsyncFunction?
function TaskScope:get(key)
  local task = self.named[key]
  if task and task.state ~= "done" and task.state ~= "error" then
    return task
  end
end

---@param key any
function TaskScope:cancel(key)
  local task = self.named[key]
  if task then
    self.named[key] = nil
    scheduler:cancel(task)
  end
end

function TaskScope:destroy()
  if self.destroyed then return end
  self.destroyed = true
  for task in pairs(self.tasks) do
    scheduler:cancel(task)
  end
end

---@class AsyncFunctionFactory
---@field fn fun(...): any
local AsyncFunctionFactory = {}
AsyncFunctionFactory.__index = AsyncFunctionFactory

function AsyncFunctionFactory.new(fn)
  return setmetatable({
    fn = fn,
  }, AsyncFunctionFactory)
end

function AsyncFunctionFactory:__call(...args)
  local f = AsyncFunction.new(self.fn, args)
  if not scheduler.coroutineMap[co.running()] then
    error("cannot call an async function from sync context; use TaskScope:spawn instead")
  end
  return f
end

---@class CppAsyncFunction
---@field fn fun(...)
---@field args table
---@field results any[]
---@field errmsg string?
---@field cancelFunc fun(err, ...)
---@field cancelled boolean?
local CppAsyncFunction = {}
CppAsyncFunction.__index = CppAsyncFunction

function CppAsyncFunction:__call(cb)
  local args = self.args
  local fn = self.fn
  args.n = args.n + 1
  args[args.n] = cb
  local packed = pack(fn(unpack(args, 1, args.n)))
  self.cancelFunc = packed[1]
end

---@class AwaitGroup
---@field awaiter AsyncFunction
---@field running Awaitable[]
---@field finished Awaitable[]
---@field all Awaitable[]
---@field cancelled boolean
---@field errmsg string
---@field shouldCancel fun(self: AwaitGroup): boolean?
local AwaitGroup = {}
AwaitGroup.__index = AwaitGroup

---@return AwaitGroup
function AwaitGroup.new(cancelFn, tasks)
  return setmetatable({
    [AWAIT_GROUP] = true,

    running = {},
    finished = {},
    all = tasks,

    errmsg = "",

    cancelled = false,
    shouldCancel = cancelFn,
  }, AwaitGroup)
end

function AwaitGroup:step(task)
  if self.cancelled or self.completed then return end
  if task then
    tablib.removeOne(self.running, task)
    self.finished[#self.finished + 1] = task
    if task.errmsg then self.errmsg = self.errmsg .. task.errmsg .. "\n" end
  elseif not self.started then
    self.started, self.starting = true, true
    -- 同步回调也可能完成任务；全部发出前不能恢复父协程，否则会重入正在启动的组。
    for _, pending in ipairs(self.all) do
      self.running[#self.running + 1] = pending
      scheduler:startAwaitee(pending, self)
    end
    self.starting = false
  end
  if self.starting then return end
  if self:shouldCancel() then self:cancelAll() end
  if self.cancelled or #self.finished == #self.all then
    self.completed = true
    scheduler:resume(self.awaiter, self)
  end
end

function AwaitGroup:cancelAll()
  self.cancelled = true
  local running = self.running
  self.running = {}
  for _, task in ipairs(running) do
    scheduler:cancel(task)
    self.finished[#self.finished+1] = task
  end
end

function AwaitGroup:getTask(taskIndex)
  return self.all[taskIndex]
end

function AwaitGroup:getResult(taskIndex)
  local task = self.all[taskIndex]
  if not task or not task.results then return end
  return unpack(task.results, 1, task.results.n or #task.results)
end

---@param cancelFn fun(group: AwaitGroup): boolean?
---@param ... AsyncFunction|CppAsyncFunction
---@return AwaitGroup
function scheduler:awaitGroup(cancelFn, ...)
  local current = co.running()
  local f = self.coroutineMap[current]
  assert(f, "cannot await outside async function")

  local wg = AwaitGroup.new(cancelFn, pack(...))
  wg.awaiter = f
  f.waitGroup = wg

  co.yield(wg)

  f.waitGroup = nil
  return wg
end

--------------------------------------------------------------

local M = {
  CANCELLED = CANCELLED,
}

-- usage: async(function() ... end)
-- creates an asyncFunctionFactory.
---@param fn fun(...): any
---@return fun(...): any
function M.async(fn)
  ---@diagnostic disable-next-line
  return AsyncFunctionFactory.new(fn)
end

---@return TaskScope
function M.newscope()
  return TaskScope.new()
end

--- await for another async func, or wrapped awaitable func.
---@param fn AsyncFunction|CppAsyncFunction
function M.await(fn)
  return scheduler:await(fn)
end

--- cancel an async execution and everything it awaits down the chain.
---@param fn AsyncFunction|CppAsyncFunction
function M.cancel(fn)
  return scheduler:cancel(fn)
end

-- use with function that with callback as last param
-- fn should return immediately
function M.wrap(fn)
  return function(...args)
    return setmetatable({
      [AWAIT] = true,
      fn = fn,
      args = args,
    }, CppAsyncFunction)
  end
end

function M.awaitgroup(cancelFn, ...)
  return scheduler:awaitGroup(cancelFn, ...)
end

function M.awaitall(...)
  return scheduler:awaitGroup(function() end, ...)
end

function M.current()
  return scheduler:current()
end

return M
