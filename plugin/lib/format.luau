--!nonstrict
-- Formatação de textos, modelos, ferramentas e erros para o chat.

local M = {}

function M.truncate(text, max)
  if text == nil then
    return ""
  end
  if type(text) ~= "string" then
    local ok, encoded = pcall(noctalia.json.encode, text)
    text = ok and encoded or tostring(text)
  end
  max = tonumber(max) or 4000
  if #text > max then
    local cut = max
    -- `sub` corta bytes: recua até uma fronteira de caractere UTF-8 para não
    -- terminar no meio de uma sequência multi-byte (acentos, emoji).
    while cut > 0 do
      local byte = text:byte(cut + 1)
      if byte == nil or byte < 0x80 or byte > 0xBF then
        break
      end
      cut = cut - 1
    end
    return text:sub(1, cut) .. "\n… (truncado)"
  end
  return text
end

function M.toolInput(input)
  if input == nil then
    return ""
  end
  if type(input) == "string" then
    return M.truncate(input, 1200)
  end
  local ok, encoded = pcall(noctalia.json.encode, input, true)
  if not ok or not encoded then
    return ""
  end
  return M.truncate(encoded, 1200)
end

function M.errorText(err)
  if err == nil then
    return ""
  end
  if type(err) == "string" then
    return err
  end
  if type(err) == "table" then
    if type(err.message) == "string" and err.message ~= "" then
      return err.message
    end
    if type(err.data) == "table" and type(err.data.message) == "string" then
      return err.data.message
    end
    if type(err.name) == "string" and err.name ~= "" then
      return err.name
    end
    local ok, encoded = pcall(noctalia.json.encode, err)
    return ok and encoded or "Erro"
  end
  return tostring(err)
end

function M.modelLabel(model)
  if type(model) ~= "table" then
    return ""
  end
  local provider = model.providerID or ""
  local id = model.id or ""
  local variant = tostring(model.variant or "")
  local label = ""
  if provider ~= "" and id ~= "" then
    label = provider .. "/" .. id
  elseif id ~= "" then
    label = id
  else
    label = provider
  end
  if label ~= "" and variant ~= "" and variant ~= "default" then
    label = label .. " · " .. variant
  end
  return label
end

function M.toolStatusLabel(status)
  if status == "completed" or status == "ok" then
    return "ok"
  end
  if status == "error" then
    return "erro"
  end
  if status == "running" then
    return "executando"
  end
  if status == "streaming" then
    return "preparando"
  end
  return tostring(status or "")
end

-- Nome da ferramenta em linguagem comum (o nome técnico fica no tooltip).
function M.toolLabel(name)
  local map = {
    read = "Ler arquivo",
    edit = "Editar arquivo",
    write = "Editar arquivo",
    shell = "Executar comando",
    bash = "Executar comando",
    grep = "Procurar no texto",
    rg = "Procurar no texto",
    glob = "Procurar arquivo",
    find = "Procurar arquivo",
    list = "Listar arquivos",
    webfetch = "Acessar site",
    task = "Consultar outro assistente",
    skill = "Consultar instruções",
  }
  local key = tostring(name or "")
  return map[key] or ("Ferramenta: " .. key)
end

