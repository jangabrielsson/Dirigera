---------------------------------------------------------------
---  helper functions -----------------------------------------
---------------------------------------------------------------
local fmt = string.format
function printf(...) print(fmt(...)) end
function printc(col,f,...)
  local str = fmt(f,...)
  str = fmt("<font color=%s>%s</font>",col,str)
  print(str)
end

function table.copy(obj)
  if type(obj) == 'table' then
    local res = {}
    for k, v in pairs(obj) do res[k] = table.copy(v) end
    return res
  else
    return obj
  end
end

function DEBUGF(tag,fmt,...)
  if fibaro.debugFlags[tag] then
    print(fmt:format(...))
  end
end

function ERRORF(fmt,...)
  fibaro.error(__TAG,fmt:format(...))
end

local IPaddress = nil
function fibaro.getIPaddress(name)
  if IPaddress then return IPaddress end
  if fibaro._IPaddress then return fibaro._IPaddress
  else
    name = name or ".*"
    local networkdata = api.get("/proxy?url=http://localhost:11112/api/settings/network")
    for n,d in pairs(networkdata.networkConfig or {}) do
      if n:match(name) and d.enabled then IPaddress = d.ipConfig.ip; return IPaddress end
    end
  end
end

function QuickApp:setupStorage()
  local storage,qa = {},self
  function storage:__index(key) return qa:internalStorageGet(key) end
  function storage:__newindex(key,val)
     if val == nil then qa:internalStorageRemove(key)
     else qa:internalStorageSet(key,val,true) end
   end
  return setmetatable({},storage)
end

function urlencode(str)
  if str then
    str = str:gsub("\n", "\r\n")
    str = str:gsub("([^%w %-%_%.%~])", function(c)
      return ("%%%02X"):format(string.byte(c))
    end)
    str = str:gsub(" ", "%%20")
  end
  return str	
end

-- Safe JSON decode for HTTP response bodies. Returns decoded value on success,
-- or nil and logs an error tagged with `name`. Empty body decodes to {}.
function safeDecode(body, name)
  if body == nil or body == "" then return {} end
  local ok, res = pcall(json.decode, body)
  if not ok or res == nil then
    ERRORF("%s: malformed JSON: %s", name or "decode", tostring(body):sub(1,200))
    return nil
  end
  return res
end

---------------------------------------------------------------
---  HTTP GET/PUT ---------------------------------------------
---------------------------------------------------------------

-- Build the standard HTTPClient options table for a Dirigera request.
-- The hub presents a self-signed certificate, so cert validation is
-- disabled here. Treat the hub as trusted-LAN-only.
local function httpOpts(method, body)
  local headers = { ["Authorization"] = "Bearer "..quickApp.store.token }
  if body ~= nil then headers["Content-Type"] = "application/json" end
  return {
    method = method,
    headers = headers,
    data = body,
    timeout = 10000,
    checkCertificate = false,
  }
end

function QuickApp:DGET(url,cb,onError)
  net.HTTPClient():request(Hub.api_base_url..url, {
    options = httpOpts('GET'),
    success = function(response)
      local data = safeDecode(response.data, "DGET "..url)
      if data == nil then if onError then onError("decode") end return end
      cb(data)
    end,
    error = function(err)
      ERRORF("Error get data: %s", err)
      if onError then onError(err) end
    end
  })
end

function QuickApp:DPUT(url,data,cb)
  local fullUrl = Hub.api_base_url..url
  local body = json.encode(data)
  DEBUGF('http',"PATCH: %s %s",fullUrl,body or "")
  net.HTTPClient():request(fullUrl, {
    options = httpOpts('PATCH', body),
    success = function(response)
      if response.status > 204 then
        ERRORF("Error put data: %s", response.status)
        return
      end
      local resp = safeDecode(response.data, "DPUT "..url)
      if resp == nil then return end
      if cb then cb(resp) end
    end,
    error = function(err)
      ERRORF("Error put data: %s %s", err, body)
    end
  })
end

function QuickApp:DPOST(url,data,cb)
  local fullUrl = Hub.api_base_url..url
  local body = data and json.encode(data) or nil
  DEBUGF('http',"POST: %s %s",fullUrl,body or "")
  net.HTTPClient():request(fullUrl, {
    options = httpOpts('POST', body),
    success = function(response)
      if response.status > 204 then
        ERRORF("Error post data: status=%s data=%s", response.status, body or "")
        return
      end
      local resp = safeDecode(response.data, "DPOST "..url)
      if resp == nil then return end
      if cb then cb(resp) end
    end,
    error = function(err)
      ERRORF("Error post data: %s %s", err, body or "")
    end
  })
end

function QuickApp:DDEL(url,data,cb)
  local fullUrl = Hub.api_base_url..url
  local body = data and json.encode(data) or nil
  DEBUGF('http',"DELETE: %s %s",fullUrl,body or "")
  net.HTTPClient():request(fullUrl, {
    options = httpOpts('DELETE', body),
    success = function(response)
      if response.status > 204 then
        ERRORF("Error delete data: status=%s data=%s", response.status, body or "")
        return
      end
      local resp = safeDecode(response.data, "DDEL "..url)
      if resp == nil then return end
      if cb then cb(resp) end
    end,
    error = function(err)
      ERRORF("Error delete data: %s %s", err, body or "")
    end
  })
end

local function round(x) return math.floor(x+0.5) end
function HSV2RGB(h,s,v)
  s = s/100.0
  v = v/100.0
  local c = v*s
  local x = c*(1.0-math.abs((h / 60.0) % 2 - 1))
  local m = v-c
  local rg,gg,bg

  if h < 60 then
    rg,gg,bg = c,x,0
  elseif h < 120 then
    rg,gg,bg = x,c,0
  elseif h < 180 then
    rg,gg,bg = 0,c,x
  elseif h < 240 then
    rg,gg,bg = 0,x,c
  elseif h < 300 then
    rg,gg,bg = x,0,c
  elseif h < 360 then
    rg,gg,bg = c,0,x
  end

  return round((rg+m)*255),round((gg+m)*255),round((bg+m)*255)
end

function RGB2HSV(r,g,b)
  r,g,b = r/255.0,g/255.0,b/255.0
  local M = math.max(r,g,b)
  local m = math.min(r,g,b)
  local C = M-m

  local h,s,v

  if C == 0 then h = 0
  elseif M == r then
    h = ((g-b)/C)%6
  elseif M==g then
    h = (b-r)/C+2
  else 
    h = (r-g)/C+4
  end
  h = h*60
  if h < 0 then h = h+360 end
  v = M
  if v == 0 then s = 0 else s = C/v end
  s = s*100
  v = v*100
  
  return round(h),s,v
end