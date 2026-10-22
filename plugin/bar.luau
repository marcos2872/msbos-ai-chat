--!nonstrict
-- Widget da barra: ícone sempre visível, status e toggle do painel.

local PANEL_ID = "omyfedora/ai-chat:panel"
local status = noctalia.state.get("chat.status") or {
  state = "unpaired",
  busy = false,
  unread = false,
}

local function render()
  local glyph = noctalia.getConfig("glyph")
  if type(glyph) ~= "string" or glyph == "" then
    glyph = "message-chatbot"
  end
  local showLabel = noctalia.getConfig("show_bar_label") == true

  local dotColor = "outline"
  if status.busy then
    dotColor = "primary"
  elseif status.unread then
    dotColor = "tertiary"
  elseif status.state == "error" then
    dotColor = "error"
  end

  local children = {
    ui.glyph({ name = glyph, size = 16, color = "on_surface" }),
    ui.box({ width = 6, height = 6, radius = 3, fill = dotColor }),
  }

  if showLabel and status.title and status.title ~= "" then
    table.insert(children, ui.label({
      text = status.title,
      fontSize = 10,
      color = "on_surface",
      maxLines = 1,
      maxWidth = 120,
    }))
  end

  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = 5, align = "center", paddingH = 4, paddingV = 2 }, children))
end

noctalia.state.watch("chat.status", function(value)
  if type(value) == "table" then
    status = value
    render()
  end
end)

render()

function update()
  noctalia.setUpdateInterval(status.busy and 500 or 5000)
  render()
end

function onClick()
  noctalia.togglePanel(PANEL_ID)
end

function onConfigChanged()
  render()
end
