--!nonstrict
-- Serviço do omyfedora AI Chat.
-- Dono do pareamento, da conexão SSE, do estado da conversa e da persistência.

local api = require("./lib/api.luau")
local store = require("./lib/store.luau")
local format = require("./lib/format.luau")

local directory = "~/.omyfedora-ai-chat"
local agentId = "omyfedora-chat"
local autoPair = true
local autoExport = true
local notifyOnFinish = true
local maxToolOutput = 4000

local pairing = nil
local models = {}
local agents = {}
local sessions = {}
local activeSession = nil
local preferredModel = nil
local messages = {}
local pendingPermissions = {}
local pendingForms = {}
local toolNames = {}

local status = "unpaired"
local statusMessage = ""
local errorMessage = ""
local busy = false
local unread = false
local runActive = false
local panelOpen = false
local agentMissing = false

local revision = 0
local dirty = false
local lastPublish = 0
local lastHealthCheck = 0

local stream = nil
local streamGeneration = 0
local reconnectAt = 0
local reconnectAttempt = 0
local generation = 0

local publish
local schedulePublish
local checkHealth
local loadCatalog
local loadSessions
local connectSse
local selectSession
local createSession
local sendPrompt
local sendPromptTo
local finishRun
local exportSession
local refreshContext
local handleEvent
local onPaired
local doPair

local function decode(payload)
  if type(payload) ~= "string" or payload == "" then
    return {}
  end
  local value = noctalia.json.decode(payload)
  if type(value) == "table" then
    return value
  end
  return {}
end

local function findSession(id)
  for _, session in ipairs(sessions) do
    if session.id == id then
      return session
    end
  end
  return nil
end

local function findTool(id)
  for _, message in ipairs(messages) do
    for _, tool in ipairs(message.tools or {}) do
      if tool.id == id then
        return tool
      end
    end
  end
  return nil
end

local function lastAssistant()
  for i = #messages, 1, -1 do
    if messages[i].role == "assistant" then
      return messages[i]
    end
  end
  return nil
end

local function ensureAssistant(id)
  for _, message in ipairs(messages) do
    if message.role == "assistant" and message.id == id then
      return message
    end
  end
  local message = {
    id = id,
    role = "assistant",
    text = "",
    reasoning = "",
    tools = {},
    streaming = true,
    error = "",
  }
  table.insert(messages, message)
  return message
end

local function ensureTool(assistantID, toolID, name, input)
  local message = ensureAssistant(assistantID)
  for _, tool in ipairs(message.tools) do
    if tool.id == toolID then
      if input ~= nil then
        tool.input = input
      end
      if name and name ~= "" then
        tool.name = name
      end
      return tool
    end
  end
  local tool = {
    id = toolID,
    name = name or "tool",
    status = "running",
    input = input,
    output = "",
  }
  table.insert(message.tools, tool)
  return tool
end

local function toolOutput(state)
  if type(state) ~= "table" then
    return ""
  end
  if state.status == "error" then
    return format.errorText(state.error)
  end
  local chunks = {}
  for _, content in ipairs(state.content or {}) do
    if type(content) == "table" and type(content.text) == "string" then
      table.insert(chunks, content.text)
    end
  end
  return table.concat(chunks, "\n")
end

local function mapContext(data)
  local out = {}
  for _, message in ipairs(data or {}) do
    if message.type == "user" then
      table.insert(out, {
        id = message.id,
        role = "user",
        text = tostring(message.text or ""),
      })
    elseif message.type == "assistant" then
      local text = {}
      local reasoning = {}
      local tools = {}
      for _, part in ipairs(message.content or {}) do
        if part.type == "text" then
          table.insert(text, tostring(part.text or ""))
        elseif part.type == "reasoning" then
          table.insert(reasoning, tostring(part.text or ""))
        elseif part.type == "tool" then
          table.insert(tools, {
            id = part.id,
            name = part.name,
            status = part.state and part.state.status or "running",
            input = part.state and part.state.input or nil,
            output = toolOutput(part.state),
          })
        end
      end
      table.insert(out, {
        id = message.id,
        role = "assistant",
        text = table.concat(text, ""),
        reasoning = table.concat(reasoning, ""),
        tools = tools,
        streaming = false,
        error = format.errorText(message.error),
        model = message.model,
      })
    end
  end
  return out
