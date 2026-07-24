-- questman: pure scroll math for the clip+offset scroll areas. Engine-free so it can be unit-tested; ui.lua owns the
-- widgets and applies these results.

local M = {}

--- Largest valid scroll offset (0 when content fits).
function M.maxOffset(contentH, viewH)
    return math.max(0, (contentH or 0) - (viewH or 0))
end

--- Clamp an offset into [0, maxOffset].
function M.clamp(offset, contentH, viewH)
    local maxOff = M.maxOffset(contentH, viewH)
    if (offset or 0) < 0 then return 0 end
    if offset > maxOff then return maxOff end
    return offset
end

--- Scrollbar thumb geometry for a vertical track of height `trackH`.
-- @return { visible = bool, height = number, top = number }
-- `slack` (optional): treat content within this many px of the viewport as "fits" and hide the bar. Lets
-- text panes, whose height is only ESTIMATED, avoid a spurious bar from a few px of rounding overshoot.
function M.thumb(contentH, viewH, trackH, offset, slack)
    contentH = contentH or 0
    if contentH <= viewH + (slack or 0) or contentH <= 0 then
        return { visible = false, height = trackH, top = 0 }
    end
    local h = math.max(28, trackH * viewH / contentH)
    local maxOff = M.maxOffset(contentH, viewH)
    local top = maxOff > 0 and (M.clamp(offset, contentH, viewH) / maxOff) * (trackH - h) or 0
    return { visible = true, height = h, top = top }
end

--- Rough rendered height of wrapped text, for clamping the detail pane.
-- Approximate (calibrate constants in-engine); newlines and width-wrapping both counted.
-- UTF-8 code points in a string. Byte length (#s) overcounts non-ASCII text -- Cyrillic (the Russian
-- journal/dialogue) is 2 bytes per character -- which would ~double the estimated line count and pop a
-- spurious scrollbar on content that actually fits. Counting code points keeps the estimate honest across
-- languages (for ASCII it equals #s). A continuation byte is 0x80..0xBF; every other byte starts a char.
local function utf8len(s)
    local n = 0
    for i = 1, #s do
        local b = string.byte(s, i)
        if b < 0x80 or b >= 0xC0 then n = n + 1 end
    end
    return n
end

function M.estimateTextHeight(text, widthPx, charWidthPx, lineHeightPx)
    text = text or ''
    charWidthPx = charWidthPx or 8
    lineHeightPx = lineHeightPx or 18
    local charsPerLine = math.max(1, math.floor((widthPx or 100) / charWidthPx))
    local lines = 0
    for paragraph in (text .. '\n'):gmatch('(.-)\n') do
        lines = lines + math.max(1, math.ceil(utf8len(paragraph) / charsPerLine))
    end
    return lines * lineHeightPx
end

return M
