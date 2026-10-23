--!nonstrict
-- Cliente mínimo da API v2 do OpenCode.
-- Pareamento, Basic auth, sessões, permissões, formulários e SSE.

local M = {}

local function trim(value)
  return noctalia.string.trim(value or "")
end

function M.parsePairLink(link)
  local value = trim(link)
  local baseUrl, code = value:match("^(https?://[^/%s]+)/auth/connect/([%w_%-]+)")
  if not baseUrl or not code then
    return nil, "Link inválido. Cole o link completo exibido por `opencode pair`."
  end
  return baseUrl, code
end

function M.pair(link, cb)
  local baseUrl, code = M.parsePairLink(link)
  if not baseUrl then
    cb(nil, code)
    return
  end
  noctalia.http({
    url = baseUrl .. "/auth/connect/" .. code,
    method = "GET",
    headers = { "Accept: application/json" },
  }, function(res)
    if not res or res.status ~= 200 then
      local message = "Falha ao parear."
      if res and res.status == 401 then
        message = "Link expirado ou já usado. Rode `opencode pair` novamente."
      elseif res and res.status then
        message = "Falha ao parear (HTTP " .. tostring(res.status) .. ")."
      end
      cb(nil, message)
      return
    end
    local data = noctalia.json.decode(res.body or "")
    if type(data) ~= "table" or type(data.token) ~= "string" or data.token == "" then
      cb(nil, "O servidor não devolveu um token de sessão.")
      return
    end
    cb({ baseUrl = baseUrl, token = data.token })
  end)
end

function M.errorMessage(err)
  if err == nil then
    return "Erro desconhecido."
  end
  if type(err) == "string" then
    return err
  end
  if type(err) == "table" then
    local message = err.message
    if not message and type(err.data) == "table" then
      message = err.data.message
    end
    if not message then
      message = err._tag or err.name
    end
    if type(message) == "string" and message ~= "" then
      if err.status then
        return message .. " (HTTP " .. tostring(err.status) .. ")"
      end
      return message
    end
  end
  return tostring(err)
end

local function encodeBody(body)
  if body == nil then
    return nil
  end
  local ok, encoded = pcall(noctalia.json.encode, body)
  if not ok then
    return nil
  end
  return encoded
end

function M.request(pairing, method, path, body, cb, opts)
  opts = opts or {}
  if type(pairing) ~= "table" or type(pairing.baseUrl) ~= "string" or type(pairing.token) ~= "string" then
    cb(nil, "OpenCode não está pareado.")
    return
  end

  local url = pairing.baseUrl .. path
  if opts.directory and not opts.noDirectory then
    local separator = url:find("?", 1, true) and "&" or "?"
    url = url .. separator .. "directory=" .. noctalia.string.urlEncode(opts.directory)
  end

  local headers = { "Accept: application/json", "Content-Type: application/json" }
  if opts.headers then
    for _, header in ipairs(opts.headers) do
      table.insert(headers, header)
    end
  end

  local request = {
    url = url,
    method = method,
    headers = headers,
    basic_username = "opencode",
    basic_password = pairing.token,
  }
  local encoded = encodeBody(body)
  if encoded then
    request.body = encoded
  end

  noctalia.http(request, function(res)
    if not res then
      cb(nil, "Sem resposta do OpenCode.")
      return
    end
    if res.status == 204 then
      cb(true)
      return
    end

    local data = nil
    if res.body and res.body ~= "" then
      data = noctalia.json.decode(res.body)
    end

    if res.status >= 200 and res.status < 300 then
      cb(data ~= nil and data or true)
      return
    end

    local message = "HTTP " .. tostring(res.status)
    if type(data) == "table" then
      if type(data.message) == "string" then
        message = data.message
      elseif type(data.error) == "string" then
        message = data.error
      elseif type(data.error) == "table" and type(data.error.message) == "string" then
        message = data.error.message
      elseif type(data._tag) == "string" then
        message = data._tag
      end
    end
    cb(nil, { status = res.status, message = message })
  end)
end

function M.health(baseUrl, cb)
  noctalia.http({
    url = baseUrl .. "/global/health",
    method = "GET",
    headers = { "Accept: application/json" },
  }, function(res)
    if not res or res.status ~= 200 then
      cb(false)
      return
    end
    local data = noctalia.json.decode(res.body or "")
    cb(true, type(data) == "table" and data.version or "")
  end)
end

-- Sonda autenticada: valida o servidor e o token de pareamento de uma vez.
-- `/global/health` não exige auth (e em algumas versões responde com o HTML da
-- SPA), então não detecta token expirado nem um servidor ainda aquecendo.
function M.ready(pairing, cb)
  M.request(pairing, "GET", "/api/agent", nil, function(data, err)
    if err then
      cb(false, err)
      return
    end
    cb(true)
  end)
end

function M.listModels(pairing, cb)
  M.request(pairing, "GET", "/api/model", nil, function(data, err)
    if err then
      cb(nil, err)
      return
    end
    cb(type(data) == "table" and data.data or {}, nil)
  end)
end

function M.defaultModel(pairing, cb)
  M.request(pairing, "GET", "/api/model/default", nil, function(data, err)
    if err then
      cb(nil, err)
      return
    end
    cb(type(data) == "table" and data.data or nil, nil)
  end)
