--[[
Dirigera connectivity for the Fibaro Home Center 3
Copyright (c) 2021 Jan Gabrielsson
Email: jan@gabrielsson.com
GNU GENERAL PUBLIC LICENSE
Version 3, 29 June 2007

Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
Everyone is permitted to copy and distribute verbatim copies
of this license document, but changing it is not allowed.

SHA 256 library from @tinman
--]]

--%%name:Dirigera
-- %%save:Dirigera.fqa
-- %%proxy:true
--%%type:com.fibaro.deviceController
--%%var:debug="http=true"
-- %%port=8269
--%%u:{label="titelLabel",text="Dirigera"}
--%%u:{{button="b1",text="Request token",visible=true,onReleased="requestToken"},{button="b2",text="Get token",visible=true,onReleased="getToken"}}
--%%u:{{button="b3",text="List device info",visible=true,onReleased="listDeviceInfo"},{button="b4",text="Restart",visible=true,onReleased="restartQA"}}
--%%u:{multi="select_ID_4",text="Devices",visible=true,onToggled="selectDevices",options={}}

--%%file:$sha2.lua,sha2
--%%file:$qwikchild.lua,Qwik
--%%file:Lib.lua,Lib
--%%file:Devices.lua,Devices
--%%file:Auth.lua,Auth
--%%var:IP="192.168.50.165"

--%%mode:offline
--%%var:refresh=false

local VERSION = "0.1.6"
DG = DG or { childs = {}}
local TOKEN = os.getenv and os.getenv("DIRIGERA_token") or nil

---------------------------------------------------------------
---  local variables ------------------------------------------
---------------------------------------------------------------
Hub = {
  IP = nil,
  port = "8443",
  api_version = "v1",
  api_base_url = nil,
  lastRequest = nil
}
local fmt = string.format
fibaro.debugFlags = fibaro.debugFlags or { }

local MessageHandler = {}
function MessageHandler.deviceStateChanged(data)
  local d = DG.devices.id[data.data.id]
  if d and d.object then d.object:change(data.data) end
end
function MessageHandler.sceneUpdated(data)
  print("SCENE",data.data.info.name)
end

function QuickApp:restartQA()
  printc("red","Restarting QuickApp...")
  plugin.restart()
end

function QuickApp:listDeviceInfo()
  local pr = function(...) printc("yellow",...) end
  for _,dev in pairs(DG.devices.id) do
    local d = dev.object
    local a = d.attributes
    pr("%s '%s' %s",d.deviceType,d.name,d.id)
    pr("model:%s",a.model or "")
    pr("manufacturer:%s",a.manufacturer or "")
    pr("firmware:%s",a.firmwareVersion or "")
    pr("hardware:%s",a.hardwareVersion or "")
    pr("----------------------------------")
  end
end

function QuickApp:removeChildren()
  for id,_ in pairs(self.childDevices or {}) do self:removeChildDevice(id) end
end

function QuickApp:listen()
  DEBUGF('test',"Websocket connect")
  local url = fmt("wss://%s:%s/%s",Hub.IP,Hub.port,Hub.api_version)
  local headers = {
    ["Authorization"] = "Bearer "..self.store.token
  }
  self._wsBackoff = self._wsBackoff or 5
  self._wsLastError = nil
  local function reconnect()
    if self._wsReconnectScheduled then return end
    self._wsReconnectScheduled = true
    local delay = self._wsBackoff
    self:warning(fmt("WebSocket disconnected (%s) - reconnect in %ds",
      self._wsLastError or "no error", delay))
    self._wsBackoff = math.min(self._wsBackoff * 2, 60)
    setTimeout(function()
      self._wsReconnectScheduled = false
      self:listen()
    end, delay * 1000)
  end
  local function handleConnected()
    DEBUGF('test',"Connected")
    self._wsBackoff = 5 -- reset backoff on successful connect
    self._wsLastError = nil
  end
  local function handleDisconnected()
    DEBUGF('test',"Disconnected")
    reconnect()
  end
  local function handleError(err)
    ERRORF("WebSocket error: %s", err)
    self._wsLastError = tostring(err)
    reconnect()
  end
  local function handleDataReceived(data)
    --print(data)
    data = safeDecode(data, "WebSocket")
    if data == nil then return end
    local handler  = MessageHandler[data.type or ""]
    if handler then handler(data) 
    else
      DEBUGF('test',"Unknown message type: %s",data.type)
    end
  end
  self.sock = net.WebSocketClientTls()
  self.sock:addEventListener("connected", handleConnected)
  self.sock:addEventListener("disconnected", handleDisconnected)
  self.sock:addEventListener("error", handleError)
  self.sock:addEventListener("dataReceived", handleDataReceived) 
  
  DEBUGF('test',"Connect: %s",url)
  self.sock:connect(url, headers)
