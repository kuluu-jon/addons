addon.name = 'autofps'
addon.author = 'kuluu-jon'
addon.version = '1.0.0'
addon.desc = 'Tracks FPS over time and adjusts FPS divisor to the lowest possible stable value'

require('common')
local chat = require('chat')
local fonts = require('fonts')
local settings = require('settings')
local imgui = require('imgui')

-- Default Settings
local default_settings = T{
    fps = T{
        format = '%d < %d < %d',
        fps_decrease_threshold = T{ 0.1 },
        fps_increase_threshold = T{ 0.01 },
        min_denominator = T{ 1, },
        max_denominator = T{ 3, },
        updateInterval = T{ 1.0 },
    },
    showWindow = T{ false },
}

-- FPS Variables
local fps = T{
    count = 0,
    timer = 0,
    frame = 0,
    avg = 0,
    font = nil,
    show = true,
    settings = settings.load(default_settings)
}

local fpsSum = 0
local lastFrameTime = 0
local lastUpdateTime = 0
local pointer = 0
--[[
* Updates the addon settings.
*
* @param {table} s - The new settings table to use for the addon settings. (Optional.)
--]]
local function update_settings(s)
    -- Update the settings table..
    if (s ~= nil) then
        fps.settings = s;
    end

    -- Save the current settings..
    settings.save();
end

local function setFpsDenominator(divisor)
    if pointer == 0 then
        print(chat.header(addon.name):append(chat.error('Error: Failed to locate FPS divisor pointer; cannot adjust framerate!')))
        return
    end

    local pointer = ashita.memory.read_uint32(pointer + 0x0C)
    pointer = ashita.memory.read_uint32(pointer)
    ashita.memory.write_uint32(pointer + 0x30, math.round(divisor))
end

local function getFpsDivisor()
    if pointer == 0 then
        print(chat.header(addon.name):append(chat.error('Error: Failed to locate FPS divisor pointer; cannot read current FPS divisor!')))
        return 0
    end

    local pointer = ashita.memory.read_uint32(pointer + 0x0C)
    pointer = ashita.memory.read_uint32(pointer)
    return ashita.memory.read_uint32(pointer + 0x30)
end

local function getLowestStableFpsDivisor()
    -- The minimum and maximum stable FPS divisor value
    local minDenominator = fps.settings.fps.min_denominator[1]
    local maxDenominator = fps.settings.fps.max_denominator[1]

    -- Get the current FPS and divisor values
    local currentDenominator = getFpsDivisor()
    local newDenominator = currentDenominator

    -- The target FPS and thresholds for increasing/decreasing the divisor
    local fpsTarget = 60 / currentDenominator
    local fpsIncreaseThreshold = fps.settings.fps.fps_increase_threshold[1]
    local fpsDecreaseThreshold = fps.settings.fps.fps_decrease_threshold[1]
    local minAverageFps = fpsTarget - (fpsTarget * fpsDecreaseThreshold) -- The minimum average FPS for a 60 FPS target
    local maxAverageFps = fpsTarget - (fpsTarget * fpsIncreaseThreshold) -- The maximum average FPS for a 60 FPS target

    if fps.avg <= minAverageFps then
        -- FPS is below target; increase divisor
        newDenominator = math.min(currentDenominator + 1, maxDenominator)
    elseif fps.avg > maxAverageFps then
        -- FPS is above target; decrease divisor
        newDenominator = math.max(currentDenominator - 1, minDenominator)
    end

    if newDenominator ~= currentDenominator then
        -- Adjust the divisor value if necessary
        setFpsDenominator(newDenominator)
        if (fps.settings.fps.verbose) then
            print(string.format('Adjusted FPS divisor from %d to %d', currentDenominator, newDenominator))
        end
    end

    -- Update the FPS font object..
    -- if (fps.font ~= nil and fps.font.visible == true) then
    --     -- Update the current settings font position..
    --     fps.settings.font.position_x = fps.font.position_x;
    --     fps.settings.font.position_y = fps.font.position_y;

    --     -- Update the font text..
    --     fps.font.text = (fps.settings.fps.format or '%d < %d < %d'):fmt(minAverageFps, fps.avg, maxAverageFps);
    -- end
