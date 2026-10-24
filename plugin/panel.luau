--!nonstrict
-- Painel principal do chat: flutuante, persistente, camada overlay.

local format = require("./lib/format.luau")

local isOpen = false
local snapshot = noctalia.state.get("chat.snapshot")
local composerKey = 0
local draft = ""
local pairLinkDraft = ""
local toast = ""
local toastAt = 0
local expandedTools = {}
local expandedPermissions = {}
local expandedReasoning = {}
local formDrafts = {}
local view = "chat"
local models = noctalia.state.get("chat.models") or {}
local sessions = noctalia.state.get("chat.sessions") or {}
local selectedModelIndex = 0
local selectedSessionIndex = 0
local selectedReasoningId = "default"
local deleteConfirm = nil
local spinnerFrames = { "◐", "◓", "◑", "◒" }
local spinnerFrame = 1
local spinnerAccum = 0
local render

-- Fundo do painel: "black" (preto fixo — exceção pedida) ou "theme" (segue o
-- tema). A intensidade do preto vem de `background_opacity` (0–100).
local backgroundModeValue = "black"
local backgroundOpacity = 45

local function refreshBackground()
  backgroundModeValue = tostring(noctalia.getConfig("background_mode") or "black")
  backgroundOpacity = tonumber(noctalia.getConfig("background_opacity")) or 45
  if backgroundOpacity < 0 then
    backgroundOpacity = 0
  elseif backgroundOpacity > 100 then
    backgroundOpacity = 100
  end
end

refreshBackground()

local function frameFill()
  return string.format("#000000%02x", math.floor(backgroundOpacity * 255 / 100 + 0.5))
end

-- Cores de texto: com fundo preto fixo, um tema claro deixaria o texto escuro
-- sobre preto. Nesses tons claros garantimos contraste; no modo "theme" voltam
-- aos roles do tema.
local function textColor()
  return backgroundModeValue == "theme" and "on_surface" or "#F5F7FA"
end

local function mutedColor()
  return backgroundModeValue == "theme" and "on_surface_variant" or "#C7CCD9"
end

local function sendCommand(event, payload)
  local argv = { "noctalia", "msg", "plugin", "msbos/ai-chat:engine", "all", event }
  if type(payload) == "string" and payload ~= "" then
    table.insert(argv, payload)
  end
  local started = noctalia.runAsync(argv, function(result)
    if result.exitCode ~= 0 then
      toast = result.stderr ~= "" and result.stderr or "Falha ao falar com o serviço do chat."
      toastAt = noctalia.nowMs()
      render()
    end
  end)
  if not started then
    toast = "Não foi possível falar com o serviço do chat."
    toastAt = noctalia.nowMs()
    render()
  end
end

local function subtitle()
  if snapshot == nil then
    return "carregando…"
  end
  if snapshot.state == "busy" then
    return "executando…"
  end
  if snapshot.session and snapshot.session.title and snapshot.session.title ~= "" then
    return snapshot.session.title
  end
  if snapshot.state == "unpaired" then
    return "não pareado"
  end
  if snapshot.state == "starting" then
    return "iniciando…"
  end
  if snapshot.state == "offline" then
    return "offline"
  end
  return "pronto"
end

-- Agente e modelo da conversa (snapshot.session), no formato "agente: …   modelo: …".
local function metaLabel()
  local agent = "—"
  local model = "modelo padrão"
  if snapshot and snapshot.session then
    agent = tostring(snapshot.session.agent or "—")
    local label = format.modelLabel(snapshot.session.model)
    if label ~= "" then
      model = label
    end
  end
  return ui.label({
    text = "agente: " .. agent .. "   modelo: " .. model,
    fontSize = 9,
    color = mutedColor(),
    maxLines = 1,
    flexGrow = 1,
  })
end

local function header()
  return ui.row({
    gap = 8,
    align = "center",
    paddingH = 12,
    paddingV = 8,
    fill = "surface_variant/0.18",
    border = "outline/0.35",
    borderWidth = 1,
    radius = 12,
  }, {
    ui.glyph({ name = "message-chatbot", size = 18, color = "primary" }),
    ui.column({ gap = 3, flexGrow = 1 }, {
      ui.row({ gap = 10, align = "center" }, {
        ui.label({ text = "msbos IA", fontSize = 15, fontWeight = "bold", color = textColor() }),
        metaLabel(),
      }),
      ui.label({ text = subtitle(), fontSize = 10, color = mutedColor(), maxLines = 1 }),
    }),
    ui.button({ glyph = "plus", variant = "ghost", tooltip = "Nova conversa", onClick = "onNewSession" }),
    ui.button({ glyph = "history", variant = "ghost", tooltip = "Modelos e sessões", onClick = "onOpenPicker" }),
    ui.button({ glyph = "minus", variant = "ghost", tooltip = "Minimizar", onClick = "onMinimize" }),
  })
end

local function busyIndicator()
  return ui.row({ gap = 6, align = "center" }, {
    ui.label({
      text = spinnerFrames[spinnerFrame],
      width = 16,
      fontSize = 14,
      textAlign = "center",
      color = "primary",
    }),
    ui.label({ text = "Pensando…", fontSize = 10, color = mutedColor() }),
  })
