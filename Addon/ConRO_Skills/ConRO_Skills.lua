-- ===================================================================
-- ConRO Color Pixel Bridge - Optimized and Refactored Version
-- Displays color-coded pixels based on ConRO addon rotation values
-- ===================================================================

-- Clean up any existing frames to prevent duplicates
local frameNames = {"ColorFrame", "ColorFrame2", "ColorFrame3", "ColorFrame4", "ColorFrame5", "ColorFrameStatus"}
for _, frameName in ipairs(frameNames) do
    local existingFrame = _G[frameName]
    if existingFrame then
        existingFrame:Hide()
        existingFrame:ClearAllPoints()
        existingFrame:SetParent(nil)
        _G[frameName] = nil
    end
end

-- Configuration
local CONFIG = {
    UPDATE_INTERVAL = 0.1,  -- Update frequency in seconds
    PIXEL_SIZE = 1,          -- Size of each pixel frame (5x5 squares)
    START_X = 0,            -- Starting X position
    START_Y = 0,            -- Starting Y position
}

-- Color mapping for rotation values (0-9)
local COLORS = {
    {1, 0, 0},       -- 0: Red
    {0, 1, 0},       -- 1: Green
    {0, 0, 1},       -- 2: Blue
    {1, 1, 0},       -- 3: Yellow
    {1, 0, 1},       -- 4: Magenta
    {0, 1, 1},       -- 5: Cyan
    {0.5, 0.5, 0.5}, -- 6: Gray
    {1, 0.5, 0},     -- 7: Orange
    {0, 1, 0.5},     -- 8: Turquoise
    {0.5, 0, 1}      -- 9: Purple
}

-- Frame configuration: {ConROWindow, frameName, yOffset}
-- Using 6-pixel spacing to avoid overlap between 5x5 squares
local FRAME_CONFIG = {
    {ConROWindow, "ColorFrame", 0},
    {ConROWindow2, "ColorFrame2", -1},
    {ConRODefenseWindow, "ColorFrame3", -2},
    {ConROInterruptWindow, "ColorFrame4", -3},
    {ConROPurgeWindow, "ColorFrame5", -4},
}

-- Status frame configuration (special case)
local STATUS_FRAME = {nil, "ColorFrameStatus", -5}

-- Global variables for update timing
local timeSinceLastUpdate = 0
local frames = {}
local textures = {}

-- Utility function to check if Global Cooldown is active
local function IsGCDActive()
    local spellCooldownInfo = C_Spell.GetSpellCooldown(61304)
    if spellCooldownInfo.startTime == 0 then return false end
    return (spellCooldownInfo.startTime + spellCooldownInfo.duration - GetTime()) > 0
end

-- Factory function to create a pixel frame
local function CreatePixelFrame(frameName, yOffset, isStatusFrame)
    local frame = CreateFrame("Frame", frameName, WorldFrame, "BackdropTemplate")
    frame:SetSize(CONFIG.PIXEL_SIZE, CONFIG.PIXEL_SIZE)
    frame:SetPoint("TOPLEFT", WorldFrame, "TOPLEFT", CONFIG.START_X, CONFIG.START_Y + yOffset)
    frame:SetIgnoreParentScale(true)
    frame:SetScale(1)
    
    -- Create texture
    local texture = frame:CreateTexture(nil, "ARTWORK")
    texture:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    texture:SetAllPoints(frame)
    
    -- Set initial color (white for rotation frames, black for status frame)
    if isStatusFrame then
        texture:SetVertexColor(0, 0, 0, 1)
    else
        texture:SetVertexColor(1, 1, 1, 1)
    end
    
    -- Debug backdrop (optional - can be removed for production)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0, 0, 0, 0.5)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
    
    frame:Show()
    return frame, texture
end

-- Function to update a rotation frame color based on ConRO window
local function UpdateRotationFrame(texture, conroWindow)
    if conroWindow and conroWindow.fontkey and conroWindow.fontkey:IsVisible() then
        local text = conroWindow.fontkey:GetText()
        if text then
            local number = tonumber(text)
            if number and COLORS[number + 1] then
                local r, g, b = unpack(COLORS[number + 1])
                texture:SetVertexColor(r, g, b, 1)
            else
                texture:SetVertexColor(1, 1, 1, 1)  -- Default to white
            end
        else
            texture:SetVertexColor(1, 1, 1, 1)  -- Default to white
        end
    else
        texture:SetVertexColor(1, 1, 1, 1)  -- Default to white
    end
end

-- Function to update status frame color based on player state
local function UpdateStatusFrame(texture)
    local casting = UnitCastingInfo("player") ~= nil
    local channeling = UnitChannelInfo("player") ~= nil
    local gcdActive = IsGCDActive()
    
    if casting then
        texture:SetVertexColor(1, 0, 0, 1)      -- Red for casting
    elseif channeling then
        texture:SetVertexColor(1, 0.5, 0, 1)    -- Orange for channeling
    elseif gcdActive then
        texture:SetVertexColor(1, 1, 1, 1)      -- White for GCD
    else
        texture:SetVertexColor(0, 0, 0, 1)      -- Black for idle
    end
end

-- Create all rotation frames
for i, config in ipairs(FRAME_CONFIG) do
    local conroWindow, frameName, yOffset = unpack(config)
    local frame, texture = CreatePixelFrame(frameName, yOffset, false)
    frames[i] = {frame = frame, texture = texture, conroWindow = conroWindow}
end

-- Create status frame
local statusFrame, statusTexture = CreatePixelFrame(STATUS_FRAME[2], STATUS_FRAME[3], true)
frames.status = {frame = statusFrame, texture = statusTexture}

-- Main update loop (attached to the first frame)
frames[1].frame:SetScript("OnUpdate", function(self, elapsed)
    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    
    -- Only update at specified interval for performance
    if timeSinceLastUpdate >= CONFIG.UPDATE_INTERVAL then
        timeSinceLastUpdate = 0
        
        -- Update all rotation frames
        for i = 1, #FRAME_CONFIG do
            local frameData = frames[i]
            if frameData then
                UpdateRotationFrame(frameData.texture, frameData.conroWindow)
            end
        end
        
        -- Update status frame
        UpdateStatusFrame(frames.status.texture)
    end
end)