end
--[[
* Registers a callback for the settings to monitor for character switches.
--]]
settings.register('settings', 'settings_update', update_settings);

--[[
* event: load
* desc : Event called when the addon is being loaded.
--]]
ashita.events.register('load', 'load_cb', function ()
    pointer = ashita.memory.find('FFXiMain.dll', 0, '81EC000100003BC174218B0D', 0, 0)
end);

--[[
* event: unload
* desc : Event called when the addon is being unloaded.
--]]
ashita.events.register('unload', 'unload_cb', function ()
    settings.save();
end);
ashita.events.register('d3d_present', 'd3d_present_cb', function()
    local currentTime = os.clock()
    -- Time since last frame in seconds
    local deltaTime = currentTime - lastFrameTime
    lastFrameTime = currentTime

    -- Skip if no time has passed
    if deltaTime <= 0 then
        return
    end

    -- Calculate current FPS
    local currentFps = 1 / deltaTime

    -- Update moving average
    fps.frame = currentFps
    local fpsCount = fps.count
    fps.avg = (fpsCount * fps.avg + currentFps) / (fpsCount + 1)
    fps.count = fpsCount + 1

    if (currentTime - lastUpdateTime) >= fps.settings.fps.updateInterval[1] then
        lastUpdateTime = currentTime
        getLowestStableFpsDivisor()
        fps.count = 0
        fps.avg = 0
        fps.frame = 0
    end

    if fps.settings.showWindow[1] and imgui.Begin('AutoFPS', fps.settings.showWindow[1], ImGuiWindowFlags_AlwaysAutoResize) then
        imgui.BeginTabBar('SettingsTabs')

        if imgui.BeginTabItem('Settings') then

            if imgui.InputInt('Min Denominator', fps.settings.fps.min_denominator) then
                if fps.settings.fps.min_denominator[1] > fps.settings.fps.max_denominator[1] then
                    fps.settings.fps.max_denominator[1] = fps.settings.fps.min_denominator[1]
                end
            end
            if imgui.InputInt('Max Denominator', fps.settings.fps.max_denominator) then
                if fps.settings.fps.max_denominator[1] < fps.settings.fps.min_denominator[1] then
                    fps.settings.fps.min_denominator[1] = fps.settings.fps.max_denominator[1]
                end
            end
            imgui.InputFloat('Update every n sec', fps.settings.fps.updateInterval, 0.01, 0.1, '%.2f')
            imgui.InputFloat('FPS Decrease Threshold', fps.settings.fps.fps_decrease_threshold, 0.01, 0.1, '%.2f')
            imgui.InputFloat('FPS Increase Threshold', fps.settings.fps.fps_increase_threshold, 0.01, 0.1, '%.2f')

            if imgui.Button('Apply') then
                update_settings(fps.settings)
            end

            imgui.EndTabItem()
        end

        if imgui.BeginTabItem('Debug') then
            imgui.Text('Count: ' .. fps.count)
            imgui.Text('Last Update: ' .. lastUpdateTime)
            imgui.Text('Last Frame: ' .. lastFrameTime)
            imgui.Text('Delta Time: ' .. deltaTime)
            imgui.Text('Current FPS: ' .. currentFps)
            imgui.Text('FPS Sum: ' .. fpsSum)

            imgui.EndTabItem()
        end

        imgui.EndTabBar()
    end
end)


--[[
* event: command
* desc : Event called when the addon is processing a command.
--]]
ashita.events.register('command', 'command_cb', function (e)
    -- Parse the command arguments..
    local args = e.command:args()
    if (#args == 0 or args[1] ~= '/autofps') then
        return
    end

    -- Block all fps related commands..
    e.blocked = true

    fps.settings.showWindow[1] = not fps.settings.showWindow[1]
end)