end

local function emptyState()
  return ui.column({ gap = 10, align = "center", padding = 20 }, {
    ui.glyph({ name = "sparkles", size = 34, color = "primary" }),
    ui.label({ text = "Pergunte sobre o seu sistema", fontSize = 16, fontWeight = "bold", color = textColor() }),
    ui.label({
      text = "Ex.: “ajuste o gap do niri para 8”, “instale o htop”, “troque o tema do Noctalia”.",
      fontSize = 11,
      color = mutedColor(),
      textAlign = "center",
      maxLines = 4,
    }),
    ui.label({
      text = "Toda mudança é confirmada antes de ser aplicada.",
      fontSize = 10,
      color = mutedColor(),
      textAlign = "center",
    }),
  })
end

local function agentMissingCard()
  return ui.column({
    fill = "error/0.08",
    border = "error/0.45",
    borderWidth = 1,
    radius = 10,
    padding = 10,
    gap = 6,
    align = "stretch",
  }, {
    ui.row({ gap = 6, align = "center" }, {
      ui.glyph({ name = "alert-triangle", size = 15, color = "error" }),
      ui.label({ text = "Agente msbos-chat indisponível", fontWeight = "bold", color = "error", fontSize = 11 }),
    }),
    ui.label({
      text = "O OpenCode ainda não listou o agente. O chat tenta de novo automaticamente; se persistir, rode ./install.sh e verifique ~/.config/opencode/agents/msbos-chat.md.",
      fontSize = 10,
      color = mutedColor(),
      maxLines = 4,
    }),
    ui.button({ text = "Verificar novamente", variant = "secondary", fontSize = 10, onClick = "onRetryAgent" }),
  })
end

local function renderTool(tool)
  local expanded = expandedTools[tool.id] == true
  local color = mutedColor()
  if tool.status == "error" then
    color = "error"
  elseif tool.status == "ok" or tool.status == "completed" then
    color = "primary"
  end

  local headerChildren = {
    ui.glyph({ name = format.toolGlyph(tool.name), size = 13, color = color }),
    ui.label({ text = tostring(tool.name or "tool"), fontSize = 10, fontWeight = "bold", color = textColor() }),
    ui.label({ text = format.toolStatusLabel(tool.status), fontSize = 9, color = color }),
    ui.spacer({ flexGrow = 1 }),
    ui.button({
      glyph = expanded and "chevron-up" or "chevron-down",
      variant = "ghost",
      onClick = function()
        expandedTools[tool.id] = not expanded
        render()
      end,
    }),
  }

  local children = { ui.row({ gap = 6, align = "center" }, headerChildren) }
  if expanded then
    local input = format.toolInput(tool.input)
    if input ~= "" then
      table.insert(children, ui.label({ text = input, fontSize = 9, color = mutedColor(), maxLines = 12 }))
    end
    if tool.output and tool.output ~= "" then
      table.insert(children, ui.markdown({ text = format.truncate(tool.output, 4000) }))
    end
  end

  return ui.column({
    fill = "surface_variant/0.16",
    border = "outline/0.30",
    borderWidth = 1,
    radius = 8,
    padding = 8,
    gap = 4,
    align = "stretch",
  }, children)
end

