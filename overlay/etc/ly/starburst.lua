-- Greyscale flame starburst, fired from the middle of the screen.
-- One three-second burst every 45 seconds; the rest of the time it draws
-- nothing, so the login screen stays quiet.
--
-- Ly calls draw() once per frame and hands us the "ly" table described in
-- /etc/ly/example.lua: ly.width, ly.height, ly.clock() (microseconds) and
-- ly.putCell(byte, fg, bg, x, y).

local BG = 0x00241F31       -- must match bg in /etc/ly/config.lua
local BURST_US = 3000000
local PERIOD_US = 45000000
local FIRST_US = 1000000    -- first burst shortly after the screen appears
local FADE_US = 600000      -- burn out over the last part of the burst
local EMIT_PER_SEC = 1100
local MAX_PART = 900

local p_ang, p_spd, p_born, p_life, p_grey = {}, {}, {}, {}, {}
local slot, emit_carry, ndrawn = 0, 0, 0
local dx, dy = {}, {}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function emit(now, n)
    for _ = 1, n do
        slot = slot % MAX_PART + 1
        p_ang[slot] = math.random() * 2 * math.pi
        p_spd[slot] = 10 + math.random() * 40
        p_born[slot] = now
        p_life[slot] = (0.50 + math.random() * 0.60) * 1000000
        p_grey[slot] = 120 + math.random(0, 135)
    end
end

math.randomseed(ly.clock() % 2147483647)

local burst_at = -1
local next_burst = ly.clock() + FIRST_US
local last_frame = ly.clock()

function draw()
    local now = ly.clock()
    local dt = (now - last_frame) / 1000000
    last_frame = now
    local w, h = ly.width, ly.height

    -- Wipe whatever we painted last frame.
    for i = 1, ndrawn do
        ly.putCell(32, 0, BG, dx[i], dy[i])
    end
    ndrawn = 0

    if next_burst > 0 and now >= next_burst then
        burst_at = now
        next_burst = now + PERIOD_US
        emit_carry = 0
    end

    if burst_at < 0 then return end
    local t = now - burst_at
    if t >= BURST_US then
        burst_at = -1
        return
    end

    emit_carry = emit_carry + EMIT_PER_SEC * dt
    local n = math.floor(emit_carry)
    emit_carry = emit_carry - n
    if n > MAX_PART then n = MAX_PART end
    emit(now, n)

    local cx, cy = w / 2, h / 2
    local fadeout = clamp((BURST_US - t) / FADE_US, 0, 1)

    for i = 1, MAX_PART do
        local born = p_born[i]
        if born then
            local age = (now - born) / 1000000
            local life = p_life[i] / 1000000
            if age <= life then
                local r = 1.5 + p_spd[i] * age
                local a = p_ang[i]
                local x = cx + math.cos(a) * r
                -- chars are about twice as tall as they are wide, so flatten
                -- the vertical axis to keep the burst round; the drift bends
                -- it slightly upwards like a flame
                local y = cy + math.sin(a) * r * 0.5 - age * 1.5
                if x >= 0 and x < w and y >= 0 and y < h then
                    local g = p_grey[i] * (1 - age / life) * fadeout *
                        (0.65 + 0.35 * math.random())
                    g = math.floor(clamp(g, 24, 255))
                    local ch = 0x2591
                    if g > 200 then
                        ch = 0x2588
                    elseif g > 120 then
                        ch = 0x2593
                    end
                    local ix, iy = math.floor(x), math.floor(y)
                    ly.putCell(ch, g * 0x010101, BG, ix, iy)
                    ndrawn = ndrawn + 1
                    dx[ndrawn] = ix
                    dy[ndrawn] = iy
                end
            end
        end
    end
end
