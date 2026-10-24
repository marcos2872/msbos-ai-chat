--!nonstrict
-- Workspace e persistência do chat: pairing.json, ui.json, sessões espelhadas.

local format = require("./format.luau")

local M = {}

local AGENTS_MD = [=[
# msbos AI Chat — workspace

Este diretório é o workspace do chat de IA do msbos.
As sessões do chat são escopadas aqui.

## Regras

- Antes de propor ou executar qualquer mudança no sistema, carregue a skill `msbos`.
- Leia `~/.agents/skills/msbos/references/local.md` no início.
- Descreva a mudança, peça confirmação explícita e espere o "sim".
- Root somente via `pkexec /usr/local/libexec/msbos-priv <subcomando>`.
- Nunca use `sudo` — nem para consultar.
- Faça backup, valide (`niri validate`, `rpm -q`) e mostre o diff.
- Registre em `~/.local/state/msbos/agent-changes.log`.
- Responda em português brasileiro.
]=]

function M.ensure(directory)
  local root = noctalia.expandPath(directory or "~/.msbos-ai-chat")
  noctalia.mkdirAll(root)
  noctalia.mkdirAll(root .. "/state")
  noctalia.mkdirAll(root .. "/sessions")
  -- Reforça 0700: o install.sh faz isso para o caminho padrão; aqui cobre o
  -- `directory` customizado e um workspace criado pelo próprio plugin.
  for _, dir in ipairs({ root, root .. "/state", root .. "/sessions" }) do
    noctalia.runAsync({ "chmod", "700", dir })
  end
  local agents = root .. "/AGENTS.md"
  if not noctalia.fileExists(agents) then
    noctalia.writeFile(agents, AGENTS_MD)
  end
  return root
end

function M.paths(directory)
  local root = noctalia.expandPath(directory or "~/.msbos-ai-chat")
  return {
    root = root,
    state = root .. "/state",
    sessions = root .. "/sessions",
    pairing = root .. "/state/pairing.json",
    ui = root .. "/state/ui.json",
    index = root .. "/sessions/index.json",
  }
end

function M.readJson(path)
  local raw = noctalia.readFile(path)
  if not raw or raw == "" then
    return nil
  end
  local value = noctalia.json.decode(raw)
  if type(value) == "table" then
    return value
  end
  return nil
end

-- Escrita restrita: grava num temporário e usa `install -m <mode>` para o
-- destino já nascer com o modo certo e de forma atômica — evita a janela em que
-- o arquivo (ex.: pairing.json, com o token) ficaria 0644 entre o writeFile e o
-- chmod assíncrono. Os caminhos vão como argumentos posicionais ($1/$2/$3),
-- nunca interpolados, então não há injeção de shell.
function M.writeFileMode(path, content, mode)
  if not mode then
    return noctalia.writeFile(path, content)
  end
  local tmp = path .. ".tmp"
  local ok, err = noctalia.writeFile(tmp, content)
  if not ok then
    return false, err
  end
  local started = noctalia.runAsync({
    "sh",
    "-c",
    'install -m "$3" -- "$1" "$2" && rm -f -- "$1"',
    "msbos-write",
    tmp,
    path,
    tostring(mode),
  }, function(result)
    if result and result.exitCode ~= 0 then
      noctalia.log("msbos-ai-chat: falha na escrita restrita de " .. path .. ": " .. tostring(result.stderr))
    end
  end)
  if not started then
    noctalia.removeFile(tmp)
    return false, "falha ao agendar a escrita restrita"
  end
  return true
end

function M.writeJson(path, value, mode)
  local encoded = noctalia.json.encode(value, true)
  if not encoded then
    return false, "falha ao codificar JSON"
  end
  return M.writeFileMode(path, encoded, mode)
end

function M.readPairing(directory)
  local value = M.readJson(M.paths(directory).pairing)
  if type(value) == "table" and type(value.baseUrl) == "string" and type(value.token) == "string" then
    return value
  end
  return nil
end

function M.writePairing(directory, pairing)
  return M.writeJson(M.paths(directory).pairing, pairing, "600")
end

function M.clearPairing(directory)
  return noctalia.removeFile(M.paths(directory).pairing)