end

local function addPendingPermission(data)
  if type(data) ~= "table" or type(data.id) ~= "string" then
    return
  end
  for _, item in ipairs(pendingPermissions) do
    if item.id == data.id then
      return
    end
  end
  table.insert(pendingPermissions, {
    id = data.id,
    action = data.action,
    resources = data.resources or {},
    save = data.save or {},
    message = data.message or "",
    metadata = data.metadata,
    source = data.source,
  })
end

local function removePendingPermission(id)
  if type(id) ~= "string" then
    return
  end
  for i = #pendingPermissions, 1, -1 do
    if pendingPermissions[i].id == id then
      table.remove(pendingPermissions, i)
    end
  end
end

local function addPendingForm(data)
  if type(data) ~= "table" or type(data.id) ~= "string" then
    return
  end
  for _, item in ipairs(pendingForms) do
    if item.id == data.id then
      return
    end
  end
  table.insert(pendingForms, {
    id = data.id,
    title = data.title or "Formulário",
    fields = data.fields or {},
    metadata = data.metadata,
  })
end

local function removePendingForm(id)
  if type(id) ~= "string" then
    return
  end
  for i = #pendingForms, 1, -1 do
    if pendingForms[i].id == id then
      table.remove(pendingForms, i)
    end
  end
end

local function saveUi()
  store.writeUi(directory, {
    activeSessionID = activeSession and activeSession.id or nil,
    model = activeSession and activeSession.model or nil,
    preferredModel = preferredModel,
    agent = agentId,
    lastOpenedAt = noctalia.nowMs(),
  })
end

local function publishModels()
  local list = {}
  for _, model in ipairs(models) do
    table.insert(list, {
      id = model.id,
      providerID = model.providerID,
      name = model.name or model.id,
      variants = model.variants,
    })
  end
  noctalia.state.set("chat.models", list)
end

local function publishSessions()
  local list = {}
  for _, session in ipairs(sessions) do
    table.insert(list, {
      id = session.id,
      title = session.title or "Nova conversa",
      updatedAt = session.time and session.time.updated or 0,
      model = session.model,
      agent = session.agent,
    })
  end
  noctalia.state.set("chat.sessions", list)
end

local function setError(message)
  errorMessage = api.errorMessage(message)
  statusMessage = ""
  status = "error"
  publish(true)
end

publish = function(_force)
  revision = revision + 1
  local snapshot = {
    revision = revision,
    state = status,
    notice = statusMessage,
    error = errorMessage,
    baseUrl = pairing and pairing.baseUrl or "",
    agentMissing = agentMissing,
    session = activeSession and {
      id = activeSession.id,
      title = activeSession.title,
      model = activeSession.model,
      agent = activeSession.agent,
    } or nil,
    messages = messages,
    pending = {
      permissions = pendingPermissions,
      forms = pendingForms,
    },
    lastEventAt = noctalia.nowMs(),
  }
  noctalia.state.set("chat.snapshot", snapshot)
  noctalia.state.set("chat.status", {
    state = status,
    busy = busy,
    unread = unread,
    title = activeSession and activeSession.title or "",
    model = activeSession and format.modelLabel(activeSession.model) or "",
    error = errorMessage,
  })
  lastPublish = noctalia.nowMs()
  dirty = false
end

schedulePublish = function()
  dirty = true
end

refreshContext = function(id)
  local gen = generation
  api.context(pairing, directory, id, function(data, err)
    if gen ~= generation or err then
      return
    end
    if activeSession and activeSession.id == id then
      messages = mapContext(data)
      publish(true)
    end
  end)
end

exportSession = function(id)
  if not autoExport or not id then
    return
  end
  local gen = generation
  api.exportSession(pairing, directory, id, function(data, err)
    if gen ~= generation or err or not data then
      return
    end
    local ok, writeError = store.writeSession(directory, id, data, maxToolOutput)
    if not ok then
      noctalia.log("omyfedora-ai-chat: falha ao exportar sessão: " .. tostring(writeError))
    end
  end)
end

