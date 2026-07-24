-- questman: pure window-resize math for the edge/corner drag handles. Engine-free so it can be
-- unit-tested; ui.lua owns the strip widgets/cursors and applies these results (like uiScroll.lua).

local M = {}

-- Drag directions (edges + corners). ui.lua keys its strips + cursors by these same values.
M.DIR = { L = 'l', R = 'r', T = 't', B = 'b', TL = 'tl', TR = 'tr', BL = 'bl', BR = 'br' }

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Which horizontal / vertical edge each direction pulls.
local PULL_LEFT   = { l = true, tl = true, bl = true }
local PULL_RIGHT  = { r = true, tr = true, br = true }
local PULL_TOP    = { t = true, tl = true, tr = true }
local PULL_BOTTOM = { b = true, bl = true, br = true }

--- New window geom for a resize drag. Pure: same inputs -> same output.
-- Left/top edges shrink the size AND move the origin (clamped to screen 0 and to minW/minH); right/bottom
-- edges only grow/shrink (clamped to minW/minH and to the screen far edge). Corners run both components.
-- @param dir   one of M.DIR
-- @param delta { x, y } cursor movement since press
-- @param start { x, y, w, h } geom at press
-- @param opts  { minW, minH, screenW, screenH }
-- @return { x, y, w, h }
function M.apply(dir, delta, start, opts)
    local x, y, w, h = start.x, start.y, start.w, start.h

    if PULL_LEFT[dir] then
        local dX = clamp(delta.x, -start.x, start.w - opts.minW)
        w = start.w - dX
        x = start.x + dX
    elseif PULL_RIGHT[dir] then
        w = clamp(start.w + delta.x, opts.minW, opts.screenW - start.x)
    end

    if PULL_TOP[dir] then
        local dY = clamp(delta.y, -start.y, start.h - opts.minH)
        h = start.h - dY
        y = start.y + dY
    elseif PULL_BOTTOM[dir] then
        h = clamp(start.h + delta.y, opts.minH, opts.screenH - start.y)
    end

    return { x = x, y = y, w = w, h = h }
end

return M