end

function M.listAgents(pairing, cb)
  M.request(pairing, "GET", "/api/agent", nil, function(data, err)
    if err then
      cb(nil, err)
      return
    end
    cb(type(data) == "table" and data.data or {}, nil)
  end)
end

function M.listSessions(pairing, directory, cb)
  M.request(pairing, "GET", "/api/session?limit=50&order=desc", nil, function(data, err)
    if err then
      cb(nil, err)
      return
    end
    cb(type(data) == "table" and data.data or {}, nil)
  end, { directory = directory })
end

function M.createSession(pairing, directory, body, cb)
  M.request(pairing, "POST", "/api/session", body, function(data, err)
    if err then
      cb(nil, err)
      return
    end
    cb(type(data) == "table" and data.data or nil, nil)
  end, { directory = directory })
end

local function sessionPath(id, suffix)
  return "/api/session/" .. noctalia.string.urlEncode(id) .. (suffix or "")
end

function M.context(pairing, directory, id, cb)
  M.request(pairing, "GET", sessionPath(id, "/context"), nil, function(data, err)
    if err then
      cb(nil, err)
      return
    end
    cb(type(data) == "table" and data.data or {}, nil)
  end, { directory = directory })
end

function M.prompt(pairing, directory, id, text, cb)
  M.request(pairing, "POST", sessionPath(id, "/prompt"), { text = text }, function(_, err)
    if err then
      cb(nil, err)
      return
    end
    cb(true)
  end, { directory = directory })
end

function M.interrupt(pairing, directory, id, cb)
  M.request(pairing, "POST", sessionPath(id, "/interrupt"), nil, function(_, err)
    if err then
      cb(nil, err)
      return
    end
    cb(true)
  end, { directory = directory })
end

function M.setModel(pairing, directory, id, model, cb)
  M.request(pairing, "POST", sessionPath(id, "/model"), { model = model }, function(_, err)
    if err then
      cb(nil, err)
      return
    end
    cb(true)
  end, { directory = directory })
end

function M.setAgent(pairing, directory, id, agent, cb)
  M.request(pairing, "POST", sessionPath(id, "/agent"), { agent = agent }, function(_, err)
    if err then
      cb(nil, err)
      return
    end
    cb(true)
  end, { directory = directory })
end

function M.renameSession(pairing, directory, id, title, cb)
  M.request(pairing, "PATCH", sessionPath(id), { title = title }, function(_, err)
    if err then
      cb(nil, err)
      return
    end
    cb(true)
  end, { directory = directory })
end

function M.deleteSession(pairing, directory, id, cb)
  M.request(pairing, "DELETE", sessionPath(id), nil, function(_, err)
    if err then
      cb(nil, err)
      return
    end
    cb(true)
  end, { directory = directory })
end

function M.listPermissions(pairing, directory, id, cb)
  M.request(pairing, "GET", sessionPath(id, "/permission"), nil, function(data, err)
    if err then
      cb(nil, err)
      return
    end
    cb(type(data) == "table" and data.data or {}, nil)
  end, { directory = directory })
end

function M.replyPermission(pairing, directory, id, requestID, decision, cb)
  local path = sessionPath(id, "/permission/" .. noctalia.string.urlEncode(requestID) .. "/reply")
  M.request(pairing, "POST", path, { decision = decision }, function(_, err)
    if err then
      cb(nil, err)
      return
    end
    cb(true)
  end, { directory = directory })
end

function M.listForms(pairing, directory, id, cb)
  M.request(pairing, "GET", sessionPath(id, "/form"), nil, function(data, err)
    if err then
      cb(nil, err)
      return
    end
    cb(type(data) == "table" and data.data or {}, nil)
  end, { directory = directory })
end

function M.replyForm(pairing, directory, id, formID, answer, cb)
  local path = sessionPath(id, "/form/" .. noctalia.string.urlEncode(formID) .. "/reply")
  M.request(pairing, "POST", path, { answer = answer }, function(_, err)
    if err then
      cb(nil, err)
      return
    end
    cb(true)
  end, { directory = directory })
end

function M.exportSession(pairing, directory, id, cb)
  local path = "/api/experimental/session/" .. noctalia.string.urlEncode(id) .. "/export?sanitize=false"
  M.request(pairing, "GET", path, nil, function(data, err)
    if err then
      cb(nil, err)
      return
    end
    cb(type(data) == "table" and data.data or nil, nil)
  end, { directory = directory })
end

function M.streamEvents(pairing, onEvent, onClose)
  if type(pairing) ~= "table" or type(pairing.baseUrl) ~= "string" then
    return nil
  end
  return noctalia.httpStream({
    url = pairing.baseUrl .. "/api/event",
    method = "GET",
    headers = { "Accept: text/event-stream" },
    basic_username = "opencode",
    basic_password = pairing.token,
  }, function(line)
    local payload = line and line:match("^data:%s*(.*)$")
    if not payload or payload == "" then
      return
    end
    local event = noctalia.json.decode(payload)
    if type(event) == "table" and type(event.type) == "string" then
      onEvent(event)
    end
  end, onClose)
end

return M