end

function M.readUi(directory)
  return M.readJson(M.paths(directory).ui) or {}
end

function M.writeUi(directory, ui)
  return M.writeJson(M.paths(directory).ui, ui, "600")
end

local function safeId(id)
  return tostring(id or "session"):gsub("[^%w_%-]", "_")
end

function M.sessionMarkdown(data, maxToolOutput)
  if type(data) ~= "table" then
    return ""
  end
  local info = data.info or {}
  local lines = {}
  table.insert(lines, "# " .. tostring(info.title or "Conversa"))
  table.insert(lines, "")
  table.insert(lines, "- **Sessão:** `" .. tostring(info.id or "") .. "`")
  table.insert(lines, "- **Agente:** `" .. tostring(info.agent or "") .. "`")
  table.insert(lines, "- **Modelo:** `" .. format.modelLabel(info.model) .. "`")
  if info.time and info.time.updated then
    table.insert(lines, "- **Atualizada:** " .. noctalia.formatTime("%Y-%m-%d %H:%M", math.floor(info.time.updated / 1000)))
  end
  table.insert(lines, "")

  for _, msg in ipairs(data.messages or {}) do
    if msg.type == "user" then
      table.insert(lines, "## Você")
      table.insert(lines, "")
      table.insert(lines, tostring(msg.text or ""))
      table.insert(lines, "")
    elseif msg.type == "assistant" then
      table.insert(lines, "## Assistente")
      table.insert(lines, "")
      for _, part in ipairs(msg.content or {}) do
        if part.type == "text" then
          table.insert(lines, tostring(part.text or ""))
          table.insert(lines, "")
        elseif part.type == "reasoning" then
          table.insert(lines, "### Raciocínio")
          table.insert(lines, "")
          table.insert(lines, format.truncate(part.text, maxToolOutput))
          table.insert(lines, "")
        elseif part.type == "tool" then
          table.insert(lines, "### Ferramenta: " .. tostring(part.name or "tool"))
          table.insert(lines, "")
          local input = format.toolInput(part.state and part.state.input)
          if input ~= "" then
            table.insert(lines, "```text")
            table.insert(lines, input)
            table.insert(lines, "```")
            table.insert(lines, "")
          end
          local output = ""
          local state = part.state or {}
          if state.status == "error" then
            output = format.errorText(state.error)
          elseif type(state.content) == "table" then
            local chunks = {}
            for _, content in ipairs(state.content) do
              if type(content) == "table" and type(content.text) == "string" then
                table.insert(chunks, content.text)
              end
            end
            output = table.concat(chunks, "\n")
          end
          if output ~= "" then
            table.insert(lines, "```text")
            table.insert(lines, format.truncate(output, maxToolOutput))
            table.insert(lines, "```")
            table.insert(lines, "")
          end
        end
      end
    end
  end

  return table.concat(lines, "\n")
end

function M.writeSession(directory, id, data, maxToolOutput)
  local paths = M.paths(directory)
  local safe = safeId(id)
  local jsonPath = paths.sessions .. "/" .. safe .. ".json"
  local mdPath = paths.sessions .. "/" .. safe .. ".md"

  local jsonOk = M.writeJson(jsonPath, data, "600")
  local mdOk = M.writeFileMode(mdPath, M.sessionMarkdown(data, maxToolOutput), "600")

  local index = M.readJson(paths.index) or { sessions = {} }
  if type(index.sessions) ~= "table" then
    index.sessions = {}
  end
  local info = data.info or {}
  local entry = {
    id = info.id or id,
    title = info.title or "Conversa",
    updatedAt = info.time and info.time.updated or 0,
    model = info.model,
    agent = info.agent,
    messageCount = #(data.messages or {}),
  }
  local replaced = false
  for i, item in ipairs(index.sessions) do
    if item.id == entry.id then
      index.sessions[i] = entry
      replaced = true
      break
    end
  end
  if not replaced then
    table.insert(index.sessions, 1, entry)
  end
  table.sort(index.sessions, function(a, b)
    return (a.updatedAt or 0) > (b.updatedAt or 0)
  end)
  M.writeJson(paths.index, index, "600")

  return jsonOk and mdOk
end

return M
