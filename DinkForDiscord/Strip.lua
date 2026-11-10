local _, ns = ...

-- The data code: a small grid of coloured squares drawn in the top-left corner for one
-- screenshot. The helper app reads the alert back out of that screenshot and deletes it.
--
-- Layout (must match the helper's decoder):
--   * 64 cells per row, every cell a square of CELL x CELL screen pixels.
--   * Row 0 is the finder: red, green, blue, white, then black/white alternating.
--   * Rows 1+ carry data, 3 bits per cell (red = 4, green = 2, blue = 1), left to right.
--   * Bytes: "D" "K" version lenHi lenLo payload... adler32 (4 bytes, big endian).

local Strip = {}
ns.Strip = Strip

Strip.COLS = 64
Strip.VERSION = 1
Strip.MAX_PAYLOAD = 1500

local COLORS = {
    [0] = { 0, 0, 0 }, [1] = { 0, 0, 1 }, [2] = { 0, 1, 0 }, [3] = { 0, 1, 1 },
    [4] = { 1, 0, 0 }, [5] = { 1, 0, 1 }, [6] = { 1, 1, 0 }, [7] = { 1, 1, 1 },
}
Strip.COLORS = COLORS

local function adler32(bytes)
    local a, b = 1, 0
    for i = 1, #bytes do
        a = (a + bytes[i]) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end
Strip.Adler32 = adler32

-- Returns rows of colour indices (0-7). rows[1] is the finder row.
function Strip.Encode(payload)
    local bytes = { 0x44, 0x4B, Strip.VERSION, math.floor(#payload / 256), #payload % 256 }
    local body = {}
    for i = 1, #payload do body[i] = payload:byte(i) end
    for i = 1, #body do bytes[#bytes + 1] = body[i] end
    local sum = adler32(body)
    for shift = 3, 0, -1 do
        bytes[#bytes + 1] = math.floor(sum / 256 ^ shift) % 256
    end

    local finder = { 4, 2, 1, 7 }
    for i = 5, Strip.COLS do finder[i] = (i % 2 == 1) and 0 or 7 end
    local rows = { finder }

    local cells, acc, nbits = {}, 0, 0
    for _, byte in ipairs(bytes) do
        for bit = 7, 0, -1 do
            acc = acc * 2 + math.floor(byte / 2 ^ bit) % 2
            nbits = nbits + 1
            if nbits == 3 then cells[#cells + 1] = acc; acc, nbits = 0, 0 end
        end
    end
    if nbits > 0 then
        while nbits < 3 do acc = acc * 2; nbits = nbits + 1 end
        cells[#cells + 1] = acc
    end

    local row
    for i, c in ipairs(cells) do
        if (i - 1) % Strip.COLS == 0 then row = {}; rows[#rows + 1] = row end
        row[#row + 1] = c
    end
    while #row < Strip.COLS do row[#row + 1] = 0 end
    return rows
end

---------------------------------------------------------------- drawing
local frame, pool, used = nil, {}, 0

local function PhysicalHeight()
    if GetPhysicalScreenSize then
        local ok, _, h = pcall(GetPhysicalScreenSize)
        if ok and type(h) == "number" and h > 0 then return h end
    end
    return 1080
end

-- Cell size in screen pixels: big enough to survive JPEG compression.
function Strip.CellSize(height)
    return math.max(6, math.floor((height or PhysicalHeight()) / 180 + 0.5))
end

local function Texture(i)
    local t = pool[i]
    if not t then
        t = frame:CreateTexture(nil, "OVERLAY")
        pool[i] = t
    end
    return t
end

-- Draws the code for this payload. Each run of same-coloured cells is one texture.
function Strip.Show(payload)
    if not frame then
        frame = CreateFrame("Frame", nil, nil)
        frame:SetFrameStrata("TOOLTIP")
        frame:SetFrameLevel(9000)
        frame:SetPoint("TOPLEFT")
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 1)
    end
    local h = PhysicalHeight()
    local cell = Strip.CellSize(h)
    -- 1 UI unit == 1 screen pixel at this scale.
    frame:SetScale(768 / h)

    local rows = Strip.Encode(payload)
    for i = 1, used do pool[i]:Hide() end
    used = 0
    for r, row in ipairs(rows) do
        local c = 1
        while c <= #row do
            local color, len = row[c], 1
            while row[c + len] == color do len = len + 1 end
            if color ~= 0 then
                used = used + 1
                local t = Texture(used)
                local rgb = COLORS[color]
                t:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", frame, "TOPLEFT", (c - 1) * cell, -(r - 1) * cell)
                t:SetSize(len * cell, cell)
                if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
                if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
                t:Show()
            end
            c = c + len
        end
    end
    frame:SetSize(Strip.COLS * cell, #rows * cell)
    frame:Show()
end

function Strip.Hide()
    if frame then frame:Hide() end
end
