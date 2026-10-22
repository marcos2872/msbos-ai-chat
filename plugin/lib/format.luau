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

function M.toolGlyph(name)
  local map = {
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
