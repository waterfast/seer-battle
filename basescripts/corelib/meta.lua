-- Helpers for LSP
do return end

---@meta

---@class class
---@field public static any
--- middleclass
local class = {}

---@param cls class|Object
---@return boolean
function class:isSubclassOf(cls) end

---@class Object
---@field public class class
local Object = { static = {} }

---@generic T
---@param self T
function Object:initialize(...) end

---@generic T
---@param self T
---@return T
function Object:new(...)end

---@generic T
---@param self T
---@param name string
---@return T
function Object:subclass(name)end

---@param cls class|Object
---@return boolean
function Object:isInstanceOf(cls) end

---@param cls class|Object
---@return boolean
function Object:isSubclassOf(cls) end

function Object:include(e) end

---@class LObject: Object
local LObject = {}

--- STATIC METHOD: register property to the class
---@param key string
---@param opts PropertyOpts?
function LObject:Property(key, opts) end

--- STATIC METHOD: register invokable to the class
---@param key string
function LObject:Invokable(key) end

--- STATIC METHOD: register signal to the class
---@param key string
function LObject:Signal(key) end

---@class ktabletop
kt = {}
kt.c = {}
kt.log = {
  info = function(...) end,
  warn = function(...) end,
  debug = function(...) end,
  critical = function(...) end,
}

---@class I18nContext
local I18nContext = {
  i18n = function(text, ...) end,
  i18nc = function(context, text, ...) end,
  i18np = function(singular, plural, ...) end,
  i18ncp = function(context, singular, plural, ...) end,
}
