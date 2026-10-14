-- questman: UI layout helpers over MWUI templates.
-- Components are plain layout factories; ui.lua composes them and wires refresh/scroll.

local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')
local core = require('openmw.core')
local I = require('openmw.interfaces')

local v2 = util.vector2
local hex = util.color.hex   -- built-in "rrggbb" (no '#', 6 chars) -> Color; readable colour literals
local WHITE = hex('ffffff')
local GRAY = hex('808080')
local HIGHLIGHT = hex('d9b873')
local GREEN = hex('66c76b')
local YELLOW = hex('f2d14d')

local M = {}
M.WHITE = WHITE
M.GRAY = GRAY
M.HIGHLIGHT = HIGHLIGHT
M.GREEN = GREEN
M.YELLOW = YELLOW

-- util.color -> "RRGGBB" for inline MyGUI colour codes (#RRGGBB) that colour a span inside one Text.
function M.colorHex(c)
    local v = c:asRgb()
    return ('%02X%02X%02X'):format(
        math.floor(v.x * 255 + 0.5), math.floor(v.y * 255 + 0.5), math.floor(v.z * 255 + 0.5))
end

-- Native MW_Button font colours, pulled from the SAME GMSTs the engine's button skin uses
-- (FontColor_color_normal / _normal_over / _active / _active_over). Memoised; GMSTs need a loaded
-- game, so we resolve lazily on first button build (in-game) with safe fallbacks.
local _btnColors
local function btnColors()
    if not _btnColors then
        local function fc(name, fallback)
            local ok, c = pcall(function()
                return util.color.commaString(core.getGMST('FontColor_color_' .. name))
            end)
            return (ok and c) or fallback
        end
        _btnColors = {
            normal = fc('normal', WHITE),
            normal_over = fc('normal_over', WHITE),
            active = fc('active', hex('7380e6')),
            active_over = fc('active_over', hex('8c99ff')),
            header = fc('header', WHITE),   -- the brighter colour the quest-name header uses
        }
    end
    return _btnColors
end
-- Exposed so PLAYER scripts (ui.lua) can read the game font colours; must stay a function because the
-- GMSTs resolve lazily (need a loaded game), so there's no static value to export.
M.fontColors = btnColors

-- Hover recolouring needs the menu element to be updated; ui.lua provides the refresher.
local _refresh = function() end
function M.setRefresh(fn) _refresh = fn or function() end end

-- Native MW_Button textured frame: 8 pieces (4 tiled sides + 4 corners) from the engine's button
-- art, assembled exactly like the MWUI `box` template (so it autosizes to the content in the slot).
local BB = 4   -- button frame thickness (matches MW_Button)
local function btnEdge(name, props, tileH, tileV)
    props.resource = ui.texture { path = 'textures/menu_button_frame_' .. name .. '.dds' }
    props.tileH = tileH or false
    props.tileV = tileV or false
    return { type = ui.TYPE.Image, props = props }
end
local buttonFrame = {
    type = ui.TYPE.Container,
    content = ui.content {
        btnEdge('top',    { position = v2(BB, 0),  relativePosition = v2(0, 0), size = v2(0, BB), relativeSize = v2(1, 0) }, true, false),
        btnEdge('bottom', { position = v2(BB, BB), relativePosition = v2(0, 1), size = v2(0, BB), relativeSize = v2(1, 0) }, true, false),
        btnEdge('left',   { position = v2(0, BB),  relativePosition = v2(0, 0), size = v2(BB, 0), relativeSize = v2(0, 1) }, false, true),
        btnEdge('right',  { position = v2(BB, BB), relativePosition = v2(1, 0), size = v2(BB, 0), relativeSize = v2(0, 1) }, false, true),
        btnEdge('top_left_corner',     { position = v2(0, 0),   relativePosition = v2(0, 0), size = v2(BB, BB) }),
        btnEdge('top_right_corner',    { position = v2(BB, 0),  relativePosition = v2(1, 0), size = v2(BB, BB) }),
        btnEdge('bottom_left_corner',  { position = v2(0, BB),  relativePosition = v2(0, 1), size = v2(BB, BB) }),
        btnEdge('bottom_right_corner', { position = v2(BB, BB), relativePosition = v2(1, 1), size = v2(BB, BB) }),
        { external = { slot = true }, props = { position = v2(BB, BB), relativeSize = v2(1, 1) } },
    },
}

--- A native-style button that sizes to its label. Replicates MW_Button's behaviour:
--- hover brightens the text, and `opts.active` shows the blue "toggled/active" colour.
-- @param text string
-- @param onClick function
-- @param opts table (optional) { active = boolean }
local BTN_PAD = 10   -- horizontal text padding so the label doesn't touch the frame

-- opts: { active = bool, width = number (fixed inner width -> no resize on text change), height = number }
function M.button(text, onClick, opts)
    opts = opts or {}
    local c = btnColors()
    local base = opts.active and c.active or c.normal
    local over = opts.active and c.active_over or c.normal_over
    local textNode = {
        template = I.MWUI.templates.textNormal,
        props = { text = text, textColor = base },
        events = {
            focusGain = async:callback(function(_, l) l.props.textColor = over; _refresh() end),
            focusLoss = async:callback(function(_, l) l.props.textColor = base; _refresh() end),
        },
    }
    local inner
    if opts.width then
        -- fixed-width: text centered in a fixed box -> stays the same size when the label changes
        textNode.props.relativePosition = v2(0.5, 0.5)
        textNode.props.anchor = v2(0.5, 0.5)
        inner = {
            type = ui.TYPE.Widget,
            props = { size = v2(opts.width, opts.height or 18) },
            content = ui.content { textNode },
        }
    else
        -- autosize with horizontal padding
        inner = {
            type = ui.TYPE.Flex,
            props = { horizontal = true, arrange = ui.ALIGNMENT.Center },
            content = ui.content {
                { props = { size = v2(BTN_PAD, 0) } },
                textNode,
                { props = { size = v2(BTN_PAD, 0) } },
            },
        }
    end
    return {
        template = buttonFrame,   -- native MW_Button textured border
        -- consume mouse events so a button inside a draggable area (e.g. the title bar) doesn't
        -- start a window drag instead of clicking (which also swallows the click -> no close)
        props = { propagateEvents = false },
        content = ui.content { inner },
        events = {
            mouseClick = async:callback(function()
                if onClick then onClick() end
            end),
        },
    }
end

--- A subtitle: the title's header colour (from textHeader) at the default font size — for in-pane
--- section labels like "Journal" / "Related topics:". Title is textSize 20; the subtitle sits below it
--- at the normal text size (16), so it reads as a caption without shrinking.
function M.subtitle(text)
    return {
        template = I.MWUI.templates.textHeader,
        props = { text = text or '', textSize = 16 },
    }
end

--- A clickable hyperlink-style text node: the engine's blue "active" colour, brightening on hover like
--- MW_Button's text (same focusGain/focusLoss + `_refresh` pattern). Used for the "Related topics"
--- cross-references so they read and behave as links. Click fires `onClick`.
function M.link(text, onClick)
    local c = btnColors()
    local base, over = c.active, c.active_over
    return {
        template = I.MWUI.templates.textNormal,
        props = { text = text or '', textColor = base },
        events = {
            mouseClick = async:callback(function() if onClick then onClick() end end),
            focusGain = async:callback(function(_, l) l.props.textColor = over; _refresh() end),
            focusLoss = async:callback(function(_, l) l.props.textColor = base; _refresh() end),
        },
    }
end

--- A plain text line. Defaults to Morrowind's normal font colour (light brown), not white.
function M.textLine(text, color)
    return {
        type = ui.TYPE.Text,
        template = I.MWUI.templates.textNormal,
        props = { text = text or '', textColor = color or btnColors().normal },
    }
end

-- ---------------------------------------------------------------------------
-- Checkbox (no native widget exists; assembled from primitives).
-- One shared "inner" idea: a fixed bordered square (1px MWUI lines, never auto-grows) that shows a
-- small CENTERED indicator when checked. The indicator varies by `style`; its colour by `mark`.
-- opts = { checked, label, style, size, color, mark, image, gap, onClick }
--   style: 'square'   — small filled square drawn from the `white` texture (font-free)
--          'asterisk' — '*' glyph (ASCII; safe in the game font)
--          'circle'   — 'O' glyph (outline approximation — the font has no filled-disc glyph, and no
--                       built-in circle texture exists; a true filled circle needs a bundled .dds)
--          'image'    — a bundled texture (opts.image), e.g. 'Icons/questman/ui_check_mark.dds'
--   color = border/label colour; mark = inner indicator colour (ignored by 'image' unless opts.tint)
-- ---------------------------------------------------------------------------
local function cbBordered(size, indicator)
    -- M.framed adds the same 8-piece directional border as the scrollbar/search boxes (the centred
    -- indicator is small enough never to reach the 2px frame). M.framed is referenced (not the local
    -- borderFrame) because it's defined later in the file; both exist by the time checkboxes are built.
    local children = indicator and { indicator } or {}
    return { type = ui.TYPE.Widget, props = { size = v2(size, size) }, content = M.framed(children) }
end

function M.checkbox(opts)
    opts = opts or {}
    local checked = opts.checked == true
    local S = opts.size or 16
    local color = opts.color or btnColors().normal
    local mark = opts.mark or M.LABEL_COLOR
    local style = opts.style or 'square'

    local function centered(node)   -- centre any indicator node inside the box
        node.props.relativePosition = v2(0.5, 0.5)
        node.props.anchor = v2(0.5, 0.5)
        return node
    end

    local ind
    if checked then
        if style == 'asterisk' then
            ind = centered { type = ui.TYPE.Text, template = I.MWUI.templates.textNormal,
                             props = { text = '*', textColor = mark } }
        elseif style == 'circle' then
            ind = centered { type = ui.TYPE.Text, template = I.MWUI.templates.textNormal,
                             props = { text = 'O', textColor = mark } }
        elseif style == 'image' then
            ind = centered { type = ui.TYPE.Image,
                             props = { resource = ui.texture { path = opts.image }, color = opts.tint or WHITE,
                                       size = v2(S - 4, S - 4) } }
        else   -- 'square': small inset filled square (the canonical inner look)
            ind = centered { type = ui.TYPE.Image,
                             props = { resource = ui.texture { path = 'white' }, color = mark,
                                       size = v2(S - 9, S - 9) } }
        end
    end

    local row = { cbBordered(S, ind) }
    if opts.label then
        row[#row + 1] = { props = { size = v2(opts.gap or 5, 0) } }
        row[#row + 1] = { type = ui.TYPE.Text, template = I.MWUI.templates.textNormal,
                          props = { text = opts.label, textColor = color } }
    end
    return {
        type = ui.TYPE.Flex,
        props = { horizontal = true, arrange = ui.ALIGNMENT.Center },
        events = opts.onClick and { mouseClick = async:callback(function() opts.onClick() end) } or nil,
        content = ui.content(row),
    }
end

--- A "Label: value" line where the label uses the brighter header colour (marking it as a static
--- caption, matching the quest name) and the value uses the normal text colour.
-- `onClick` (optional): makes the whole line clickable (same look/colours, just a mouseClick handler) —
-- used by the detail pane to filter the quest list by the clicked category / faction, mirroring the Stats rows.
function M.labelValue(label, value, labelColor, onClick)
    local c = btnColors()
    local node = {
        type = ui.TYPE.Flex,
        props = { horizontal = true },
        content = ui.content {
            { type = ui.TYPE.Text, template = I.MWUI.templates.textNormal,
              props = { text = label or '', textColor = labelColor or c.header } },
            { type = ui.TYPE.Text, template = I.MWUI.templates.textNormal,
              props = { text = ' ' .. (value or ''), textColor = c.normal } },
        },
    }
    if onClick then node.events = { mouseClick = async:callback(onClick) } end
    return node
end

-- Static-label colour (dark brown) — distinctive on the dark panel and reads as a caption vs the value.
M.LABEL_COLOR = hex('cc7d3e')

--- A header line (bigger).
function M.header(text)
    return {
        template = I.MWUI.templates.textHeader,
        props = { text = text or '', textSize = 20 },
    }
end

--- A wrapping paragraph constrained to `width` (height auto). Used for journal entries.
function M.paragraph(text, width)
    return {
        template = I.MWUI.templates.textParagraph,
        props = { text = text or '', size = v2(width or 300, 0) },
    }
end

--- Fixed single-line search box. `onChange(text)` fires on every keystroke.
function M.searchBox(width, initial, onChange)
    return {
        name = 'search',
        template = I.MWUI.templates.textEditLine,
        props = { text = initial or '', size = v2(width or 200, 0) },
        events = {
            textChanged = async:callback(function(s)
                if onChange then onChange(s) end
            end),
        },
    }
end

--- A clickable quest row: small icon + name (grayed when completed/hidden, default Morrowind text
-- colour when active, white when selected).
-- `markers` (optional list of icon paths): inserted before the name in order (shifting the title right);
-- rows without markers keep their title flush against the quest icon.
function M.questRow(quest, selected, onClick, markers, rowH, iconSz)
    local color = (quest.completed or quest.hidden) and GRAY or btnColors().normal
    if selected then color = WHITE end
    rowH = rowH or 26
    iconSz = iconSz or 22
    local row = {
        { props = { size = v2(2, 0) } },   -- 2px left margin: aligns icons with the search icon
        -- 0-width, rowH-tall spacer forces the row to rowH so adjacent icons don't touch (the row would
        -- otherwise shrink to the icon). The icon stays a DIRECT child of the full-width row, centered by the
        -- Flex's arrange -- do NOT wrap it in an iconSz-sized cell: that clip box sits right on the icon's
        -- edges and shaves ~1px off its left/top at fractional GUI scales (e.g. 1.5x). rowH (= ROW_H) is the
        -- one row-height knob; iconSz (= ICON_SZ) sizes the icon; keep rowH >= iconSz + 2 for margin.
        { props = { size = v2(0, rowH) } },
        {
            type = ui.TYPE.Image,
            props = { size = v2(iconSz, iconSz), resource = ui.texture { path = quest.icon } },
        },
    }
    if markers and #markers > 0 then
        row[#row + 1] = { props = { size = v2(3, 0) } }   -- gap after the quest icon
        for i, m in ipairs(markers) do
            if i > 1 then row[#row + 1] = { props = { size = v2(2, 0) } } end   -- gap between markers
            row[#row + 1] = { type = ui.TYPE.Image,
                              props = { size = v2(14, 14), resource = ui.texture { path = m } } }
        end
    end
    row[#row + 1] = { props = { size = v2(4, 0) } }   -- small gap before the name (both pinned & not)
    row[#row + 1] = { type = ui.TYPE.Text, template = I.MWUI.templates.textNormal,
                      props = { text = quest.name or quest.id, textColor = color } }
    return {
        type = ui.TYPE.Flex,
        props = { horizontal = true, arrange = ui.ALIGNMENT.Center },
        external = { stretch = 1 },
        content = ui.content(row),
        events = {
            mouseClick = async:callback(function()
                if onClick then onClick(quest) end
            end),
        },
    }
end

--- A vertical scrollbar (track + draggable thumb). `onDragDelta(dyPixels)` is optional.
-- `thumb` is the geometry from uiScroll.thumb().
-- engine scrollbar textures (the same ones the native MW_VScroll skin is built from)
local SCROLL_UP = 'textures/omw_menu_scroll_up.dds'
local SCROLL_DOWN = 'textures/omw_menu_scroll_down.dds'
local SCROLL_THUMB = 'textures/omw_menu_scroll_center_v.dds'

-- 8-piece ornate thin border (4 directional tiled sides + 4 corners) filling its parent Widget — the
-- groove and each arrow box. Assembled exactly like MWUI's own box border (omw/mwui/borders.lua): each
-- side uses its OWN directional texture and the corners join them. The old 4-line version reused the
-- left texture for the right edge and the top texture for the bottom edge with no corners, so the right
-- /bottom edges drew the wrong art and the box's top line looked "not connected to the sides".
local SB = 2   -- thin-border thickness (MWUI constants.border)
local SB_SIDE = 'textures/menu_thin_border_%s.dds'
local SB_CORNER = 'textures/menu_thin_border_%s_corner.dds'
local SB_SIDES = {
    { k = 'top',    v = v2(0, 0), d = v2(1, 0) },
    { k = 'bottom', v = v2(0, 1), d = v2(1, 0) },
    { k = 'left',   v = v2(0, 0), d = v2(0, 1) },
    { k = 'right',  v = v2(1, 0), d = v2(0, 1) },
}
local SB_CORNERS = {
    { k = 'top_left',     v = v2(0, 0) },
    { k = 'top_right',    v = v2(1, 0) },
    { k = 'bottom_left',  v = v2(0, 1) },
    { k = 'bottom_right', v = v2(1, 1) },
}
local function borderFrame()
    local pieces = {}
    for _, s in ipairs(SB_SIDES) do
        local horizontal = s.d.x == 1
        pieces[#pieces + 1] = {
            type = ui.TYPE.Image,
            props = {
                resource = ui.texture { path = SB_SIDE:format(s.k) },
                tileH = horizontal,
                tileV = not horizontal,
                position = (s.d - s.v) * SB,
                relativePosition = s.v,
                size = (v2(1, 1) - s.d * 3) * SB,
                relativeSize = s.d,
            },
        }
    end
    for _, c in ipairs(SB_CORNERS) do
        pieces[#pieces + 1] = {
            type = ui.TYPE.Image,
            props = {
                resource = ui.texture { path = SB_CORNER:format(c.k) },
                position = -c.v * SB,
                relativePosition = c.v,
                size = v2(SB, SB),
            },
        }
    end
    return pieces
end
-- Public: the content pieces for a thin ornate frame, to spread into any fixed-size Widget's content
-- (e.g. the funnel button). Reuses the same 8-piece directional border as the scrollbar boxes.
M.borderFrame = borderFrame

-- Wrap child layouts with the thin frame and return a ready ui.content. The border is added LAST so it
-- draws on top of the children (matching how the search/funnel/combo boxes layered their old 4-line
-- border over their input/icon). Used by every bordered box so they all share one correct frame.
function M.framed(children)
    local out = {}
    for _, c in ipairs(children) do out[#out + 1] = c end
    for _, p in ipairs(borderFrame()) do out[#out + 1] = p end
    return ui.content(out)
end

-- Native-style vertical scrollbar, hand-assembled to mirror MW_VScroll (openmw_list.skin.xml):
--   [▲ boxed arrow]  · gap ·  bordered groove (tiled thumb travels inside)  · gap ·  [▼ boxed arrow]
-- THREE separately-bordered Widgets (two arrow boxes + the groove) with a small gap between each box and
-- the groove, matching the system scrollbar. Everything is a plain Widget/Image (known to render).
-- opts = { width, height, arrowH, thumb = uiScroll.thumb result, onDrag(dy), onStepUp(), onStepDown() }
function M.scrollbar(opts)
    local w, h, ah, t = opts.width, opts.height, opts.arrowH, opts.thumb
    local GAP = 3              -- gap between an arrow box and the groove (system look)
    local boxH = ah - GAP     -- arrow-box height; with ARROW_H = BAR_W + GAP the box is square (boxH == w)
    local asz = w - 6         -- arrow glyph, inset inside its box (clear of the 2px borders)
    local ax = math.floor((w - asz) / 2)
    local abY = math.floor((boxH - asz) / 2)

    -- The thumb travels in [ah, h-ah] (UNCHANGED — trackH stays h-2*ah on the caller side). x=2 sits
    -- flush against the groove's 2px left border; width w-5 leaves a 1px black gap on the RIGHT only,
    -- matching the system scrollbar (the apply sites in ui.lua set this same x=2 when scrolling).
    local thumbWidget = {
        name = 'thumb',
        type = ui.TYPE.Image,
        props = {
            resource = ui.texture { path = SCROLL_THUMB },
            tileV = true,
            tileH = true,   -- match native MW_ScrollTrackV (TileRect tiles both ways); false = flat color
            position = v2(2, ah + t.top),
            size = v2(w - 5, t.height),
        },
        userData = { drag = false, last = nil },
    }
    if opts.onDrag then
        thumbWidget.events = {
            mousePress = async:callback(function(e, l) l.userData.drag = true; l.userData.last = e.position end),
            mouseMove = async:callback(function(e, l)
                if l.userData.drag and l.userData.last then
                    opts.onDrag((e.position - l.userData.last).y)
                    l.userData.last = e.position
                end
            end),
            mouseRelease = async:callback(function(_, l) l.userData.drag = false end),
        }
    end

    local function arrowBox(y, tex, onClick)
        local content = borderFrame()
        content[#content + 1] = {
            type = ui.TYPE.Image,
            props = { resource = ui.texture { path = tex }, size = v2(asz, asz), position = v2(ax, abY) },
            events = onClick and { mouseClick = async:callback(onClick) } or nil,
        }
        return {
            type = ui.TYPE.Widget,
            props = { position = v2(0, y), size = v2(w, boxH) },
            content = ui.content(content),
        }
    end

    -- groove = the thumb track, its own frame, spanning [ah, h-ah] (GAP below the top box / above the
    -- bottom box). The thumb (a sibling, drawn last) lands inside it.
    local groove = {
        type = ui.TYPE.Widget,
        props = { position = v2(0, ah), size = v2(w, h - 2 * ah) },
        content = ui.content(borderFrame()),
    }

    return {
        type = ui.TYPE.Widget,  -- fixed size + clips children
        props = { size = v2(w, h), visible = t.visible },
        content = ui.content {
            groove,
            arrowBox(0, SCROLL_UP, opts.onStepUp),
            arrowBox(h - boxH, SCROLL_DOWN, opts.onStepDown),
            thumbWidget,
        },
    }
end

-- ---------------------------------------------------------------------------
-- Hover tooltips. No native tooltip widget: we create a small solid box on the 'Notification' layer
-- (above Windows, non-interactive) at the cursor and destroy it on mouse-leave. The tooltip is its own
-- top-level Element (NOT a child of the menu), so callers MUST `hideTooltip()` on teardown/page switch.
-- Reusable: `M.attachTooltip(node, text|fn)` wires mouseMove(show) + focusLoss(hide) onto any node.
-- ---------------------------------------------------------------------------
local function logicalScreen()   -- logical view size (cursor coords are in this space); see ui.lua
    local ok, size = pcall(function()
        for _, layer in ipairs(ui.layers) do
            if layer.name == 'Windows' and layer.size then return layer.size end
        end
    end)
    return (ok and size) or ui.screenSize()
end

local activeTip, activeTipKey
local tipBlockUntil = 0   -- real-time until which show* is suppressed (see dismissTooltip)
function M.hideTooltip()
    if activeTip then pcall(function() activeTip:destroy() end) end
    activeTip, activeTipKey = nil, nil
end

-- Hide the tooltip for an action that rebuilds the menu (page switch / filter jump / resize / teardown).
-- Such a click DESTROYS the hovered widget, so its focusLoss (mouse-leave) never fires; worse, a trailing
-- mouseMove from the same click can call show* again just AFTER a plain hideTooltip, re-creating the tip and
-- orphaning it over the new page. So we also suppress show* for a brief window to swallow that stray re-show.
-- Use this (not hideTooltip) wherever a click rebuilds the UI. The window is far shorter than any deliberate
-- hover, so it never blocks a real tooltip.
function M.dismissTooltip()
    M.hideTooltip()
    tipBlockUntil = core.getRealTime() + 0.1
end

local function tipPosAnchor(cursor)
    local sz = logicalScreen()
    local ax = (cursor.x > sz.x / 2) and 1 or 0   -- flip the anchor by screen quadrant so it stays on-screen
    local ay = (cursor.y > sz.y / 2) and 1 or 0
    local pos = v2(cursor.x + (ax == 0 and 16 or -10), cursor.y + (ay == 0 and 18 or -10))
    return pos, v2(ax, ay)
end

local function showTip(cursor, text)
    if core.getRealTime() < tipBlockUntil then return end   -- swallow a click's trailing re-show (see dismissTooltip)
    if not text or text == '' then M.hideTooltip(); return end
    local pos, anchor = tipPosAnchor(cursor)
    if activeTip and activeTipKey == text then   -- same content -> just move it (no flicker)
        activeTip.layout.props.position = pos
        activeTip.layout.props.anchor = anchor
        pcall(function() activeTip:update() end)
        return
    end
    M.hideTooltip()
    activeTipKey = text
    activeTip = ui.create {
        layer = 'Notification',
        template = I.MWUI.templates.boxSolid,
        props = { position = pos, anchor = anchor },
        content = ui.content {
            { template = I.MWUI.templates.padding,
              content = ui.content {
                  { type = ui.TYPE.Text, template = I.MWUI.templates.textNormal,
                    props = { text = text, textColor = btnColors().normal } },
              } },
        },
    }
end

-- Like showTip, but the floating box holds an IMAGE instead of text (a zoom of a small icon). `nativePx`
-- is the texture's NATIVE size in PHYSICAL pixels. Lua sizes are LOGICAL px, which the engine multiplies
-- by the GUI scale, so a 64-logical box on a 64px icon at 1.5x scale would upscale to 96px (blurry). We
-- divide by the current scale so the physical size == the texture size (crisp, 1:1, no up/down-scaling).
-- Shares the tooltip host (activeTip); keyed so re-hovering the same icon just repositions.
local function showIconTip(cursor, iconPath, nativePx)
    if core.getRealTime() < tipBlockUntil then return end   -- swallow a click's trailing re-show (see dismissTooltip)
    if not iconPath then M.hideTooltip(); return end
    local scr, logi = ui.screenSize(), logicalScreen()      -- physical vs logical view size
    local scale = (logi.x > 0) and (scr.x / logi.x) or 1
    local sz = math.max(1, math.floor(nativePx / scale + 0.5))
    local pos, anchor = tipPosAnchor(cursor)
    local key = iconPath .. '@' .. sz
    if activeTip and activeTipKey == key then
        activeTip.layout.props.position = pos
        activeTip.layout.props.anchor = anchor
        pcall(function() activeTip:update() end)
        return
    end
    M.hideTooltip()
    activeTipKey = key
    activeTip = ui.create {
        layer = 'Notification',
        template = I.MWUI.templates.boxSolid,
        props = { position = pos, anchor = anchor },
        content = ui.content {
            { template = I.MWUI.templates.padding,
              content = ui.content {
                  { type = ui.TYPE.Image,
                    props = { size = v2(sz, sz), resource = ui.texture { path = iconPath } } },
              } },
        },
    }
end

--- Attach a hover tooltip to a layout node. `provider` is a string or a function -> string.
function M.attachTooltip(node, provider)
    node.events = node.events or {}
    node.events.mouseMove = async:callback(function(e)
        showTip(e.position, type(provider) == 'function' and provider() or provider)
    end)
    node.events.focusLoss = async:callback(function() M.hideTooltip() end)
    return node
end

--- Attach an "enlarged icon" hover to a node: shows the SAME icon in a floating box (a zoom for the small
-- Stats-page row icons). `size` is the texture's NATIVE size in PHYSICAL px — pass the icon's real pixel
-- size (ours are 64) to render it crisp 1:1 regardless of GUI scale. Reuses the shared tooltip host, so
-- callers must hideTooltip() on teardown / page switch (ui.lua already does). `iconPath` is a VFS path.
function M.attachIconZoom(node, iconPath, size)
    node.events = node.events or {}
    node.events.mouseMove = async:callback(function(e) showIconTip(e.position, iconPath, size or 64) end)
    node.events.focusLoss = async:callback(function() M.hideTooltip() end)
    return node
end

return M
