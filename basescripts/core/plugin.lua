local class = kt.class

-- stores meta info for every plugins.
---@class Plugin: Object
---@field path string
---@field env table plugin-private global environment
---@field i18nContext I18nContext
local Plugin = class("Plugin")

function Plugin:initialize(path)
  self.path = path
  -- per-plugin sandbox: reads fall through to the real globals, writes stay here
  self.env = setmetatable({}, { __index = _G })
  self.env._G = self.env
end

return Plugin