local function renderForm(form)
  local draftForm = formDrafts[form.id]
  if not draftForm then
    draftForm = {}
    for _, field in ipairs(form.fields or {}) do
      if field.default ~= nil then
        draftForm[field.key] = field.default
      end
    end
    formDrafts[form.id] = draftForm
  end

  local children = {
    ui.row({ gap = 6, align = "center" }, {
      ui.glyph({ name = "forms", size = 15, color = "primary" }),
      ui.label({ text = tostring(form.title or "Formulário"), fontSize = 11, fontWeight = "bold", color = textColor() }),
    }),
    ui.label({
      text = "Confira o pedido antes de responder; o texto vem do modelo, não do painel.",
      fontSize = 9,
      color = mutedColor(),
    }),
  }

  local function addDescription(field)
    local description = tostring(field.description or "")
    if description ~= "" then
      table.insert(children, ui.label({
        text = description,
        fontSize = 10,
        color = textColor(),
        maxLines = 6,
      }))
    end
  end

  local function optionColumn(field, option, selected)
    local props = {
      gap = 2,
      flexGrow = 1,
      align = "stretch",
      padding = 8,
      radius = 10,
      fill = selected and "primary" or "surface_variant/0.35",
      onClick = function()
        if field.type == "multiselect" then
          local values = draftForm[field.key]
          if type(values) ~= "table" then
            values = {}
            draftForm[field.key] = values
          end
          local nextValues = {}
          local found = false
          for _, value in ipairs(values) do
            if value == option.value then
              found = true
            else
              table.insert(nextValues, value)
            end
          end
          if not found then
            table.insert(nextValues, option.value)
          end
          draftForm[field.key] = nextValues
        else
          draftForm[field.key] = option.value
        end
        render()
      end,
    }
    if not selected then
      props.border = "outline/0.2"
      props.borderWidth = 1
    end

    local optionChildren = {
      ui.label({
        text = tostring(option.label or option.value),
        fontSize = 9,
        fontWeight = "bold",
        color = selected and "on_primary" or textColor(),
        maxLines = 2,
      }),
    }
    local description = tostring(option.description or "")
    if description ~= "" then
      table.insert(optionChildren, ui.label({
        text = description,
        fontSize = 9,
        color = selected and "on_primary/0.85" or mutedColor(),
        maxLines = 3,
      }))
    end
    return ui.column(props, optionChildren)
  end

  for _, field in ipairs(form.fields or {}) do
    local label = tostring(field.title or field.key or "campo")
    if field.type == "boolean" then
      table.insert(children, ui.label({ text = label, fontSize = 10, color = mutedColor() }))
      addDescription(field)
      table.insert(children, ui.row({ gap = 8, align = "center" }, {
        ui.spacer({ flexGrow = 1 }),
        ui.toggle({
          checked = draftForm[field.key] == true,
          onChange = function(value)
            draftForm[field.key] = value == "true"
            render()
          end,
        }),
      }))
    elseif field.type == "string" and type(field.options) == "table" and #field.options > 0 then
      table.insert(children, ui.label({ text = label, fontSize = 10, color = mutedColor() }))
      addDescription(field)
      local buttons = {}
      for _, option in ipairs(field.options) do
        table.insert(buttons, optionColumn(field, option, draftForm[field.key] == option.value))
      end
      table.insert(children, ui.row({ gap = 6, align = "start" }, buttons))
    elseif field.type == "multiselect" then
      table.insert(children, ui.label({ text = label, fontSize = 10, color = mutedColor() }))
      addDescription(field)
      local selected = draftForm[field.key]
      if type(selected) ~= "table" then
        selected = {}
        draftForm[field.key] = selected
      end
      local buttons = {}
      for _, option in ipairs(field.options or {}) do
        local isSelected = false
        for _, value in ipairs(selected) do
          if value == option.value then
            isSelected = true
          end
        end
        table.insert(buttons, optionColumn(field, option, isSelected))
      end
      table.insert(children, ui.row({ gap = 6, align = "start" }, buttons))
    else
      table.insert(children, ui.label({ text = label, fontSize = 10, color = mutedColor() }))
      addDescription(field)
      table.insert(children, ui.input({
        key = "form-" .. tostring(form.id) .. "-" .. tostring(field.key),
        value = tostring(draftForm[field.key] or ""),
        placeholder = tostring(field.placeholder or ""),
        onChange = function(value)
          draftForm[field.key] = value
        end,
      }))
    end
  end

  table.insert(children, ui.button({
    text = "Responder",
    variant = "primary",
    fontSize = 10,
    onClick = function()
      sendCommand("reply_form", noctalia.json.encode({ formID = form.id, answer = draftForm }))
      formDrafts[form.id] = nil
    end,
  }))

  return ui.column({
    fill = "primary/0.06",
    border = "primary/0.35",
    borderWidth = 1,
    radius = 10,
    padding = 10,
    gap = 6,
    align = "stretch",
  }, children)
end

-- Cartão de permissão: o engine não autoaprova shell/edit; o usuário decide aqui.
local function permissionDetail(permission)
  local lines = {}
  local resources = permission.resources
  if type(resources) == "table" then
    for _, key in ipairs({ "command", "path", "file", "pattern", "url" }) do
      local value = resources[key]
      if type(value) == "string" and value ~= "" then
        table.insert(lines, key .. ": " .. value)
      end
    end
    if #lines == 0 then
      for key, value in pairs(resources) do
        if type(value) == "string" and value ~= "" then
          table.insert(lines, tostring(key) .. ": " .. value)
        end
      end
    end
  end
  return table.concat(lines, "\n")
end

local function renderPermission(permission)
  local children = {
    ui.row({ gap = 6, align = "center" }, {
      ui.glyph({ name = "shield-lock", size = 15, color = "tertiary" }),
      ui.label({
        text = "Permissão: " .. tostring(permission.action or "ação"),
        fontSize = 11,
        fontWeight = "bold",
        color = textColor(),
        flexGrow = 1,
        maxLines = 1,
      }),
    }),
  }
  local message = tostring(permission.message or "")
  if message ~= "" then
    table.insert(children, ui.label({ text = message, fontSize = 10, color = textColor(), maxLines = 4 }))
  end
  local detail = permissionDetail(permission)
  if detail ~= "" then
    -- Mostra o alvo em bloco de código (monoespaçado) e permite expandir: o
    -- comando/salvamento precisa ser lido por inteiro antes de aprovar.
    local expanded = expandedPermissions[permission.id] == true
    local preview = expanded and detail or format.truncate(detail, 280)
    table.insert(children, ui.markdown({ text = "```text\n" .. preview .. "\n```" }))
    if not expanded and #detail > 280 then
      table.insert(children, ui.button({
        text = "Ver o alvo completo",
        variant = "ghost",
        fontSize = 9,
        onClick = function()
          expandedPermissions[permission.id] = true
          render()
        end,
      }))
    end
  end
  table.insert(children, ui.row({ gap = 8, align = "center" }, {
    ui.button({
      text = "Permitir uma vez",
      variant = "primary",
      fontSize = 10,
      onClick = function()
        expandedPermissions[permission.id] = nil
        sendCommand("reply_permission", noctalia.json.encode({ requestID = permission.id, decision = "once" }))
      end,
    }),
    -- "Sempre" é menos destacado de propósito; o escopo é o que o servidor definiu.
    ui.button({
      text = "Permitir sempre",
      variant = "ghost",
      fontSize = 10,
      tooltip = "Permite sempre (escopo definido pelo OpenCode)",
      onClick = function()
        expandedPermissions[permission.id] = nil
        sendCommand("reply_permission", noctalia.json.encode({ requestID = permission.id, decision = "always" }))
      end,
    }),
    ui.button({
      text = "Recusar",
      variant = "destructive",
      fontSize = 10,
      onClick = function()
        expandedPermissions[permission.id] = nil
        sendCommand("reply_permission", noctalia.json.encode({ requestID = permission.id, decision = "reject" }))
      end,
    }),
  }))
  return ui.column({
    fill = "tertiary/0.10",
    border = "tertiary/0.40",
    borderWidth = 1,
    radius = 10,
    padding = 10,
    gap = 6,
    align = "stretch",
  }, children)
