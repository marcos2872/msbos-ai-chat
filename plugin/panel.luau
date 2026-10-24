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
local toastError = false
local expandedTools = {}
local expandedPermissions = {}
local showAlwaysPermission = {}
local expandedReasoning = {}
local formDrafts = {}
local view = "chat"
local showPairAdvanced = false
local showTechnical = false
local sessionQuery = ""
local models = noctalia.state.get("chat.models") or {}
local sessions = noctalia.state.get("chat.sessions") or {}
local changes = noctalia.state.get("chat.changes") or {}
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

-- Caixa de mensagem multilinha (ajuste do plugin). Desligada por padrão.
local composerMultiline = false

local function refreshComposer()
  composerMultiline = noctalia.getConfig("composer_multiline") == true
end

refreshComposer()

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
  return backgroundModeValue == "theme" and "on_surface_variant" or "#D2D7E1"
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
      toastError = true
      render()
    end
  end)
  if not started then
    toast = "Não foi possível falar com o serviço do chat."
    toastAt = noctalia.nowMs()
    toastError = true
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
    return "não conectado"
  end
  if snapshot.state == "starting" then
    return "iniciando…"
  end
  if snapshot.state == "offline" then
    return "sem conexão"
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
    fontSize = 10,
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
      ui.row({
        gap = 10,
        align = "center",
        tooltip = "Abrir modelos e sessões",
        onClick = "onOpenPicker",
      }, {
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

-- Nome da ferramenta em execução na última mensagem (para o indicador de busy).
local function currentActivity()
  local list = snapshot and snapshot.messages or {}
  for i = #list, 1, -1 do
    local tools = list[i].tools or {}
    for j = #tools, 1, -1 do
      if tools[j].status == "running" then
        return tostring(tools[j].name or "ferramenta")
      end
    end
  end
  return nil
end

local function busyIndicator()
  local activity = currentActivity()
  return ui.row({ gap = 6, align = "center" }, {
    ui.label({
      text = spinnerFrames[spinnerFrame],
      width = 16,
      fontSize = 14,
      textAlign = "center",
      color = "primary",
    }),
    ui.label({
      text = activity and ("Executando: " .. format.toolLabel(activity) .. "…") or "Pensando…",
      fontSize = 10,
      color = mutedColor(),
      maxLines = 1,
    }),
  })
end

-- Exemplos em linguagem de quem não conhece niri/Noctalia: o agente traduz o
-- pedido para a configuração certa.
local EXAMPLES = {
  "Deixe as janelas mais afastadas",
  "Instale um programa",
  "Mude as cores do desktop",
}

-- Sem nenhum modelo, o OpenCode está instalado mas não tem conta de IA. A tela
-- explica em linguagem comum e oferece abrir o login num terminal.
local function noModelsCard()
  local children = {
    ui.row({ gap = 6, align = "center" }, {
      ui.glyph({ name = "key", size = 16, color = "tertiary" }),
      ui.label({ text = "Falta conectar uma conta de IA", fontSize = 12, fontWeight = "bold", color = textColor(), flexGrow = 1 }),
    }),
    ui.label({
      text = "O chat já está instalado, mas o assistente ainda não tem um modelo para responder. Conecte sua conta uma vez — depois é só conversar.",
      fontSize = 10,
      color = mutedColor(),
      maxLines = 5,
    }),
    ui.row({ gap = 8, align = "center" }, {
      ui.button({ text = "Conectar conta", variant = "primary", glyph = "plug", fontSize = 10, onClick = "onConnectAccount" }),
      ui.button({ text = "Já conectei", variant = "secondary", glyph = "refresh", fontSize = 10, onClick = "onRetryModels" }),
    }),
    ui.button({
      text = showTechnical and "Ocultar detalhes técnicos" or "Detalhes técnicos",
      variant = "ghost",
      fontSize = 10,
      onClick = "onToggleTechnical",
    }),
  }
  if showTechnical then
    table.insert(children, ui.markdown({
      text = "```text\nopencode auth login\nopencode models\n```",
    }))
  end
  return ui.column({
    fill = "tertiary/0.10",
    border = "tertiary/0.40",
    borderWidth = 1,
    radius = 10,
    padding = 12,
    gap = 8,
    align = "stretch",
  }, children)
end

local function emptyState()
  if #models == 0 then
    return ui.column({ gap = 10, align = "center", padding = 16 }, { noModelsCard() })
  end
  local chips = {}
  for _, example in ipairs(EXAMPLES) do
    table.insert(chips, ui.button({
      text = example,
      variant = "secondary",
      fontSize = 10,
      onClick = function()
        sendCommand("prompt", example)
      end,
    }))
  end
  return ui.column({ gap = 10, align = "center", padding = 20 }, {
    ui.glyph({ name = "sparkles", size = 34, color = "primary" }),
    ui.label({ text = "Pergunte sobre o seu sistema", fontSize = 16, fontWeight = "bold", color = textColor() }),
    ui.column({ gap = 6, align = "center" }, chips),
    ui.label({
      text = "Toda mudança é confirmada antes de ser aplicada.",
      fontSize = 10,
      color = mutedColor(),
      textAlign = "center",
    }),
  })
end

local function agentMissingCard()
  local children = {
    ui.row({ gap = 6, align = "center" }, {
      ui.glyph({ name = "alert-triangle", size = 15, color = "error" }),
      ui.label({ text = "Assistente especialista indisponível", fontWeight = "bold", color = "error", fontSize = 11 }),
    }),
    ui.label({
      text = "O chat tenta de novo sozinho em alguns segundos. Se continuar, rode o instalador novamente.",
      fontSize = 10,
      color = mutedColor(),
      maxLines = 4,
    }),
    ui.button({ text = "Verificar novamente", variant = "secondary", fontSize = 10, onClick = "onRetryAgent" }),
    ui.button({
      text = showTechnical and "Ocultar detalhes técnicos" or "Detalhes técnicos",
      variant = "ghost",
      fontSize = 10,
      onClick = "onToggleTechnical",
    }),
  }
  if showTechnical then
    table.insert(children, ui.label({
      text = "Agente msbos-chat ausente em ~/.config/opencode/agents/msbos-chat.md.",
      fontSize = 10,
      color = mutedColor(),
      maxLines = 2,
    }))
  end
  return ui.column({
    fill = "error/0.08",
    border = "error/0.45",
    borderWidth = 1,
    radius = 10,
    padding = 10,
    gap = 6,
    align = "stretch",
  }, children)
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
    ui.label({
      text = format.toolLabel(tool.name),
      fontSize = 10,
      fontWeight = "bold",
      color = textColor(),
      tooltip = tostring(tool.name or "tool"),
    }),
    ui.label({ text = format.toolStatusLabel(tool.status), fontSize = 10, color = color }),
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
      table.insert(children, ui.label({ text = input, fontSize = 10, color = mutedColor(), maxLines = 12 }))
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
      fontSize = 10,
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
        fontSize = 10,
        fontWeight = "bold",
        color = selected and "on_primary" or textColor(),
        maxLines = 2,
      }),
    }
    local description = tostring(option.description or "")
    if description ~= "" then
      table.insert(optionChildren, ui.label({
        text = description,
        fontSize = 10,
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

-- Nome do arquivo sem o caminho completo (o caminho fica no detalhe técnico).
local function baseName(path)
  local value = tostring(path or "")
  return value:match("([^/]+)$") or value
end

-- Resume o pedido em linguagem comum. O comando real continua disponível em
-- "Ver o comando": quem não lê shell aprova pelo resumo, não às cegas.
local function permissionSummary(permission)
  local action = tostring(permission.action or "")
  local resources = type(permission.resources) == "table" and permission.resources or {}
  local command = tostring(resources.command or "")
  local path = tostring(resources.path or resources.file or "")
  local url = tostring(resources.url or "")

  if command ~= "" then
    local pkg = command:match("msbos%-priv%s+dnf%-install%s+([%w%-%._]+)")
    if pkg then
      return "Instalar o programa " .. pkg
    end
    pkg = command:match("msbos%-priv%s+dnf%-remove%s+([%w%-%._]+)")
    if pkg then
      return "Remover o programa " .. pkg
    end
    if command:match("msbos%-priv%s+dnf%-upgrade") then
      return "Atualizar o sistema"
    end
    local verb, unit = command:match("msbos%-priv%s+svc%-(%w+)%s+([%w%-%._@]+)")
    if verb and unit then
      local label = "Reiniciar"
      if verb == "enable" then
        label = "Ativar"
      elseif verb == "disable" then
        label = "Desativar"
      end
      return label .. " o serviço " .. unit
    end
    if command:match("^%s*(dnf|rpm)%s") then
      return "Alterar programas instalados"
    end
    if command:match("^%s*(systemctl|service)%s") then
      return "Alterar um serviço do sistema"
    end
    if command:match("^%s*(cp|mv|install|mkdir|chmod|chown|rm)%s") then
      return "Alterar arquivos do sistema"
    end
    return "Executar um comando no sistema"
  end

  if url ~= "" then
    return "Acessar o site " .. url:gsub("^https?://", ""):sub(1, 60)
  end

  if path ~= "" then
    if action == "edit" or action == "write" then
      return "Editar o arquivo " .. baseName(path)
    elseif action == "read" then
      return "Ler o arquivo " .. baseName(path)
    end
  end

  local labels = {
    shell = "Executar um comando no sistema",
    bash = "Executar um comando no sistema",
    edit = "Editar um arquivo",
    write = "Editar um arquivo",
    read = "Ler um arquivo",
    webfetch = "Acessar um site",
  }
  return labels[action] or ("Usar a ferramenta " .. (action ~= "" and action or "desconhecida"))
end

local function renderPermission(permission)
  local summary = permissionSummary(permission)
  local children = {
    ui.row({ gap = 6, align = "center" }, {
      ui.glyph({ name = "shield-lock", size = 15, color = "tertiary" }),
      ui.label({
        text = "O assistente quer: " .. summary,
        fontSize = 11,
        fontWeight = "bold",
        color = textColor(),
        flexGrow = 1,
        maxLines = 2,
      }),
    }),
    ui.label({
      text = "Nada é aplicado sem a sua confirmação.",
      fontSize = 10,
      color = mutedColor(),
      maxLines = 2,
    }),
  }

  local detail = permissionDetail(permission)
  local expanded = expandedPermissions[permission.id] == true
  if detail ~= "" then
    table.insert(children, ui.button({
      text = expanded and "Ocultar o comando" or "Ver o comando",
      variant = "ghost",
      fontSize = 10,
      glyph = expanded and "chevron-up" or "chevron-down",
      onClick = function()
        expandedPermissions[permission.id] = not expanded
        render()
      end,
    }))
    if expanded then
      table.insert(children, ui.markdown({ text = "```text\n" .. detail .. "\n```" }))
      local message = tostring(permission.message or "")
      if message ~= "" then
        table.insert(children, ui.label({ text = message, fontSize = 10, color = mutedColor(), maxLines = 4 }))
      end
    end
  end

  local alwaysOpen = showAlwaysPermission[permission.id] == true
  table.insert(children, ui.row({ gap = 8, align = "center" }, {
    ui.button({
      text = "Permitir uma vez",
      variant = "primary",
      fontSize = 10,
      onClick = function()
        expandedPermissions[permission.id] = nil
        showAlwaysPermission[permission.id] = nil
        sendCommand("reply_permission", noctalia.json.encode({ requestID = permission.id, decision = "once" }))
      end,
    }),
    ui.button({
      text = "Recusar",
      variant = "destructive",
      fontSize = 10,
      onClick = function()
        expandedPermissions[permission.id] = nil
        showAlwaysPermission[permission.id] = nil
        sendCommand("reply_permission", noctalia.json.encode({ requestID = permission.id, decision = "reject" }))
      end,
    }),
    ui.button({
      text = alwaysOpen and "Menos opções" or "Mais opções",
      variant = "ghost",
      fontSize = 10,
      onClick = function()
        showAlwaysPermission[permission.id] = not alwaysOpen
        render()
      end,
    }),
  }))

  -- "Sempre" fica atrás de uma camada com aviso: é a única opção que desliga a
  -- confirmação, e o alcance é definido pelo servidor, não pelo painel.
  if alwaysOpen then
    table.insert(children, ui.column({
      fill = "error/0.08",
      border = "error/0.35",
      borderWidth = 1,
      radius = 8,
      padding = 8,
      gap = 6,
      align = "stretch",
    }, {
      ui.label({
        text = "Permitir sempre salva esta aprovação no assistente (o alcance é definido por ele, não pelo painel): ele pode repetir a ação sem perguntar. O ajuste “Confirmação” vale para os próximos pedidos; para revogar um “sempre” já salvo, use as permissões salvas do OpenCode.",
        fontSize = 10,
        color = mutedColor(),
        maxLines = 6,
      }),
      ui.button({
        text = "Permitir sempre",
        variant = "secondary",
        fontSize = 10,
        onClick = function()
          expandedPermissions[permission.id] = nil
          showAlwaysPermission[permission.id] = nil
          sendCommand("reply_permission", noctalia.json.encode({ requestID = permission.id, decision = "always" }))
        end,
      }),
    }))
  end

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

local function renderMessage(message, isLast)
  if message.role == "user" then
    local ago = format.timeAgo(message.time)
    local header = {
      ui.label({ text = "Você", fontSize = 10, fontWeight = "bold", color = "primary" }),
    }
    if ago ~= "" then
      table.insert(header, ui.spacer({ flexGrow = 1 }))
      table.insert(header, ui.label({ text = ago, fontSize = 10, color = mutedColor() }))
    end
    return ui.column({
      fill = "primary/0.12",
      radius = 10,
      padding = 10,
      gap = 2,
      align = "stretch",
    }, {
      ui.row({ gap = 6, align = "center" }, header),
      ui.markdown({ text = message.text or "" }),
    })
  end

  local children = {}
  local ago = format.timeAgo(message.time)
  local headerChildren = {
    ui.glyph({ name = "sparkles", size = 13, color = "primary" }),
    ui.label({ text = "Assistente", fontSize = 10, fontWeight = "bold", color = mutedColor() }),
  }
  if message.streaming then
    table.insert(headerChildren, ui.label({ text = "…", color = "primary" }))
  elseif ago ~= "" then
    table.insert(headerChildren, ui.label({ text = ago, fontSize = 10, color = mutedColor() }))
  end
  table.insert(headerChildren, ui.spacer({ flexGrow = 1 }))
  if isLast and not message.streaming and snapshot and snapshot.state ~= "busy" then
    table.insert(headerChildren, ui.button({
      text = "Regenerar",
      glyph = "refresh",
      variant = "ghost",
      fontSize = 10,
      tooltip = "Reenvia o último pedido para gerar outra resposta",
      onClick = function()
        sendCommand("regenerate")
      end,
    }))
  end
  if message.text and message.text ~= "" then
    table.insert(headerChildren, ui.button({
      glyph = "copy",
      variant = "ghost",
      fontSize = 10,
      tooltip = "Copiar resposta",
      onClick = function()
        noctalia.copyToClipboard(message.text, "text/plain")
        toast = "Resposta copiada."
    toastError = false
        toastAt = noctalia.nowMs()
        render()
      end,
    }))
  end
  table.insert(children, ui.row({ gap = 6, align = "center" }, headerChildren))

  if message.reasoning and message.reasoning ~= "" then
    local expanded = expandedReasoning[message.id] == true
    table.insert(children, ui.button({
      text = expanded and "Ocultar raciocínio" or "Raciocínio",
      glyph = expanded and "chevron-up" or "chevron-down",
      variant = "ghost",
      fontSize = 10,
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
      multiline = composerMultiline,
      controlSize = (not composerMultiline) and "sm" or nil,
      height = composerMultiline and 64 or nil,
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
  return ui.row({ gap = 8, align = "center", justify = "center" }, {
    ui.label({
      text = "Mostrando as últimas " .. tostring(shown) .. " de " .. tostring(total) .. " mensagens.",
      fontSize = 10,
      color = mutedColor(),
    }),
    ui.button({
      text = "Carregar anteriores",
      variant = "ghost",
      fontSize = 10,
      onClick = function()
        sendCommand("load_previous")
      end,
    }),
  })
end

local function chatView()
  local children = {}
  local list = snapshot.messages or {}
  local total = tonumber(snapshot.messagesTotal) or #list
  if total > #list then
    table.insert(children, historyNotice(#list, total))
  end
  for index, message in ipairs(list) do
    table.insert(children, renderMessage(message, index == #list))
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
    table.insert(rootChildren, ui.label({ text = toast, color = toastError and "error" or "primary", fontSize = 10, paddingH = 12 }))
  end
  return ui.column({ flexGrow = 1, gap = 6, align = "stretch" }, rootChildren)
end

local function onboardingView()
  local children = {
    ui.glyph({ name = "message-chatbot", size = 44, color = "primary" }),
    ui.label({ text = "Conecte o assistente", fontSize = 18, fontWeight = "bold", color = textColor() }),
    ui.label({
      text = "O chat conecta sozinho ao assistente do seu computador. Clique no botão abaixo — se não funcionar, abra Avançado para colar o link de conexão.",
      fontSize = 12,
      color = mutedColor(),
      textAlign = "center",
      maxLines = 4,
    }),
    ui.button({ text = "Conectar agora", variant = "primary", glyph = "plug", onClick = "onPairAuto" }),
    ui.button({
      text = showPairAdvanced and "Ocultar avançado" or "Avançado",
      variant = "ghost",
      glyph = showPairAdvanced and "chevron-up" or "chevron-down",
      onClick = "onToggleAdvancedPairing",
    }),
  }
  if showPairAdvanced then
    table.insert(children, ui.label({
      text = "Detalhes técnicos: o link aparece ao rodar `opencode pair` no terminal.",
      fontSize = 10,
      color = mutedColor(),
      textAlign = "center",
      maxLines = 2,
    }))
    table.insert(children, ui.input({
      key = "pair-link",
      placeholder = "Cole o link http://127.0.0.1:.../auth/connect/...",
      width = 380,
      height = 38,
      onSubmit = "onPairLinkSubmit",
      onChange = "onPairLinkChange",
      submitOnEnter = true,
    }))
    table.insert(children, ui.row({ gap = 8, align = "center" }, {
      ui.button({ text = "Usar link colado", variant = "secondary", glyph = "link", onClick = "onPairLinkButton" }),
      ui.button({ text = "Colar da área de transferência", variant = "secondary", glyph = "clipboard", onClick = "onPastePairLink" }),
    }))
    table.insert(children, ui.row({ gap = 8, align = "center" }, {
      ui.button({ text = "Copiar comando", variant = "ghost", glyph = "copy", onClick = "onCopyPairCommand" }),
      ui.button({ text = "Tentar novamente", variant = "ghost", glyph = "refresh", onClick = "onRetry" }),
    }))
  end
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
    ui.label({ text = "Assistente sem resposta", fontSize = 16, fontWeight = "bold", color = textColor() }),
    ui.label({
      text = "O chat vai tentar iniciar o assistente de novo. Isso costuma resolver em alguns segundos.",
      fontSize = 12,
      color = mutedColor(),
      textAlign = "center",
      maxLines = 4,
    }),
    ui.button({ text = "Iniciar assistente", variant = "primary", glyph = "player-play", onClick = "onStartService" }),
    ui.button({ text = "Tentar novamente", variant = "secondary", glyph = "refresh", onClick = "onRetry" }),
    ui.button({
      text = showTechnical and "Ocultar detalhes técnicos" or "Detalhes técnicos",
      variant = "ghost",
      fontSize = 10,
      onClick = "onToggleTechnical",
    }),
  }
  if showTechnical then
    table.insert(children, ui.markdown({
      text = "```text\nopencode service status\nopencode serve\n```",
    }))
    table.insert(children, ui.button({ text = "Abrir terminal", variant = "ghost", glyph = "terminal-2", onClick = "onOpenTerminal" }))
  end
  if snapshot and snapshot.error and snapshot.error ~= "" then
    table.insert(children, ui.label({ text = snapshot.error, color = "error", fontSize = 10, maxLines = 3 }))
  end
  return ui.column({ flexGrow = 1, gap = 12, padding = 20, align = "center", justify = "center" }, children)
end

local function startingView()
  return ui.column({ flexGrow = 1, gap = 12, padding = 20, align = "center", justify = "center" }, {
    ui.glyph({ name = "loader-2", size = 36, color = "primary" }),
    ui.label({ text = "Iniciando o assistente…", fontSize = 15, fontWeight = "bold", color = textColor() }),
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
    ui.label({ text = "Conectando ao assistente…", color = mutedColor() }),
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

-- Agrupa a sessão por data a partir de `updatedAt` (segundos para formatTime).
local function dateBucket(ms)
  local value = tonumber(ms) or 0
  if value <= 0 then
    return "Mais antigas"
  end
  local now = noctalia.nowMs()
  local day = noctalia.formatTime("%Y-%m-%d", math.floor(value / 1000))
  if day == noctalia.formatTime("%Y-%m-%d", math.floor(now / 1000)) then
    return "Hoje"
  end
  if day == noctalia.formatTime("%Y-%m-%d", math.floor((now - 86400000) / 1000)) then
    return "Ontem"
  end
  if value >= now - 7 * 86400000 then
    return "Últimos 7 dias"
  end
  return "Mais antigas"
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

  local modelChildren
  if hasModels then
    modelChildren = {
      ui.label({ text = "Modelo", fontSize = 10, color = mutedColor() }),
      ui.select({
        options = modelOptions,
        selectedIndex = math.max(0, selectedModelIndex - 1),
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
  else
    -- Sem conta de IA: em vez de um select desabilitado, explica o que fazer.
    modelChildren = { noModelsCard() }
  end

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
    table.insert(modelChildren, ui.label({
      text = "Valores menores respondem mais rápido; maiores, com mais detalhe.",
      fontSize = 10,
      color = mutedColor(),
      maxLines = 2,
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

  local order = { "Hoje", "Ontem", "Últimos 7 dias", "Mais antigas" }
  local buckets = {}
  local query = string.lower(tostring(sessionQuery or ""))
  local shown = 0
  for i, session in ipairs(sessions) do
    local title = string.lower(tostring(session.title or "Nova conversa"))
    if query == "" or title:find(query, 1, true) then
      local bucket = dateBucket(session.updatedAt)
      buckets[bucket] = buckets[bucket] or {}
      table.insert(buckets[bucket], { index = i, session = session })
      shown = shown + 1
    end
  end

  local sessionRows = {}
  local function addSessionRow(index, session)
    local selected = index == selectedSessionIndex
    local itemProps = {
      gap = 0,
      align = "center",
      paddingH = 10,
      paddingV = 9,
      radius = 10,
      flexGrow = 1,
      fill = selected and "primary" or "surface_variant/0.35",
      onClick = function()
        selectedSessionIndex = index
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
          selectedSessionIndex = index
          deleteConfirm = session.id
          render()
        end,
      }),
    }))
  end

  for _, bucket in ipairs(order) do
    local items = buckets[bucket]
    if items then
      table.insert(sessionRows, ui.label({ text = bucket, fontSize = 10, fontWeight = "bold", color = mutedColor() }))
      for _, item in ipairs(items) do
        addSessionRow(item.index, item.session)
      end
    end
  end
  if shown == 0 then
    table.insert(sessionRows, ui.label({
      text = query ~= "" and "Nenhuma sessão encontrada." or "Nenhuma sessão ainda.",
      fontSize = 10,
      color = mutedColor(),
    }))
  end

  table.insert(children, ui.column({ gap = 8, flexGrow = 1, paddingH = 12, align = "stretch" }, {
    ui.label({ text = "Sessões", fontSize = 10, color = mutedColor() }),
    ui.input({
      key = "session-search",
      value = sessionQuery,
      placeholder = "Buscar sessão…",
      controlSize = "sm",
      frameVisible = false,
      onChange = "onSessionQueryChange",
    }),
    ui.scroll({ flexGrow = 1, gap = 4 }, sessionRows),
  }))

  local bottom = {
    ui.button({
      text = "Alterações no sistema",
      variant = "ghost",
      glyph = "history-toggle",
      fontSize = 10,
      onClick = "onOpenChanges",
    }),
    ui.button({
      text = "Posição e tamanho do painel",
      variant = "ghost",
      glyph = "settings",
      fontSize = 10,
      onClick = "onOpenSettings",
    }),
    ui.label({
      text = "As conversas ficam salvas em ~/.msbos-ai-chat; só o seu usuário lê.",
      fontSize = 10,
      color = mutedColor(),
      maxLines = 2,
      paddingH = 2,
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
          text = "A conversa será removida do assistente. A cópia local não é apagada.",
          fontSize = 10,
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

-- Histórico de alterações do sistema (log da skill msbos), com desfazer.
local function changesView()
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
        ui.label({ text = "Alterações no sistema", fontSize = 15, fontWeight = "bold", color = textColor() }),
        ui.label({ text = "O que mudou e como desfazer", fontSize = 10, color = mutedColor() }),
      }),
      ui.button({ glyph = "minus", variant = "ghost", tooltip = "Minimizar", onClick = "onMinimize" }),
    }),
  }

  if #changes == 0 then
    table.insert(children, ui.column({ gap = 8, align = "center", padding = 20, justify = "center", flexGrow = 1 }, {
      ui.glyph({ name = "history-toggle", size = 32, color = mutedColor() }),
      ui.label({ text = "Nenhuma alteração registrada ainda.", fontSize = 12, fontWeight = "bold", color = textColor() }),
      ui.label({
        text = "Quando o assistente mudar algo no seu sistema, o registro aparece aqui com a forma de desfazer.",
        fontSize = 10,
        color = mutedColor(),
        textAlign = "center",
        maxLines = 4,
      }),
    }))
  else
    local rows = {}
    for index, change in ipairs(changes) do
      local undo = tostring(change.undo or "")
      table.insert(rows, ui.column({
        fill = "surface_variant/0.18",
        border = "outline/0.35",
        borderWidth = 1,
        radius = 10,
        padding = 10,
        gap = 6,
        align = "stretch",
      }, {
        ui.label({ text = tostring(change.when or ""), fontSize = 10, color = mutedColor() }),
        ui.label({ text = tostring(change.what or ""), fontSize = 10, color = textColor(), maxLines = 5 }),
        (function()
          local actions = {
            ui.button({
              text = "Pedir para desfazer",
              variant = "secondary",
              fontSize = 10,
              glyph = "arrow-back-up",
              onClick = function()
                onUndoChange(index)
              end,
            }),
          }
          if undo ~= "" then
            table.insert(actions, ui.button({
              text = "Copiar comando",
              variant = "ghost",
              fontSize = 10,
              glyph = "copy",
              tooltip = undo,
              onClick = function()
                onCopyUndo(index)
              end,
            }))
          end
          return ui.row({ gap = 8, align = "center" }, actions)
        end)(),
      }))
    end
    table.insert(children, ui.scroll({ flexGrow = 1, gap = 8, paddingH = 12 }, rows))
  end

  table.insert(children, ui.label({
    text = "Registro: ~/.local/state/msbos/agent-changes.log",
    fontSize = 10,
    color = mutedColor(),
    paddingH = 12,
  }))

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
  if view == "changes" then
    panel.render(frame(changesView()))
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
  refreshComposer()
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
  elseif event == "open_changes" then
    onOpenChanges()
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

function onSessionQueryChange(text)
  sessionQuery = text or ""
  render()
end

function onOpenChanges()
  view = "changes"
  sendCommand("refresh_changes")
  render()
end

-- Pede ao assistente para desfazer. Ele explica e passa pelo cartão de
-- permissão como qualquer outra ação — o painel não executa nada sozinho.
function onUndoChange(index)
  local change = changes[index]
  if change == nil then
    return
  end
  local what = tostring(change.what or "")
  local undo = tostring(change.undo or "")
  local text = "Desfaça esta mudança que você fez no sistema"
  if what ~= "" then
    text = text .. ": " .. what
  end
  if undo ~= "" then
    text = text .. "\n\nForma de desfazer registrada: " .. undo
  end
  text = text .. "\n\nExplique em uma frase o que vai fazer, peça minha confirmação e valide o resultado depois."
  view = "chat"
  sendCommand("prompt", text)
  render()
end

function onCopyUndo(index)
  local change = changes[index]
  local undo = change and tostring(change.undo or "") or ""
  if undo == "" then
    return
  end
  noctalia.copyToClipboard(undo, "text/plain")
  toast = "Comando de desfazer copiado."
    toastError = false
  toastAt = noctalia.nowMs()
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

function onToggleAdvancedPairing()
  showPairAdvanced = not showPairAdvanced
  render()
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
    toastError = true
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
    toastError = true
    render()
    return
  end
  sendCommand("pair", text)
end

function onCopyPairCommand()
  noctalia.copyToClipboard("opencode pair", "text/plain")
  toast = "Comando copiado. Rode no terminal e cole o link aqui."
    toastError = false
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

-- Abre o login da conta de IA num terminal (é interativo; não dá para fazer
-- dentro do painel). Ao terminar, "Já conectei" recarrega o catálogo.
function onConnectAccount()
  noctalia.runInTerminal("opencode auth login")
end

function onRetryModels()
  -- `sync` só republica o catálogo em memória; `refresh_models` recarrega do
  -- servidor (necessário depois de `opencode auth login`).
  sendCommand("refresh_models")
  toast = "Verificando os modelos de novo…"
  toastAt = noctalia.nowMs()
  toastError = false
  render()
end

function onToggleTechnical()
  showTechnical = not showTechnical
  render()
end

function onOpenSettings()
  noctalia.openSettings()
end

function onDraftChange(text)
  draft = text or ""
end

function onSubmit(text)
  if snapshot and snapshot.state == "busy" then
    toast = "Aguarde a resposta terminar (ou pare) antes de enviar outra mensagem."
    toastAt = noctalia.nowMs()
    toastError = true
    render()
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

noctalia.state.watch("chat.changes", function(value)
  if type(value) == "table" then
    changes = value
    if isOpen and view == "changes" then
      render()
    end
  end
end)