finishRun = function()
  if not runActive then
    return
  end
  runActive = false
  busy = false
  status = errorMessage ~= "" and "error" or "idle"
  statusMessage = ""
  if activeSession then
    refreshContext(activeSession.id)
    exportSession(activeSession.id)
  end
  unread = not panelOpen
  if notifyOnFinish and not panelOpen then
    local title = activeSession and activeSession.title or "Conversa"
    noctalia.notify("omyfedora IA", "Resposta concluída: " .. title)
  end
  publish(true)
end

loadCatalog = function(gen)
  api.listModels(pairing, function(data, err)
    if gen ~= generation then
      return
    end
    if err then
      setError(err)
      return
    end
    models = {}
    for _, model in ipairs(data or {}) do
      if model.enabled ~= false and model.status ~= "deprecated" then
        local id = model.id or model.modelID
        if id and model.providerID then
          local variants = {}
          for _, variant in ipairs(model.variants or {}) do
            local variantID = variant.id
            if type(variantID) == "string" and variantID ~= "" then
              table.insert(variants, { id = variantID })
            end
          end
          table.insert(models, {
            id = id,
            providerID = model.providerID,
            name = model.name or id,
            variants = variants,
          })
        end
      end
    end
    publishModels()
  end)

  api.listAgents(pairing, function(data, err)
    if gen ~= generation or err then
      return
    end
    agents = {}
    agentMissing = true
    for _, agent in ipairs(data or {}) do
      if agent.mode ~= "subagent" and agent.hidden ~= true then
        table.insert(agents, agent)
        if agent.id == agentId then
          agentMissing = false
        end
      end
    end
    publish(true)
  end)
end

selectSession = function(id)
  local session = findSession(id)
  if not session then
    return
  end
  activeSession = session
  messages = {}
  pendingPermissions = {}
  pendingForms = {}
  status = "idle"
  statusMessage = ""
  errorMessage = ""
  busy = false
  runActive = false
  publish(true)
  saveUi()

  local gen = generation
  api.context(pairing, directory, id, function(data, err)
    if gen ~= generation then
      return
    end
    if err then
      setError(err)
      return
    end
    messages = mapContext(data)
    if not activeSession.model then
      for i = #messages, 1, -1 do
        if messages[i].role == "assistant" and messages[i].model then
          activeSession.model = messages[i].model
          break
        end
      end
    end
    publish(true)
  end)

  api.listPermissions(pairing, directory, id, function(data, err)
    if gen ~= generation or err then
      return
    end
    pendingPermissions = data or {}
    publish(true)
  end)

  api.listForms(pairing, directory, id, function(data, err)
    if gen ~= generation or err then
      return
    end
    pendingForms = data or {}
    publish(true)
  end)
end

loadSessions = function(gen)
  api.listSessions(pairing, directory, function(data, err)
    if gen ~= generation then
      return
    end
    if err then
      setError(err)
      return
    end
    sessions = data or {}
    publishSessions()
    local ui = store.readUi(directory)
    local target = ui.activeSessionID
    if not target or not findSession(target) then
      target = sessions[1] and sessions[1].id or nil
    end
    if target then
      selectSession(target)
    else
      status = "idle"
      publish(true)
    end
  end)
end

local function copyModelRef(model)
  if type(model) ~= "table" or type(model.id) ~= "string" or model.id == "" then
    return nil
  end
  if type(model.providerID) ~= "string" or model.providerID == "" then
    return nil
  end
  local copy = { id = model.id, providerID = model.providerID }
  local variant = tostring(model.variant or "")
  if variant ~= "" and variant ~= "default" then
    copy.variant = variant
  end
  return copy
end

createSession = function(opts, onCreated)
  opts = opts or {}
  if not pairing then
    setError("Conecte o OpenCode primeiro.")
    return
  end
  local body = {
    title = "Nova conversa",
    agent = opts.agent or agentId,
    location = { directory = directory },
  }
  local inheritedModel = copyModelRef(opts.model)
    or copyModelRef(preferredModel)
    or copyModelRef(activeSession and activeSession.model or nil)
  if inheritedModel then
    body.model = inheritedModel
  end
  api.createSession(pairing, directory, body, function(session, err)
    if err or not session then
      setError(err or "Falha ao criar sessão.")
      return
    end
    table.insert(sessions, 1, session)
    publishSessions()
    selectSession(session.id)
    if onCreated then
      onCreated(session)
    end
  end)
end