end

local function renderMessage(message)
  if message.role == "user" then
    return ui.column({
      fill = "primary/0.12",
      radius = 10,
      padding = 10,
      gap = 2,
      align = "stretch",
    }, {
      ui.label({ text = "Você", fontSize = 9, fontWeight = "bold", color = "primary" }),
      ui.markdown({ text = message.text or "" }),
    })
  end

  local children = {}
  local headerChildren = {
    ui.glyph({ name = "sparkles", size = 13, color = "primary" }),
    ui.label({ text = "Assistente", fontSize = 9, fontWeight = "bold", color = mutedColor() }),
  }
  if message.streaming then
    table.insert(headerChildren, ui.label({ text = "…", color = "primary" }))
  end
  table.insert(children, ui.row({ gap = 6, align = "center" }, headerChildren))

  if message.reasoning and message.reasoning ~= "" then
    local expanded = expandedReasoning[message.id] == true
    table.insert(children, ui.button({
      text = expanded and "Ocultar raciocínio" or "Raciocínio",
      glyph = expanded and "chevron-up" or "chevron-down",
      variant = "ghost",
      fontSize = 9,
      onClick = function()
        expandedReasoning[message.id] = not expanded
        render()
      end,
    }))
    if expanded then
      table.insert(children, ui.markdown({ text = message.reasoning }))
    end
  end

  if message.text and message.text ~= "" then
    table.insert(children, ui.markdown({ text = message.text }))
  end

  for _, tool in ipairs(message.tools or {}) do
    table.insert(children, renderTool(tool))
  end

  if message.error and message.error ~= "" then
    table.insert(children, ui.label({ text = message.error, color = "error", fontSize = 11 }))
  end

  return ui.column({ gap = 6, align = "stretch" }, children)
end

local function composer()
  local action
  if snapshot and snapshot.state == "busy" then
    action = ui.button({ glyph = "player-stop", variant = "destructive", controlSize = "sm", tooltip = "Parar", onClick = "onStop" })
  else
    action = ui.button({ glyph = "send", variant = "primary", controlSize = "sm", tooltip = "Enviar (Enter)", onClick = "onSend" })
  end

  -- Input e botão lado a lado na mesma linha.
  return ui.row({
    gap = 6,
    align = "center",
    paddingH = 12,
    paddingV = 8,
    fill = "surface_variant/0.18",
    border = "outline/0.35",
    borderWidth = 1,
    radius = 12,
  }, {
    ui.input({
      key = "composer-" .. tostring(composerKey),
      value = draft,
      placeholder = "Pergunte sobre o sistema…",
      submitOnEnter = true,
      controlSize = "sm",
      frameVisible = false,
      focus = true,
      flexGrow = 1,
      onChange = "onDraftChange",
      onSubmit = "onSubmit",
    }),
    action,
  })
end

local function historyNotice(shown, total)
  return ui.label({
    text = "Mostrando as últimas " .. tostring(shown) .. " de " .. tostring(total) .. " mensagens.",
    fontSize = 9,
    color = mutedColor(),
    textAlign = "center",
  })
end

