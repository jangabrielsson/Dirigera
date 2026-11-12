---------------------------------------------------------------
---  Authorization --------------------------------------------
---------------------------------------------------------------
local fmt = string.format
sha = sha
local function codeChallenge(codeVerifier)
  local hash = sha.sha256(codeVerifier)
  local binhash = sha.hex2bin(hash)
  local base64hash = sha.bin2base64(binhash)
  -- RFC 7636: base64url, no padding.
  base64hash = base64hash:gsub('+','-'):gsub('/','_'):gsub('=+$','')
  return base64hash
end

local function getToken(IP, code, codeVerifier, cb)
  local data = 
  "code="..urlencode(code)
  .."&name="..urlencode("127.0.0.1") ---fibaro.getIPaddress()
  .."&grant_type=authorization_code"
  .."&code_verifier="..urlencode(codeVerifier)
  local headers = { 
    ['Content-Type'] = "application/x-www-form-urlencoded;charset=UTF-8",
    --['Content-Length'] = #data
    --["Accept"] = "application/json"
  }
  local tokenURL = fmt("https://%s:%s/v1/oauth/token",IP,Hub.port)
  -- print(code)
  -- print(data)
  net.HTTPClient():request(tokenURL, {
    options = {
      method = 'POST',
      headers = headers,
      data = data,
      timeout = 10000,
      checkCertificate = false
    },
    success = function(response)
      local stat,res = pcall(json.decode,response.data)
      if not stat or res == nil then
        ERRORF("Error get token: %s ", json.encode(response))
        return
      end
      local data = res
      if not data.access_token then
        ERRORF("No access_token in response: %s", json.encode(data))
        return
      end
      cb(data.access_token)
    end,
    error = function(err)
      ERRORF("Error get token: %s", err)
    end
  })
end

local function sendChallenge(IP, codeVerifier)
  local authUrl = fmt("https://%s:%s/v1/oauth/authorize",IP,Hub.port)
  local params = "?audience=homesmart.local&response_type=code&code_challenge=%s&code_challenge_method=S256"
  local cc = codeChallenge(codeVerifier)
  params = fmt(params, cc)
  Hub.lastRequest = nil
  net.HTTPClient():request(authUrl..params, {
    options = {
      method = 'GET',
      headers = {
      },
      checkCertificate = false,
      timeout = 10000
    },
    success = function(response)
      local data = safeDecode(response.data, "sendChallenge")
      if data == nil then 
        ERRORF("Error requesting token: %s", json.encode(response))
        return
      end
      print("Press the action button on the bottom of the Dirigera hub, then press QA button 'Get token'' ..." )
      Hub.lastRequest = { IP=IP, codeVerifier=codeVerifier, code=data.code}
      --getToken(IP, data.code, codeVerifier, cb)
    end,
    error = function(err)
      ERRORF("Error requesting token: %s", err)
    end
  })
end

function QuickApp:requestToken()
  local randomCode = {}
  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
  for i=1,128 do
    local n = math.random(1, #chars)
    randomCode[#randomCode+1] = chars:sub(n, n)
  end
  local codeVerifier = table.concat(randomCode)
  DEBUGF('test',"verifier len=%d",#codeVerifier)
  sendChallenge(Hub.IP, codeVerifier)
end

function QuickApp:getToken()
  local lastRequest = Hub.lastRequest
  if not lastRequest then
    ERRORF("No last request")
    return
  end
  getToken(Hub.lastRequest.IP, lastRequest.code, lastRequest.codeVerifier, function(token)
    DEBUGF('test',"Token received (prefix=%s…, len=%d)",token:sub(1,6),#token)
    self.store.token = token
    plugin.restart()
  end)
end