-- Título em linguagem comum para uma linha do agent-changes.log. O texto
-- original continua disponível em "Ver detalhes"; aqui só traduzimos o tipo.
function M.changeTitle(what)
  local text = tostring(what or "")
  local low = text:lower()
  local function limpa(value)
    return (tostring(value or ""):gsub("%s+$", ""))
  end

  -- "install | htop-3.4.1-3.fc44 ..." e "dnf-install btop".
  local pkg = text:match("^install%s*|%s*([%w%-%._]+)")
  if pkg then
    return "Instalou o programa " .. limpa((pkg:gsub("%-%d.*$", "")))
  end
  pkg = text:match("dnf%-install%s+([%w%-%._]+)")
  if pkg then
    return "Instalou o programa " .. pkg
  end
  pkg = text:match("dnf%-remove%s+([%w%-%._]+)")
  if pkg then
    return "Removeu o programa " .. pkg
  end
  if text:find("dnf%-upgrade") or (low:find("atualiza") and low:find("sistema")) then
    return "Atualizou o sistema"
  end

  local app = text:match("[Aa]utostart:%s*desativado%s+(.-)%s*%(")
  if app then
    return "Desativou a inicialização automática do " .. limpa(app)
  end
  app = text:match("[Aa]utostart:%s*ativado%s+(.-)%s*%(")
  if app then
    return "Ativou a inicialização automática do " .. limpa(app)
  end

  if low:find("wallpaper") then
    return "Trocou o papel de parede"
  end
  if text:find("layout%.gaps") or text:find("config%.kdl.*gaps") then
    return "Ajustou o espaçamento das janelas"
  end

  if low:find("paleta") then
    -- Só usa a seta quando a linha é sobre a paleta em si; em "terminal blue ->
    -- roxo" a seta enganaria o resumo.
    if text:match("^[Pp]aleta") then
      local from, to = text:match("([%w%-]+)%s*%-%>%s*([%w%-]+)")
      if from and to then
        return "Trocou as cores do sistema (" .. from .. " → " .. to .. ")"
      end
    end
    local de, para = text:match("muda de%s+([%w%-]+).-para%s+([%w%-]+)")
    if de and para then
      return "Trocou as cores do sistema (" .. de .. " → " .. para .. ")"
    end
    local nome = text:match("paleta pessoal%s+([%w%-]+)")
    if nome then
      return "Criou a paleta de cores " .. nome
    end
    return "Trocou as cores do sistema"
  end

  local removido = text:match("[Rr]emovidos?%s+([^%(]+)")
  if removido then
    return "Removeu o " .. limpa(removido)
  end
  local instalado = text:match("^[Ii]nstalado%s+([^%(]+)")
  if instalado then
    -- Corta a versão no fim ("JetBrains Toolbox 3.9.0.88839").
    local nome = limpa(instalado):gsub("%s+%d[%w%.-]*$", "")
    return "Instalou o " .. limpa(nome)
  end
  -- "instalado htop ... via dnf-install": sem nome capturado antes, mas ainda
  -- é uma instalação.
  if low:find("dnf%-install") then
    return "Instalou um programa"
  end
  if low:find("dnf%-remove") then
    return "Removeu um programa"
  end
  if low:find("servi[çc]o") or text:find("systemctl") then
    return "Alterou um serviço do sistema"
  end
  if low:find("revers") then
    return "Desfez uma mudança anterior"
  end

  return "Alterou o sistema"
end

-- Data amigável: "hoje, 16:50", "ontem, 15:22" ou "24/10, 16:50".
function M.changeWhen(when)
  local text = tostring(when or "")
  local date = text:match("^(%d%d%d%d%-%d%d%-%d%d)")
  local time = text:match("(%d%d:%d%d)")
  if not date or not time then
    return text
  end
  local now = noctalia.nowMs()
  if date == noctalia.formatTime("%Y-%m-%d", math.floor(now / 1000)) then
    return "hoje, " .. time
  end
  if date == noctalia.formatTime("%Y-%m-%d", math.floor((now - 86400000) / 1000)) then
    return "ontem, " .. time
  end
  local year, month, day = date:match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
  return day .. "/" .. month .. ", " .. time
end

function M.toolGlyph(name)  local map = {
    read = "file-text",
    edit = "pencil",
    write = "pencil",
    shell = "terminal-2",
    bash = "terminal-2",
    grep = "search",
    rg = "search",
    glob = "folder-search",
    find = "folder-search",
    list = "list",
    webfetch = "world",
    task = "users",
    skill = "sparkles",
  }
  return map[tostring(name or "")] or "tool"
end

function M.timeAgo(ms)
  local value = tonumber(ms) or 0
  if value <= 0 then
    return ""
  end
  local diff = math.max(0, noctalia.nowMs() - value)
  if diff < 60000 then
    return "agora"
  end
  if diff < 3600000 then
    return string.format("%dm", math.floor(diff / 60000))
  end
  if diff < 86400000 then
    return string.format("%dh", math.floor(diff / 3600000))
  end
  return string.format("%dd", math.floor(diff / 86400000))
end

return M