sendPromptTo = function(sessionID, text)
  if not pairing then
    setError("Conecte o OpenCode primeiro.")
    return
  end
  local last = messages[#messages]
  if not (last and last.role == "user" and last.text == text) then
    table.insert(messages, {
      id = "local-" .. tostring(noctalia.nowMs()),
      role = "user",
      text = text,
    })
  end
  local session = findSession(sessionID)
  if session and (session.title == nil or session.title == "" or session.title == "Nova conversa") then
    local title = text:sub(1, 60)
    session.title = title
    if activeSession and activeSession.id == sessionID then
      activeSession.title = title
    end
    publishSessions()
    api.renameSession(pairing, directory, sessionID, title, function(ok, err)
      if not ok then
        noctalia.log("omyfedora-ai-chat: falha ao renomear sessão: " .. tostring(err))
      end
    end)
  end
  runActive = true
  busy = true
  status = "busy"
  statusMessage = ""
  errorMessage = ""
  unread = false
  publish(true)
  api.prompt(pairing, directory, sessionID, text, function(ok, err)
    if ok then
      return
    end
    runActive = false
    busy = false
    status = "error"
    errorMessage = api.errorMessage(err)
    publish(true)
  end)
end

sendPrompt = function(text)
  local value = noctalia.string.trim(text or "")
  if value == "" then
    return
  end
  if not pairing then
    setError("Conecte o OpenCode primeiro.")
    return
  end
  if activeSession then
    sendPromptTo(activeSession.id, value)
    return
  end
  createSession({}, function(session)
    sendPromptTo(session.id, value)
  end)
end

local function interrupt()
  if not activeSession then
    return
  end
  api.interrupt(pairing, directory, activeSession.id, function(ok, err)
    if not ok then
      setError(err)
    end
  end)
end

local function setModel(model)
  if not activeSession or type(model) ~= "table" or not model.id then
    return
  end
  api.setModel(pairing, directory, activeSession.id, model, function(ok, err)
    if not ok then
      setError(err)
      return
    end
    local normalized = copyModelRef(model) or model
    activeSession.model = normalized
    preferredModel = normalized
    saveUi()
    publish(true)
  end)
end

local function setAgent(agent)
  if not activeSession or type(agent) ~= "string" or agent == "" then
    return
  end
  api.setAgent(pairing, directory, activeSession.id, agent, function(ok, err)
    if not ok then
      setError(err)
      return
    end
    activeSession.agent = agent
    agentId = agent
    saveUi()
    publish(true)
  end)
end

local function deleteSession(id)
  if type(id) ~= "string" or id == "" then
    return
  end
  api.deleteSession(pairing, directory, id, function(ok, err)
    if not ok then
      setError(err)
      return
    end
    for i = #sessions, 1, -1 do
      if sessions[i].id == id then
        table.remove(sessions, i)
      end
    end
    if activeSession and activeSession.id == id then
      activeSession = nil
      messages = {}
      pendingPermissions = {}
      pendingForms = {}
      status = "idle"
      statusMessage = ""
      errorMessage = ""
      busy = false
      runActive = false
      saveUi()
    end
    publishSessions()
    publish(true)
  end)
end

local function replyPermission(requestID, decision)
  if not activeSession or type(requestID) ~= "string" then
    return
  end
  api.replyPermission(pairing, directory, activeSession.id, requestID, decision, function(ok, err)
    if not ok then
      setError(err)
      return
    end
    removePendingPermission(requestID)
    publish(true)
  end)
end

local function replyForm(formID, answer)
  if not activeSession or type(formID) ~= "string" then
    return
  end
  api.replyForm(pairing, directory, activeSession.id, formID, answer or {}, function(ok, err)
    if not ok then
      setError(err)
      return
    end
    removePendingForm(formID)
    publish(true)
  end)
end

handleEvent = function(event)
  local data = event.data or {}
  local sessionID = data.sessionID
  local eventType = event.type

  if eventType == "server.connected" then
    status = "idle"
    publish(true)
    return
  end

  if eventType == "session.created" and sessionID then
    if not findSession(sessionID) then
      table.insert(sessions, 1, {
        id = sessionID,
        title = data.title or "Nova conversa",
        time = { updated = noctalia.nowMs() },
        model = data.model,
        agent = data.agent,
      })
      publishSessions()
      publish(true)
    end
    return
  end

  if eventType == "session.renamed" and sessionID then
    local session = findSession(sessionID)
    if session and type(data.title) == "string" then
      session.title = data.title
      if activeSession and activeSession.id == sessionID then
        activeSession.title = data.title
      end
      publishSessions()
      publish(true)
    end
    return
  end

  if eventType == "session.updated" and sessionID then
    local session = findSession(sessionID)
    local info = data.info
    if session and type(info) == "table" then
      if type(info.title) == "string" then
        session.title = info.title
      end
      if info.model then
        session.model = info.model
      end
      if info.agent then
        session.agent = info.agent
      end
      if activeSession and activeSession.id == sessionID then
        activeSession.title = session.title
        activeSession.model = session.model or activeSession.model
        activeSession.agent = session.agent or activeSession.agent
      end
      publishSessions()
      publish(true)
    end
    return
  end

  -- Formulários (incluindo a ferramenta question) trazem o sessionID dentro
  -- de data.form. Trate-os antes do filtro de sessão para não perder o evento.
  if eventType == "form.created" then
    local form = data.form or data
    if type(form) == "table" and activeSession and form.sessionID == activeSession.id then
      addPendingForm(form)
      if not panelOpen then
        noctalia.notify("omyfedora IA", "O agente precisa de uma resposta.")
      end
      publish(true)
    end
    return
  end

  if eventType == "form.replied" or eventType == "form.cancelled" then
    local formID = data.id
    if type(data.form) == "table" then
      formID = data.form.id or formID
    end
    removePendingForm(formID)
    publish(true)
    return
  end

  if not activeSession or sessionID ~= activeSession.id then
    return
  end

  local assistantID = data.assistantMessageID

  if eventType == "session.step.started" or eventType == "session.execution.started" then
    if not runActive then
      runActive = true
      busy = true
      status = "busy"
      statusMessage = ""
      errorMessage = ""
      unread = false
      publish(true)
    end
  elseif eventType == "session.text.started" then
    if assistantID then
      ensureAssistant(assistantID).streaming = true
      schedulePublish()
    end
  elseif eventType == "session.text.delta" then
    if assistantID and type(data.delta) == "string" then
      local message = ensureAssistant(assistantID)
      message.text = message.text .. data.delta
      message.streaming = true
      statusMessage = ""
      schedulePublish()
    end
  elseif eventType == "session.text.ended" then
    if assistantID then
      local message = ensureAssistant(assistantID)
      if type(data.text) == "string" then
        message.text = data.text
      end
      message.streaming = false
      schedulePublish()
    end
  elseif eventType == "session.reasoning.delta" then
    if assistantID and type(data.delta) == "string" then
      local message = ensureAssistant(assistantID)
      message.reasoning = message.reasoning .. data.delta
      schedulePublish()
    end
  elseif eventType == "session.reasoning.ended" then
    if assistantID then
      local message = ensureAssistant(assistantID)
      if type(data.text) == "string" then
        message.reasoning = data.text
      end
      schedulePublish()
    end
  elseif eventType == "session.tool.input.started" then
    if type(data.id) == "string" and type(data.name) == "string" then
      toolNames[data.id] = data.name
    end
  elseif eventType == "session.tool.called" then
    if assistantID and type(data.id) == "string" then
      local tool = ensureTool(assistantID, data.id, toolNames[data.id], data.input)
      tool.status = "running"
      schedulePublish()
    end
  elseif eventType == "session.tool.progress" then
    if type(data.id) == "string" then
      local tool = findTool(data.id)
      if tool then
        tool.metadata = data.metadata
        schedulePublish()
      end
    end
  elseif eventType == "session.tool.success" then
    if assistantID and type(data.id) == "string" then
      local tool = ensureTool(assistantID, data.id, toolNames[data.id], data.input)
      tool.status = "ok"
      tool.output = toolOutput({ status = "completed", content = data.content })
      tool.metadata = data.metadata
      schedulePublish()
    end
  elseif eventType == "session.tool.failed" then
    if assistantID and type(data.id) == "string" then
      local tool = ensureTool(assistantID, data.id, toolNames[data.id], data.input)
      tool.status = "error"
      local errorText = format.errorText(data.error)
      tool.output = errorText ~= "" and errorText or toolOutput({ status = "completed", content = data.content })
      schedulePublish()
    end
  elseif eventType == "session.retry.scheduled" then
    busy = true
    status = "busy"
    local attempt = tonumber(data.attempt)
    local reason = type(data.message) == "string" and data.message or "erro temporário"
    statusMessage = "Tentando novamente" .. (attempt and (" (tentativa " .. tostring(attempt) .. ")") or "") .. ": " .. reason
    publish(true)
  elseif eventType == "session.execution.succeeded" or eventType == "session.execution.failed" or eventType == "session.execution.interrupted" then
    if eventType == "session.execution.failed" then
      errorMessage = "A execução falhou."
    end
    finishRun()
  elseif eventType == "session.step.ended" then
    if data.finish ~= "tool-calls" then
      finishRun()
    end
  elseif eventType == "session.status" then
    local state = data.status
    if type(state) == "table" and state.type == "idle" then
      finishRun()
    end
  elseif eventType == "session.error" then
    local message = lastAssistant()
    if message then
      message.error = format.errorText(data.error)
      message.streaming = false
    end
    errorMessage = format.errorText(data.error) ~= "" and format.errorText(data.error) or "Erro na execução."
    finishRun()
  elseif eventType == "permission.asked" then
    -- Comportamento tipo OpenCode: shell/edit e perguntas seguem direto;
    -- outras ações sensíveis (ex.: leitura de .env.*) são negadas automaticamente.
    if activeSession and data.id then
      local action = tostring(data.action or "")
      local allowed = action == "shell" or action == "edit" or action == "question" or action == "form"
      local decision = allowed and "once" or "reject"
      api.replyPermission(pairing, directory, activeSession.id, data.id, decision, function(ok, err)
        if not ok then
          noctalia.log("omyfedora-ai-chat: falha ao responder permissão automática: " .. tostring(err))
        end
      end)
      noctalia.log("omyfedora-ai-chat: permissão automática (" .. decision .. "): " .. action)
      if decision == "reject" then
        noctalia.notify("omyfedora IA", "Ação sensível bloqueada automaticamente: " .. action)
      end
    end
    publish(true)
  elseif eventType == "permission.replied" then
    removePendingPermission(data.requestID or data.id)
    publish(true)
  end
end

connectSse = function()
  if not pairing then
    return
  end
  streamGeneration = streamGeneration + 1
  local gen = streamGeneration
  if stream then
    stream.stop()
    stream = nil
  end
  reconnectAt = 0
  stream = api.streamEvents(pairing, function(event)
    if gen == streamGeneration then
      handleEvent(event)
    end
  end, function(result)
    if gen ~= streamGeneration then
      return
    end
    stream = nil
    if result and result.status == 401 then
      reconnectAt = 0
      if autoPair then
        doPair("")
      else
        status = "unpaired"
        publish(true)
      end
      return
    end
    local delay = math.min(30, 2 ^ reconnectAttempt)
    reconnectAttempt = reconnectAttempt + 1
    reconnectAt = noctalia.nowMs() + delay * 1000
    noctalia.log("omyfedora-ai-chat: SSE caiu; reconectando em " .. tostring(delay) .. "s")
  end)
  if stream then
    reconnectAttempt = 0
    noctalia.log("omyfedora-ai-chat: SSE conectado")
  else
    local delay = math.min(30, 2 ^ reconnectAttempt)
    reconnectAttempt = reconnectAttempt + 1
    reconnectAt = noctalia.nowMs() + delay * 1000
  end
end

checkHealth = function(gen)
  if not pairing then
    status = "unpaired"
    publish(true)
    return
  end
  lastHealthCheck = noctalia.nowMs()
  api.health(pairing.baseUrl, function(ok, version)
    if gen ~= generation then
      return
    end
    if not ok then
      status = "offline"
      errorMessage = "OpenCode não está respondendo."
      publish(true)
      return
    end
    pairing.version = version
    store.writePairing(directory, pairing)
    status = "idle"
    errorMessage = ""
    publish(true)
    loadCatalog(gen)
    loadSessions(gen)
    connectSse()
  end)
end

onPaired = function(result, err)
  if err or not result then
    status = "unpaired"
    errorMessage = api.errorMessage(err or "Falha ao parear.")
    publish(true)
    return
  end
  pairing = {
    baseUrl = result.baseUrl,
    token = result.token,
    version = "",
    pairedAt = noctalia.nowMs(),
  }
  store.writePairing(directory, pairing)
  status = "idle"
  errorMessage = ""
  publish(true)
  checkHealth(generation)
end

doPair = function(link)
  if status == "pairing" then
    return
  end
  status = "pairing"
  statusMessage = ""
  errorMessage = ""
  publish(true)

  if type(link) == "string" and noctalia.string.trim(link) ~= "" then
    api.pair(link, onPaired)
    return
  end

  local binary = noctalia.getConfig("opencode_bin") or "opencode"
  if not noctalia.commandExists(binary) then
    status = "unpaired"
    errorMessage = "Binário não encontrado: " .. binary
    publish(true)
    return
  end

  noctalia.runAsync({ binary, "pair" }, function(result)
    if result.exitCode ~= 0 then
      status = "unpaired"
      errorMessage = (result.stderr ~= "" and result.stderr) or "`opencode pair` falhou."
      publish(true)
      return
    end
    local found = tostring(result.stdout or ""):match("(https?://[^%s]+/auth/connect/[%w_%-]+)")
    if not found then
      status = "unpaired"
      errorMessage = "Não encontrei o link no output de `opencode pair`."
      publish(true)
      return
    end
    api.pair(found, onPaired)
  end, 15000)
end

local PANEL_SIZE_PRESETS = {
  compact = { width = 420, height = 560 },
  medium = { width = 460, height = 640 },
  large = { width = 620, height = 820 },
}

local function panelSizeFromManifest(text)
  local width = nil
  local height = nil
  local inPanel = false
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed == "[[panel]]" then
      inPanel = true
    elseif inPanel and trimmed:match("^%[%[") then
      break
    elseif inPanel then
      local w = trimmed:match("^width%s*=%s*(%d+)")
      if w then
        width = tonumber(w)
      end
      local h = trimmed:match("^height%s*=%s*(%d+)")
      if h then
        height = tonumber(h)
      end
    end
  end
  return width, height
end

local function rewritePanelSize(text, width, height)
  local out = {}
  local inPanel = false
  local sawWidth = false
  local sawHeight = false
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed == "[[panel]]" then
      inPanel = true
    elseif inPanel and trimmed:match("^%[%[") then
      inPanel = false
    end
    if inPanel and trimmed:match("^width%s*=") then
      table.insert(out, "width = " .. tostring(width))
      sawWidth = true
    elseif inPanel and trimmed:match("^height%s*=") then
      table.insert(out, "height = " .. tostring(height))
      sawHeight = true
    else
      table.insert(out, line)
    end
  end
  if not (sawWidth and sawHeight) then
    return nil
  end
  return table.concat(out, "\n")
end

local function applyPanelSize()
  local preset = tostring(noctalia.getConfig("panel_size") or "medium")
  local size = PANEL_SIZE_PRESETS[preset] or PANEL_SIZE_PRESETS.medium
  local dir = noctalia.pluginDir()
  if not dir then
    return
  end
  local path = dir .. "/plugin.toml"
  local text = noctalia.readFile(path)
  if not text then
    return
  end
  local width, height = panelSizeFromManifest(text)
  if width == size.width and height == size.height then
    return
  end
  local updated = rewritePanelSize(text, size.width, size.height)
  if not updated then
    noctalia.log("omyfedora-ai-chat: width/height do painel não encontrados no plugin.toml")
    return
  end
  local backedUp, backupErr = noctalia.writeFile(path .. ".bak-size", text)
  if not backedUp then
    noctalia.log("omyfedora-ai-chat: falha ao criar backup do plugin.toml: " .. tostring(backupErr))
  end
  local ok, err = noctalia.writeFile(path, updated)
  if not ok then
    noctalia.log("omyfedora-ai-chat: falha ao gravar o tamanho do painel: " .. tostring(err))
    noctalia.notifyError("omyfedora IA", "Não consegui redimensionar o painel: " .. tostring(err))
    return
  end
  noctalia.log(
    "omyfedora-ai-chat: painel " .. preset .. " (" .. tostring(size.width) .. "x" .. tostring(size.height) .. "); recarregando"
  )
  local started = noctalia.runAsync(
    "nohup sh -c 'sleep 0.2; noctalia msg plugins disable omyfedora/ai-chat; sleep 0.5; noctalia msg plugins enable omyfedora/ai-chat' >/dev/null 2>&1 &"
  )
  if not started then
    noctalia.notifyError("omyfedora IA", "Não consegui recarregar o plugin para aplicar o novo tamanho.")
  end
end

local function init()
  generation = generation + 1
  local gen = generation
  directory = noctalia.expandPath(noctalia.getConfig("directory") or "~/.omyfedora-ai-chat")
  agentId = noctalia.getConfig("agent") or "omyfedora-chat"
  autoPair = noctalia.getConfig("auto_pair") ~= false
  autoExport = noctalia.getConfig("auto_export") ~= false
  notifyOnFinish = noctalia.getConfig("notify_on_finish") ~= false
  maxToolOutput = tonumber(noctalia.getConfig("max_tool_output")) or 4000

  store.ensure(directory)

  local ui = store.readUi(directory)
  preferredModel = copyModelRef(ui.preferredModel) or copyModelRef(ui.model)

  pairing = store.readPairing(directory)
  models = {}
  agents = {}
  sessions = {}
  activeSession = nil
  messages = {}
  pendingPermissions = {}
  pendingForms = {}
  toolNames = {}
  busy = false
  runActive = false
  unread = false
  statusMessage = ""
  errorMessage = ""
  agentMissing = false
  revision = 0
  dirty = false
  lastPublish = 0
  lastHealthCheck = 0
  reconnectAt = 0
  reconnectAttempt = 0
  streamGeneration = 0

  if pairing then
    status = "offline"
    publish(true)
    checkHealth(gen)
  else
    status = "unpaired"
    publish(true)
  end
end

function onIpc(event, payload)
  if event == "sync" then
    if pairing and status == "offline" then
      checkHealth(generation)
    else
      publish(true)
      publishModels()
      publishSessions()
    end
  elseif event == "pair" then
    doPair(payload)
  elseif event == "unpair" then
    if stream then
      stream.stop()
      stream = nil
    end
    store.clearPairing(directory)
    pairing = nil
    status = "unpaired"
    statusMessage = ""
    errorMessage = ""
    messages = {}
    pendingPermissions = {}
    pendingForms = {}
    busy = false
    runActive = false
    publish(true)
  elseif event == "new_session" then
    createSession(decode(payload))
  elseif event == "select_session" then
    selectSession(payload)
  elseif event == "delete_session" then
    deleteSession(payload)
  elseif event == "set_model" then
    setModel(decode(payload))
  elseif event == "set_agent" then
    setAgent(payload)
  elseif event == "prompt" then
    sendPrompt(payload)
  elseif event == "interrupt" then
    interrupt()
  elseif event == "reply_permission" then
    local data = decode(payload)
    replyPermission(data.requestID, data.decision)
  elseif event == "reply_form" then
    local data = decode(payload)
    replyForm(data.formID, data.answer)
  elseif event == "refresh_models" then
    if pairing then
      loadCatalog(generation)
    end
  elseif event == "refresh_sessions" then
    if pairing then
      loadSessions(generation)
    end
  elseif event == "export" then
    if activeSession then
      exportSession(payload ~= "" and payload or activeSession.id)
    end
  elseif event == "toggle_panel" then
    noctalia.togglePanel("omyfedora/ai-chat:panel")
  end
end

function update()
  if dirty and noctalia.nowMs() - lastPublish >= 100 then
    publish(true)
  end
  if reconnectAt > 0 and noctalia.nowMs() >= reconnectAt then
    reconnectAt = 0
    connectSse()
  end
  if status == "offline" and pairing and noctalia.nowMs() - lastHealthCheck > 15000 then
    checkHealth(generation)
  end
end

function onEnable()
  if pairing and status ~= "idle" then
    checkHealth(generation)
  end
end

function onConfigChanged()
  init()
  applyPanelSize()
end

function onExit(_signal, _reason)
  if stream then
    stream.stop()
    stream = nil
  end
end

noctalia.setUpdateInterval(100)
noctalia.state.watch("chat.panel_open", function(value)
  panelOpen = value == true
end)
panelOpen = noctalia.state.get("chat.panel_open") == true
applyPanelSize()
init()