end

function QuickApp:onInit()
  quickApp = self
  print("Dirigera version:",VERSION)
  self:updateView("titelLabel","text","Dirigera v"..VERSION)
  function self.initChildDevices() end
  local dbgs = self:getVariable("debug")
  dbgs:gsub("(%w+)=([FfAaLlSsEeTtRrUu]+)",function(f,v) 
    v = v:lower()
    if v == "true" then fibaro.debugFlags[f] = true elseif v == "false" then fibaro.debugFlags[f] = false end
  end)
  self.store = self:setupStorage()
  Hub.IP = self:getVariable("IP")
  if Hub.IP == "" then
    self:warning("Please set IP address of Dirigera")
    return
  end
  Hub.api_base_url = fmt("https://%s:%s/%s",Hub.IP,Hub.port,Hub.api_version)
  self:defineClasses()
  if TOKEN then self.store.token = TOKEN end
  if self.store.token == nil then
    print("Please Request & Get token...")
    print("Start by pressing QA button 'Request token'")
    return
  else
    print("Token stored.")
  end
  local devices = self.store.devices
  if devices == nil then
    local chs = api.get("/devices?parentId="..self.id) or {}
    devices = {}
    for _,child in ipairs(chs) do devices[child.id] = true end
  end
  self.store.devices = devices

  -- Bootstrap chain: GET /devices -> /scenes -> /home, then init children
  -- and start the WebSocket. On any failure, surface on the title label and
  -- retry the whole chain with exponential backoff (capped at 60s).
  self._initBackoff = 5
  local function bootstrap()
    local function onError(stage, err)
      local delay = self._initBackoff
      local msg = fmt("Init failed at %s (%s) - retry in %ds", stage, tostring(err), delay)
      ERRORF("%s", msg)
      self:updateView("titelLabel","text","Dirigera v"..VERSION.." - "..msg)
      self._initBackoff = math.min(self._initBackoff * 2, 60)
      setTimeout(bootstrap, delay * 1000)
    end
    self:DGET("/devices",function(ddata)
      local oldDevices = table.copy(devices)
      devices = {}
      for _,d in ipairs(ddata) do
        devices[d.id] = oldDevices[d.id] or false
        DG:addDevice(d)
      end
      self.store.devices = devices
      self:populateDeviceSelector()
      self:DGET("/scenes",function(sdata)
        for _,d in ipairs(sdata) do
          DG:addScene(d)
        end
        local function filter(ds,df)
          -- Map each child id back to its parent device id (selection map key).
          -- Most children use the bare device id, but AirSensor sub-children use
          -- '<id>_pm25', '<id>_voc', '<id>_temp'. Try the id directly, then strip
          -- the last '_<suffix>' segment and retry.
          local res = {}
          for id,d in pairs(ds) do
            local base = id:match("^(.-)_[^_]+$")
            if df[id] or (base and df[base]) then res[id] = d end
          end
          return res
        end
        self:DGET("/home",function(hdata)
          local hub = DG.devices.type['gateway']
          if hub then
            local attr = hub.attributes
            printf("Gateway: %s",attr.customName or "")
            printf("model:%s",attr.model)
            printf("firmware:%s",attr.firmwareVersion)
            printf("hardware:%s",attr.hardwareVersion)
          end
          self._initBackoff = 5 -- reset backoff after full success
          self:updateView("titelLabel","text","Dirigera v"..VERSION)
          quickApp:initChildren(filter(DG.childs,devices))
          DG:linkDevices()
          quickApp:listen()
        end, function(err) onError("/home", err) end)
      end, function(err) onError("/scenes", err) end)
    end, function(err) onError("/devices", err) end)
  end
  bootstrap()
end

function QuickApp:populateDeviceSelector()
  local options = {}
  local values = {}
  local devices = self.store.devices
  for id,d in pairs(DG.childs) do
    local dev = DG.devices.id[id]
    if dev then 
      local name = d.name or ""
      if name == "" then name = "<noname>" end
      name = string.format("%s (%s)",name,dev.attributes.model)
      local i = {text=name,type="option",value=id}
      table.insert(options,i)
      if devices[id] then table.insert(values,id) end
    end
  end
  table.sort(options,function(a,b) return a.text < b.text end)
  self:updateView("select_ID_4","options",options)
  self:updateView("select_ID_4","selectedItems",values)
end

function QuickApp:selectDevices(data)
  local devices = self.store.devices
  for id,_ in pairs(devices) do devices[id] = false end
  for _,d in pairs(data.values[1]) do
    devices[d] = true
  end
  self.store.devices = devices
end