local function chatView()
  local children = {}
  local list = snapshot.messages or {}
  local total = tonumber(snapshot.messagesTotal) or #list
  if total > #list then
    table.insert(children, historyNotice(#list, total))
  end
  for _, message in ipairs(list) do
    table.insert(children, renderMessage(message))
  end
  if #children == 0 then
    table.insert(children, emptyState())
  end

  local pending = snapshot.pending or {}
  for _, permission in ipairs(pending.permissions or {}) do
    table.insert(children, renderPermission(permission))
  end
  for _, form in ipairs(pending.forms or {}) do
    table.insert(children, renderForm(form))
  end

  if snapshot.state == "busy" then
    table.insert(children, busyIndicator())
  end
  if snapshot.notice and snapshot.notice ~= "" then
    table.insert(children, ui.label({ text = snapshot.notice, fontSize = 10, color = "primary" }))
  end
  if snapshot.error and snapshot.error ~= "" then
    table.insert(children, ui.label({ text = snapshot.error, color = "error", fontSize = 10 }))
  end
  if snapshot.agentStatus == "missing" and snapshot.state ~= "busy" then
    table.insert(children, agentMissingCard())
  end

  local rootChildren = {
    header(),
    ui.scroll({ flexGrow = 1, stickToBottom = true, gap = 10, padding = 12 }, children),
    composer(),
  }
  if toast ~= "" and noctalia.nowMs() - toastAt < 5000 then
    table.insert(rootChildren, ui.label({ text = toast, color = "error", fontSize = 9, paddingH = 12 }))
  end
  return ui.column({ flexGrow = 1, gap = 6, align = "stretch" }, rootChildren)
end

local function onboardingView()
  local children = {
    ui.glyph({ name = "message-chatbot", size = 44, color = "primary" }),
    ui.label({ text = "Conecte o OpenCode", fontSize = 18, fontWeight = "bold", color = textColor() }),
    ui.label({
      text = "O chat conecta sozinho ao OpenCode local. Se precisar, rode `opencode pair` e cole o link abaixo.",
      fontSize = 12,
      color = mutedColor(),
      textAlign = "center",
      maxLines = 4,
    }),
    ui.button({ text = "Conectar automaticamente", variant = "primary", glyph = "plug", onClick = "onPairAuto" }),
    ui.input({
      key = "pair-link",
      placeholder = "Cole o link http://127.0.0.1:.../auth/connect/...",
      width = 380,
      height = 38,
      onSubmit = "onPairLinkSubmit",
      onChange = "onPairLinkChange",
      submitOnEnter = true,
    }),
    ui.row({ gap = 8, align = "center" }, {
      ui.button({ text = "Usar link colado", variant = "secondary", glyph = "link", onClick = "onPairLinkButton" }),
      ui.button({ text = "Colar da área de transferência", variant = "secondary", glyph = "clipboard", onClick = "onPastePairLink" }),
    }),
    ui.row({ gap = 8, align = "center" }, {
      ui.button({ text = "Copiar comando", variant = "ghost", glyph = "copy", onClick = "onCopyPairCommand" }),
      ui.button({ text = "Tentar novamente", variant = "ghost", glyph = "refresh", onClick = "onRetry" }),
    }),
  }
  if snapshot and snapshot.error and snapshot.error ~= "" then
    table.insert(children, ui.label({
      text = snapshot.error,
      color = "error",
      fontSize = 11,
      textAlign = "center",
      maxLines = 4,
    }))
  end
  return ui.column({ flexGrow = 1, gap = 14, padding = 20, align = "center", justify = "center" }, children)
end

local function offlineView()
  local children = {
    ui.glyph({ name = "cloud-off", size = 38, color = mutedColor() }),
    ui.label({ text = "OpenCode offline", fontSize = 16, fontWeight = "bold", color = textColor() }),
    ui.label({
      text = "O chat inicia o servidor local automaticamente. Se não conectar, abra o app OpenCode ou rode `opencode serve`.",
      fontSize = 12,
      color = mutedColor(),
      textAlign = "center",
      maxLines = 4,
    }),
    ui.button({ text = "Iniciar OpenCode", variant = "primary", glyph = "player-play", onClick = "onStartService" }),
    ui.button({ text = "Tentar novamente", variant = "secondary", glyph = "refresh", onClick = "onRetry" }),
    ui.button({ text = "Abrir terminal", variant = "ghost", glyph = "terminal-2", onClick = "onOpenTerminal" }),
  }
  if snapshot and snapshot.error and snapshot.error ~= "" then
    table.insert(children, ui.label({ text = snapshot.error, color = "error", fontSize = 10, maxLines = 3 }))
  end
  return ui.column({ flexGrow = 1, gap = 12, padding = 20, align = "center", justify = "center" }, children)
end

local function startingView()
  return ui.column({ flexGrow = 1, gap = 12, padding = 20, align = "center", justify = "center" }, {
    ui.glyph({ name = "loader-2", size = 36, color = "primary" }),
    ui.label({ text = "Iniciando o OpenCode…", fontSize = 15, fontWeight = "bold", color = textColor() }),
    ui.label({
      text = "Isso leva alguns segundos na primeira vez.",
      fontSize = 10,
      color = mutedColor(),
      textAlign = "center",
    }),
  })
end

local function pairingView()
  return ui.column({ flexGrow = 1, gap = 12, padding = 20, align = "center", justify = "center" }, {
    ui.glyph({ name = "loader-2", size = 36, color = "primary" }),
    ui.label({ text = "Pareando com o OpenCode…", color = mutedColor() }),
    ui.label({ text = "Isso deve levar só um instante.", fontSize = 10, color = mutedColor() }),
  })
end

local function syncPickerSelection()
  selectedModelIndex = 0
  selectedSessionIndex = 0
  selectedReasoningId = "default"
  local activeModel = snapshot and snapshot.session and snapshot.session.model or nil
  local activeModelMatched = false
  if activeModel then
    for i, model in ipairs(models) do
      if model.id == activeModel.id and model.providerID == activeModel.providerID then
        selectedModelIndex = i
        activeModelMatched = true
        break
      end
    end
  end
  local activeSession = snapshot and snapshot.session or nil
  if activeSession then
    for i, session in ipairs(sessions) do
      if session.id == activeSession.id then
        selectedSessionIndex = i
        break
      end
    end
  end
  if selectedModelIndex == 0 and #models > 0 then
    selectedModelIndex = 1
  end

  local currentModel = models[selectedModelIndex]
  local currentVariants = currentModel and currentModel.variants or {}
  if activeModelMatched and #currentVariants > 0 then
    local activeVariant = tostring(activeModel.variant or "")
    if activeVariant ~= "" and activeVariant ~= "default" then
      selectedReasoningId = activeVariant
    end
  end
end

local function modelText(model)
  local name = tostring(model.name or model.id or "modelo")
  local provider = tostring(model.providerID or "")
  if provider ~= "" then
    return name .. " · " .. provider
  end
  return name
end

local function containsReasoningId(list, id)
  for _, value in ipairs(list) do
    if value == id then
      return true
    end
  end
  return false
end

local function applySelectedModel()
  local model = models[selectedModelIndex]
  if model == nil then
    return
  end
  local payload = { id = model.id, providerID = model.providerID }
  local variants = model.variants or {}
  if #variants > 0 and selectedReasoningId ~= "" and selectedReasoningId ~= "default" then
    payload.variant = selectedReasoningId
  end
  sendCommand("set_model", noctalia.json.encode(payload))
end

local function sessionText(session)
  local title = tostring(session.title or "Nova conversa")
  local ago = format.timeAgo(session.updatedAt)
  if ago ~= "" then
    return title .. " · " .. ago
  end
  return title
end

local function pickerView()
  local children = {
    ui.row({
      gap = 8,
      align = "center",
      paddingH = 12,
      paddingV = 8,
      fill = "surface_variant/0.18",
      border = "outline/0.35",
      borderWidth = 1,
      radius = 12,
    }, {
      ui.button({ glyph = "arrow-left", variant = "ghost", tooltip = "Voltar ao chat", onClick = "onBackToChat" }),
      ui.column({ gap = 0, flexGrow = 1 }, {
        ui.label({ text = "Modelo e sessão", fontSize = 15, fontWeight = "bold", color = textColor() }),
        ui.label({ text = "Ajustes do chat", fontSize = 10, color = mutedColor() }),
      }),
      ui.button({ glyph = "minus", variant = "ghost", tooltip = "Minimizar", onClick = "onMinimize" }),
    }),
  }

  local modelOptions = {}
  for _, model in ipairs(models) do
    table.insert(modelOptions, modelText(model))
  end
  local hasModels = #modelOptions > 0
  if not hasModels then
    modelOptions = { "Nenhum modelo carregado" }
  end

  local currentModel = models[selectedModelIndex]
  local currentVariants = currentModel and currentModel.variants or {}

  local reasoningIds = {}
  local reasoningOptions = {}
  local reasoningIndex = 0
  if #currentVariants > 0 then
    table.insert(reasoningIds, "default")
    table.insert(reasoningOptions, "default")
    for _, variant in ipairs(currentVariants) do
      local id = tostring(variant.id or "")
      if id ~= "" and id ~= "default" and not containsReasoningId(reasoningIds, id) then
        table.insert(reasoningIds, id)
        table.insert(reasoningOptions, id)
      end
    end
    if selectedReasoningId ~= "" and not containsReasoningId(reasoningIds, selectedReasoningId) then
      table.insert(reasoningIds, selectedReasoningId)
      table.insert(reasoningOptions, selectedReasoningId)
    end
    for i, id in ipairs(reasoningIds) do
      if id == selectedReasoningId then
        reasoningIndex = i - 1
        break
      end
    end
  end

  local modelChildren = {
    ui.label({ text = "Modelo", fontSize = 10, color = mutedColor() }),
    ui.select({
      options = modelOptions,
      selectedIndex = hasModels and math.max(0, selectedModelIndex - 1) or 0,
      enabled = hasModels,
      onChange = function(index)
        local model = models[index + 1]
        if model == nil then
          return
        end
        local previousReasoning = selectedReasoningId
        selectedModelIndex = index + 1
        selectedReasoningId = "default"
        local variants = model.variants or {}
        if previousReasoning ~= "default" then
          for _, variant in ipairs(variants) do
            if tostring(variant.id or "") == previousReasoning then
              selectedReasoningId = previousReasoning
              break
            end
          end
        end
        applySelectedModel()
        render()
      end,
    }),
  }

  if #currentVariants > 0 then
    table.insert(modelChildren, ui.label({ text = "Raciocínio", fontSize = 10, color = mutedColor() }))
    table.insert(modelChildren, ui.select({
      key = "reasoning-"
        .. tostring(currentModel and currentModel.providerID or "")
        .. "/"
        .. tostring(currentModel and currentModel.id or ""),
      options = reasoningOptions,
      selectedIndex = reasoningIndex,
      onChange = function(index)
        local id = reasoningIds[index + 1]
        if id == nil then
          return
        end
        selectedReasoningId = id
        applySelectedModel()
        render()
      end,
    }))
  end

  table.insert(children, ui.column({
    gap = 8,
    padding = 12,
    fill = "surface_variant/0.18",
    border = "outline/0.35",
    borderWidth = 1,
    radius = 12,
    align = "stretch",
  }, modelChildren))

  table.insert(children, ui.separator({}))

  local sessionRows = {}
  for i, session in ipairs(sessions) do
    local selected = i == selectedSessionIndex
    local itemProps = {
      gap = 0,
      align = "center",
      paddingH = 10,
      paddingV = 9,
      radius = 10,
      flexGrow = 1,
      fill = selected and "primary" or "surface_variant/0.35",
      onClick = function()
        selectedSessionIndex = i
        deleteConfirm = nil
        sendCommand("select_session", session.id)
        view = "chat"
        render()
      end,
    }
    if not selected then
      itemProps.border = "outline/0.2"
      itemProps.borderWidth = 1
    end
    table.insert(sessionRows, ui.row({ gap = 6, align = "center", key = "session-" .. tostring(session.id) }, {
      ui.row(itemProps, {
        ui.label({
          text = sessionText(session),
          fontSize = 10,
          color = selected and "on_primary" or textColor(),
          maxLines = 1,
          flexGrow = 1,
        }),
      }),
      ui.button({
        glyph = "trash",
        variant = "ghost",
        tooltip = "Apagar esta sessão",
        onClick = function()
          selectedSessionIndex = i
          deleteConfirm = session.id
          render()
        end,
      }),
    }))
  end
  if #sessionRows == 0 then
    table.insert(sessionRows, ui.label({ text = "Nenhuma sessão ainda.", fontSize = 10, color = mutedColor() }))
  end

  table.insert(children, ui.column({ gap = 8, flexGrow = 1, paddingH = 12, align = "stretch" }, {
    ui.label({ text = "Sessões", fontSize = 10, color = mutedColor() }),
    ui.scroll({ flexGrow = 1, gap = 4 }, sessionRows),
  }))

  local bottom = {
    ui.button({
      text = "Posição e tamanho do painel",
      variant = "ghost",
      glyph = "settings",
      fontSize = 9,
      onClick = "onOpenSettings",
    }),
  }

  local selected = sessions[selectedSessionIndex]
  if selected then
    if deleteConfirm == selected.id then
      table.insert(bottom, ui.column({
        fill = "error/0.08",
        border = "error/0.45",
        borderWidth = 1,
        radius = 10,
        padding = 10,
        gap = 6,
        align = "stretch",
      }, {
        ui.label({
          text = "Apagar \"" .. tostring(selected.title or "sessão") .. "\"?",
          fontSize = 11,
          fontWeight = "bold",
          color = "error",
          maxLines = 2,
        }),
        ui.label({
          text = "A conversa será removida do OpenCode. O espelho local em sessions/ não é apagado.",
          fontSize = 9,
          color = mutedColor(),
          maxLines = 3,
        }),
        ui.row({ gap = 8, align = "center" }, {
          ui.button({ text = "Sim, apagar", variant = "destructive", fontSize = 10, onClick = "onConfirmDelete" }),
          ui.button({ text = "Cancelar", variant = "secondary", fontSize = 10, onClick = "onCancelDelete" }),
        }),
      }))
    else
      table.insert(bottom, ui.button({ text = "Apagar sessão", variant = "destructive", glyph = "trash", fontSize = 10, onClick = "onRequestDelete" }))
    end
  end

  table.insert(children, ui.column({ gap = 8, paddingH = 12, align = "stretch" }, bottom))

  return ui.column({ flexGrow = 1, gap = 8, align = "stretch", paddingV = 8 }, children)
end

-- Inset que o host aplica ao conteúdo do plugin: Style::panelPadding (14 px) ×
-- contentScale (1.0 por padrão). O frame usa esse valor como padding negativo
-- para o fundo preto cobrir também a borda/raio do painel.
local PANEL_INSET = 14

local function frame(content)
  -- Modo "theme": o host desenha o fundo/borda e o frame só organiza o conteúdo.
  if backgroundModeValue == "theme" then
    return ui.column({ flexGrow = 1, gap = 0, align = "stretch" }, { content })
  end
  -- Modo "black": fundo preto fixo cobrindo o painel inteiro (padding negativo
  -- alcança a borda/raio do tema). O alfa preserva a transparência e o blur.
  return ui.column({
    flexGrow = 1,
    gap = 0,
    align = "stretch",
    padding = -PANEL_INSET,
  }, {
    ui.column({
      flexGrow = 1,
      gap = 0,
      align = "stretch",
      fill = frameFill(),
      radius = 12,
      padding = PANEL_INSET,
    }, { content }),
  })
end

render = function()
  if not isOpen then
    return
  end
  if view == "picker" then
    panel.render(frame(pickerView()))
    return
  end
  if snapshot == nil then
    panel.render(frame(ui.column({ flexGrow = 1, gap = 8, align = "center", justify = "center" }, {
      ui.glyph({ name = "loader-2", size = 30, color = "primary" }),
      ui.label({ text = "Carregando…", color = mutedColor() }),
    })))
    return
  end
  if snapshot.state == "unpaired" then
    panel.render(frame(onboardingView()))
  elseif snapshot.state == "pairing" then
    panel.render(frame(pairingView()))
  elseif snapshot.state == "starting" then
    panel.render(frame(startingView()))
  elseif snapshot.state == "offline" then
    panel.render(frame(offlineView()))
  else
    panel.render(frame(chatView()))
  end
end

function onOpen(_context)
  isOpen = true
  spinnerAccum = 0
  panel.setWantsSecondTicks(true)
  panel.setNeedsFrameTick(true)
  noctalia.state.set("chat.panel_open", true)
  snapshot = noctalia.state.get("chat.snapshot") or snapshot
  composerKey = composerKey + 1
  sendCommand("sync")
  render()
end

function onClose()
  isOpen = false
  panel.setWantsSecondTicks(false)
  panel.setNeedsFrameTick(false)
  noctalia.state.set("chat.panel_open", false)
end

function onConfigChanged()
  refreshBackground()
  render()
end

function onIpc(event, _payload)
  if event == "refresh" then
    render()
  elseif event == "open_picker" then
    view = "picker"
    deleteConfirm = nil
    syncPickerSelection()
    render()
  elseif event == "back" then
    view = "chat"
    deleteConfirm = nil
    render()
  end
end

function update()
  if toast ~= "" and noctalia.nowMs() - toastAt > 5000 then
    toast = ""
    render()
  end
end

function onFrameTick(deltaMs)
  if not isOpen or view ~= "chat" or snapshot == nil or snapshot.state ~= "busy" then
    spinnerAccum = 0
    return
  end

  local delta = tonumber(deltaMs)
  if delta == nil or delta <= 0 then
    return
  end

  spinnerAccum = spinnerAccum + delta
  if spinnerAccum < 400 then
    return
  end

  spinnerAccum = spinnerAccum % 400
  spinnerFrame = (spinnerFrame % #spinnerFrames) + 1
  render()
end

function onMinimize()
  panel.close()
end

function onNewSession()
  local model = snapshot and snapshot.session and snapshot.session.model or nil
  local payload = "{}"
  if model and model.id then
    payload = noctalia.json.encode({ model = model })
  end
  sendCommand("new_session", payload)
  view = "chat"
  deleteConfirm = nil
  render()
end

function onOpenPicker()
  view = "picker"
  deleteConfirm = nil
  syncPickerSelection()
  sendCommand("sync")
  render()
end

function onBackToChat()
  view = "chat"
  deleteConfirm = nil
  render()
end

function onRequestDelete()
  local session = sessions[selectedSessionIndex]
  deleteConfirm = session and session.id or nil
  render()
end

function onConfirmDelete()
  local id = deleteConfirm
  deleteConfirm = nil
  if id then
    sendCommand("delete_session", id)
  end
  render()
end

function onCancelDelete()
  deleteConfirm = nil
  render()
end

function onStop()
  sendCommand("interrupt")
end

function onRetry()
  sendCommand("sync")
end

function onPairAuto()
  sendCommand("pair")
end

function onPairLinkChange(text)
  pairLinkDraft = text or ""
end

function onPairLinkSubmit(text)
  sendCommand("pair", text or pairLinkDraft)
end

function onPairLinkButton()
  if noctalia.string.trim(pairLinkDraft) == "" then
    toast = "Cole o link de `opencode pair` primeiro."
    toastAt = noctalia.nowMs()
    render()
    return
  end
  sendCommand("pair", pairLinkDraft)
end

function onPastePairLink()
  local text = noctalia.clipboardText()
  if not text or noctalia.string.trim(text) == "" then
    toast = "A área de transferência está vazia."
    toastAt = noctalia.nowMs()
    render()
    return
  end
  sendCommand("pair", text)
end

function onCopyPairCommand()
  noctalia.copyToClipboard("opencode pair", "text/plain")
  toast = "Comando copiado. Rode no terminal e cole o link aqui."
  toastAt = noctalia.nowMs()
  render()
end

function onOpenTerminal()
  -- Mantém o terminal aberto com o servidor em primeiro plano (diagnóstico).
  noctalia.runInTerminal("opencode serve")
end

function onStartService()
  sendCommand("start")
end

function onRetryAgent()
  sendCommand("refresh_agents")
end

function onOpenSettings()
  noctalia.openSettings()
end

function onDraftChange(text)
  draft = text or ""
end

function onSubmit(text)
  if snapshot and snapshot.state == "busy" then
    return
  end
  local value = noctalia.string.trim(text or draft)
  if value == "" then
    return
  end
  sendCommand("prompt", value)
  draft = ""
  composerKey = composerKey + 1
  render()
end

function onSend()
  onSubmit(draft)
end

noctalia.setUpdateInterval(1000)
noctalia.state.watch("chat.snapshot", function(value)
  if type(value) == "table" then
    snapshot = value
    if isOpen then
      render()
    end
  end
end)

noctalia.state.watch("chat.models", function(value)
  if type(value) == "table" then
    models = value
    if isOpen and view == "picker" then
      syncPickerSelection()
      render()
    end
  end
end)

noctalia.state.watch("chat.sessions", function(value)
  if type(value) == "table" then
    sessions = value
    if isOpen and view == "picker" then
      syncPickerSelection()
      render()
    end
  end
end)
