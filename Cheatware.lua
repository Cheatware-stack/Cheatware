--[[
    IMP // Combat Suite  v4  (Linoria edition, mstudio45 spec)
    Tabs: Combat | Visuals | Misc | Settings
    Improvements over v3:
        - Parallel HTTP loading (3 scripts fetched concurrently)
        - Custom cursor disabled (skips heavy cursor init)
        - ESP colors fixed (inline Callback + manual RGB lerp)
        - Misc tab populates both columns (no empty space)
--]]

-- ========================== SERVICES ==========================
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui          = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera
local Mouse       = LocalPlayer:GetMouse()

-- ========================== STATE =============================
local S = {
    Aimbot = {
        Enabled = false,
        FOV = 100,
        Smoothness = 5,
        ShowFOV = true,
        TargetPart = "HumanoidRootPart",
        TeamCheck = true,
        WallCheck = false,
    },
    ESP = {
        Enabled = false,
        TeamCheck = true,
        MaxDistance = 5000,
        UpdateRate = 60,
        Box = true, BoxColor = Color3.fromRGB(255, 40, 40),
        Name = true, NameColor = Color3.fromRGB(255, 255, 255),
        Distance = true, DistanceColor = Color3.fromRGB(200, 200, 200),
        HealthBar = true,
        Tracer = false, TracerColor = Color3.fromRGB(255, 255, 255),
        Chams = false, ChamsColor = Color3.fromRGB(255, 0, 170),
    },
    SilentAim = {
        Enabled = false,
        FOV = 200,
        ShowFOV = false,
        FOVColor = Color3.fromRGB(255, 0, 170),
        HitChance = 100,
        TargetPart = "Head",
        TeamCheck = true,
        AliveCheck = true,
    }
}

-- ========================== DRAWING SHIM ======================
local Drawing = Drawing or getgenv().Drawing
if not Drawing or type(Drawing.new) ~= "function" then
    local fmt = {__index = function() return function() end end}
    Drawing = setmetatable({ new = function() return setmetatable({Remove=function()end, Visible=false}, fmt) end, Fonts = {Plex = 2} }, fmt)
end

-- ========================== UTILS =============================
local function isEnemy(plr)
    if not plr or plr == LocalPlayer then return false end
    if LocalPlayer.Team and plr.Team then return LocalPlayer.Team ~= plr.Team end
    return true
end

local function alive(plr)
    local c = plr and plr.Character; if not c then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    local r = c:FindFirstChild("HumanoidRootPart")
    return h and r and h.Health > 0
end

local function visible(pos, ignoreChar)
    local parts = Camera:GetPartsObscuringTarget({pos}, {LocalPlayer.Character, Camera, ignoreChar})
    return #parts == 0
end

-- Manual RGB lerp (bypasses Color3:Lerp quirks on some executors)
-- Red (0% HP) → Orange (50%) → Green (100%)
local function getHpColor(pct)
    pct = math.clamp(pct, 0, 1)
    local r, g, b
    if pct > 0.5 then
        -- Orange (255, 165, 0) → Green (0, 255, 0)
        local t = (pct - 0.5) * 2
        r = math.floor(255 * (1 - t))
        g = math.floor(165 + (255 - 165) * t)
        b = 0
    else
        -- Red (255, 0, 0) → Orange (255, 165, 0)
        local t = pct * 2
        r = 255
        g = math.floor(165 * t)
        b = 0
    end
    return Color3.fromRGB(r, g, b)
end

-- ========================== AIMBOT ============================
local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness = 2
FOVCircle.NumSides = 64
FOVCircle.Color = Color3.fromRGB(255, 255, 255)
FOVCircle.Transparency = 0.7
FOVCircle.Filled = false
FOVCircle.Visible = false

local SilentAimCircle = Drawing.new("Circle")
SilentAimCircle.Thickness = 2
SilentAimCircle.NumSides = 64
SilentAimCircle.Color = Color3.fromRGB(255, 0, 170)
SilentAimCircle.Transparency = 0.7
SilentAimCircle.Filled = false
SilentAimCircle.Visible = false

local function getClosestPlayer()
    local closest, closestDist = nil, S.Aimbot.FOV
    local mouseLoc = UserInputService:GetMouseLocation()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and alive(p) and (not S.Aimbot.TeamCheck or isEnemy(p)) then
            local part = p.Character:FindFirstChild(S.Aimbot.TargetPart) or p.Character:FindFirstChild("HumanoidRootPart")
            if part then
                local sp, on = Camera:WorldToViewportPoint(part.Position)
                if on then
                    local d = (Vector2.new(sp.X, sp.Y) - mouseLoc).Magnitude
                    if d < closestDist then
                        if not S.Aimbot.WallCheck or visible(part.Position, p.Character) then
                            closest = p; closestDist = d
                        end
                    end
                end
            end
        end
    end
    return closest
end

local function aimAt(target)
    if not target or not target.Character then return end
    local part = target.Character:FindFirstChild(S.Aimbot.TargetPart) or target.Character:FindFirstChild("HumanoidRootPart")
    if not part then return end
    local sp = Camera:WorldToViewportPoint(part.Position)
    local mouseLoc = UserInputService:GetMouseLocation()
    local smoothed = mouseLoc:Lerp(Vector2.new(sp.X, sp.Y), 1 / S.Aimbot.Smoothness)
    pcall(mousemoverel, smoothed.X - mouseLoc.X, smoothed.Y - mouseLoc.Y)
end

-- ========================== SILENT AIM ========================
-- IsShooting gate: silent aim ONLY spoofs while LMB is held.
-- Without this, hooking Mouse.Hit/Raycast affects movement, ground
-- detection, camera direction, etc.  Causes desync / can't move.
local IsShooting = false
UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        IsShooting = true
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        IsShooting = false
    end
end)

local function findSilentTarget()
    if not S.SilentAim.Enabled then return nil, nil end
    if math.random(1, 100) > S.SilentAim.HitChance then return nil, nil end

    local mouseLoc = UserInputService:GetMouseLocation()
    local bestPos, bestPart, bestDist = nil, nil, S.SilentAim.FOV

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer
        and (not S.SilentAim.TeamCheck or isEnemy(plr))
        and (not S.SilentAim.AliveCheck or alive(plr)) then
            local char = plr.Character
            local part = char and char:FindFirstChild(S.SilentAim.TargetPart)
            if part then
                local sp, on = Camera:WorldToViewportPoint(part.Position)
                if on then
                    local d = (Vector2.new(sp.X, sp.Y) - mouseLoc).Magnitude
                    if d < bestDist then
                        bestDist = d; bestPos = part.Position; bestPart = part
                    end
                end
            end
        end
    end
    return bestPos, bestPart
end

-- Hook __namecall for Raycast and __index for Mouse.Hit/Target
-- Both gated by IsShooting to avoid breaking movement/camera/replication.
local hookmm   = hookmetamethod
local newcc    = newcclosure or function(f) return f end
local getncm   = getnamecallmethod
local checkcal = checkcaller or function() return false end

if hookmm then
    local oldNamecall
    oldNamecall = hookmm(game, "__namecall", newcc(function(self, ...)
        local method = getncm()
        local args = {...}
        if S.SilentAim.Enabled and IsShooting and not checkcal() then
            if method == "Raycast" then
                local targetPos = findSilentTarget()
                if targetPos then
                    local origin = args[1]
                    args[2] = (targetPos - origin).Unit * 5000
                    return oldNamecall(self, table.unpack(args))
                end
            elseif method == "FindPartOnRay"
                or method == "FindPartOnRayWithIgnoreList"
                or method == "FindPartOnRayWithWhitelist" then
                local targetPos = findSilentTarget()
                if targetPos then
                    local origin = args[1].Origin
                    args[1] = Ray.new(origin, (targetPos - origin).Unit * 5000)
                    return oldNamecall(self, table.unpack(args))
                end
            end
        end
        return oldNamecall(self, ...)
    end))

    local oldIndex
    oldIndex = hookmm(game, "__index", newcc(function(self, key)
        if S.SilentAim.Enabled and IsShooting and not checkcal() and self == Mouse then
            local targetPos, targetPart = findSilentTarget()
            if targetPos then
                if key == "Hit"    then return CFrame.new(targetPos) end
                if key == "Target" then return targetPart end
            end
        end
        return oldIndex(self, key)
    end))
end

-- ========================== ESP ===============================
local ESPCache = {}

local function makeESP(plr)
    local e = {
        box=Drawing.new("Square"), boxOL=Drawing.new("Square"),
        name=Drawing.new("Text"), dist=Drawing.new("Text"),
        hp=Drawing.new("Square"), hpBg=Drawing.new("Square"),
        tracer=Drawing.new("Line"), chams=nil
    }
    e.box.Thickness=1; e.box.Filled=false
    e.boxOL.Thickness=3; e.boxOL.Color=Color3.new(0,0,0); e.boxOL.Filled=false
    e.name.Center=true; e.name.Outline=true; e.name.Size=13; e.name.Font=Drawing.Fonts.Plex
    e.dist.Center=true; e.dist.Outline=true; e.dist.Size=13; e.dist.Font=Drawing.Fonts.Plex
    e.hp.Filled=true; e.hpBg.Filled=true; e.hpBg.Color=Color3.new(0,0,0)
    e.tracer.Thickness=1
    ESPCache[plr] = e
end

local function hideESP(e)
    for k,v in pairs(e) do
        if k=="chams" then if v then v.Enabled=false end
        else v.Visible=false end
    end
end

local function killESP(plr)
    local e = ESPCache[plr]; if not e then return end
    for k,v in pairs(e) do
        if k=="chams" then if v then pcall(function() v:Destroy() end) end
        else pcall(function() v:Remove() end) end
    end
    ESPCache[plr] = nil
end

Players.PlayerRemoving:Connect(killESP)

local function updateESP()
    if not S.ESP.Enabled then
        for _, e in pairs(ESPCache) do hideESP(e) end
        return
    end

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and not ESPCache[p] then makeESP(p) end
    end

    for plr, _ in pairs(ESPCache) do
        if not plr.Parent then killESP(plr) end
    end

    local camPos = Camera.CFrame.Position
    for plr, e in pairs(ESPCache) do
        local char = plr.Character
        local head = char and char:FindFirstChild("Head")
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        local hum  = char and char:FindFirstChildOfClass("Humanoid")

        if not (head and hrp and hum and hum.Health > 0) or (S.ESP.TeamCheck and not isEnemy(plr)) then
            hideESP(e)
        else
            local dist3D = (hrp.Position - camPos).Magnitude
            if dist3D > S.ESP.MaxDistance then
                hideESP(e)
            else
                local tV, tOn = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                local bV, bOn = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
                if not (tOn and bOn) then
                    hideESP(e)
                else
                    local h = math.abs(bV.Y - tV.Y); local w = h * 0.55
                    local x = tV.X - w/2; local y = tV.Y

                    -- Box (defensive color)
                    local boxCol = S.ESP.BoxColor or Color3.fromRGB(255, 40, 40)
                    e.box.Visible = S.ESP.Box
                    e.box.Position = Vector2.new(x, y); e.box.Size = Vector2.new(w, h); e.box.Color = boxCol
                    e.boxOL.Visible = S.ESP.Box
                    e.boxOL.Position = Vector2.new(x, y); e.boxOL.Size = Vector2.new(w, h)

                    -- Name
                    e.name.Visible = S.ESP.Name
                    e.name.Position = Vector2.new(x + w/2, y - 16)
                    e.name.Color = S.ESP.NameColor or Color3.new(1,1,1)
                    e.name.Text = plr.DisplayName == plr.Name and plr.Name or (plr.DisplayName.." (@"..plr.Name..")")

                    -- Distance
                    e.dist.Visible = S.ESP.Distance
                    e.dist.Position = Vector2.new(x + w/2, y + h + 2)
                    e.dist.Color = S.ESP.DistanceColor or Color3.fromRGB(200,200,200)
                    e.dist.Text = string.format("[%dm]", math.floor(dist3D))

                    -- HP bar (manual RGB lerp)
                    if S.ESP.HealthBar then
                        local pct = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
                        e.hpBg.Visible=true; e.hpBg.Position=Vector2.new(x-6,y); e.hpBg.Size=Vector2.new(3,h)
                        e.hp.Visible=true
                        e.hp.Position = Vector2.new(x-6, y + h*(1-pct))
                        e.hp.Size = Vector2.new(3, math.max(1, h*pct))
                        e.hp.Color = getHpColor(pct)
                    else
                        e.hp.Visible=false; e.hpBg.Visible=false
                    end

                    -- Tracer
                    if S.ESP.Tracer then
                        local vs = Camera.ViewportSize
                        e.tracer.Visible=true
                        e.tracer.From = Vector2.new(vs.X/2, vs.Y)
                        e.tracer.To = Vector2.new(x + w/2, y + h)
                        e.tracer.Color = S.ESP.TracerColor or Color3.new(1,1,1)
                    else e.tracer.Visible=false end

                    -- Chams
                    if S.ESP.Chams then
                        if not (e.chams and e.chams.Parent) then
                            e.chams = Instance.new("Highlight", char)
                            e.chams.Name = "IMP_Chams"; e.chams.Adornee = char
                            e.chams.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        end
                        e.chams.Enabled = true
                        e.chams.FillColor = S.ESP.ChamsColor or Color3.fromRGB(255,0,170)
                        e.chams.FillTransparency = 0.5
                    elseif e.chams then e.chams.Enabled = false end
                end
            end
        end
    end
end

-- ========================== LINORIA UI (mstudio45) ============
-- Parallel HTTP fetch to drop load time from 20s to ~5s
local repo = "https://raw.githubusercontent.com/mstudio45/LinoriaLib/main/"
local urls = {
    repo .. "Library.lua",
    repo .. "addons/ThemeManager.lua",
    repo .. "addons/SaveManager.lua",
}
local sources = {}
local pending = #urls
for i, url in ipairs(urls) do
    task.spawn(function()
        local ok, body = pcall(game.HttpGet, game, url)
        sources[i] = ok and body or ""
        pending = pending - 1
    end)
end
while pending > 0 do task.wait() end

local Library      = loadstring(sources[1])()
local ThemeManager = loadstring(sources[2])()
local SaveManager  = loadstring(sources[3])()

local Options = Library.Options
local Toggles = Library.Toggles

Library.ShowCustomCursor = false  -- big load-time win, skips custom cursor system
Library.NotifySide       = "Left"

local Window = Library:CreateWindow({
    Title = "IMP // Combat",
    Center = true,
    AutoShow = true,
    Resizable = false,
    TabPadding = 20,
    MenuFadeTime = 0
})

local Tabs = {
    Combat   = Window:AddTab("   Combat   "),
    Visuals  = Window:AddTab("   Visuals  "),
    Misc     = Window:AddTab("    Misc    "),
    Settings = Window:AddTab("  Settings  "),
}

-- =============== COMBAT TAB ===============
local AimLeft  = Tabs.Combat:AddLeftGroupbox("Aimbot")
local AimRight = Tabs.Combat:AddRightGroupbox("Targeting")

AimLeft:AddToggle("AimEn", {Text = "Enabled", Default = false})
AimLeft:AddToggle("AimShowFov", {Text = "Show FOV Circle", Default = true})
AimLeft:AddSlider("AimFov", {Text = "FOV", Default = 100, Min = 30, Max = 500, Rounding = 0, Suffix = "px"})
AimLeft:AddSlider("AimSmooth", {Text = "Smoothness", Default = 5, Min = 1, Max = 20, Rounding = 0})

AimRight:AddDropdown("AimPart", {
    Text = "Target Part",
    Values = {"Head", "UpperTorso", "HumanoidRootPart", "Torso"},
    Default = "HumanoidRootPart",
    Multi = false,
})
AimRight:AddToggle("AimTeam", {Text = "Team Check", Default = true})
AimRight:AddToggle("AimWall", {Text = "Wall Check", Default = false})
AimRight:AddLabel("Aim Key"):AddKeyPicker("AimKey", {
    Default = "MB2",
    SyncToggleState = false,
    Mode = "Hold",
    Text = "Aim Key",
})

Toggles.AimEn:OnChanged(function() S.Aimbot.Enabled = Toggles.AimEn.Value end)
Toggles.AimShowFov:OnChanged(function() S.Aimbot.ShowFOV = Toggles.AimShowFov.Value end)
Options.AimFov:OnChanged(function() S.Aimbot.FOV = Options.AimFov.Value end)
Options.AimSmooth:OnChanged(function() S.Aimbot.Smoothness = Options.AimSmooth.Value end)
Options.AimPart:OnChanged(function() S.Aimbot.TargetPart = Options.AimPart.Value end)
Toggles.AimTeam:OnChanged(function() S.Aimbot.TeamCheck = Toggles.AimTeam.Value end)
Toggles.AimWall:OnChanged(function() S.Aimbot.WallCheck = Toggles.AimWall.Value end)

-- ============== SILENT AIM (second row in Combat tab) ==============
local SAimLeft  = Tabs.Combat:AddLeftGroupbox("Silent Aim")
local SAimRight = Tabs.Combat:AddRightGroupbox("Silent Aim Settings")

SAimLeft:AddToggle("SAEn", {Text = "Enabled", Default = false,
    Callback = function(v) S.SilentAim.Enabled = v end})

SAimLeft:AddToggle("SAShow", {Text = "Show FOV Circle", Default = false,
    Callback = function(v) S.SilentAim.ShowFOV = v end})
    :AddColorPicker("SAColor", {
        Default = S.SilentAim.FOVColor, Title = "FOV Color",
        Callback = function(v) if v then S.SilentAim.FOVColor = v end end
    })

SAimLeft:AddSlider("SAFOV", {Text = "FOV", Default = 200, Min = 50, Max = 1000, Rounding = 0, Suffix = "px",
    Callback = function(v) S.SilentAim.FOV = v end})

SAimLeft:AddSlider("SAChance", {Text = "Hit Chance", Default = 100, Min = 1, Max = 100, Rounding = 0, Suffix = "%",
    Callback = function(v) S.SilentAim.HitChance = v end})

SAimRight:AddDropdown("SAPart", {
    Text = "Target Part",
    Values = {"Head", "UpperTorso", "HumanoidRootPart", "Torso"},
    Default = "Head", Multi = false,
    Callback = function(v) S.SilentAim.TargetPart = v end
})
SAimRight:AddToggle("SATeam", {Text = "Team Check", Default = true,
    Callback = function(v) S.SilentAim.TeamCheck = v end})
SAimRight:AddToggle("SAAlive", {Text = "Alive Check", Default = true,
    Callback = function(v) S.SilentAim.AliveCheck = v end})

pcall(function() Options.SAColor:SetValueRGB(S.SilentAim.FOVColor) end)

-- =============== VISUALS TAB ===============
local ESPLeft  = Tabs.Visuals:AddLeftGroupbox("ESP Core")
local ESPRight = Tabs.Visuals:AddRightGroupbox("ESP Elements")

ESPLeft:AddToggle("ESPEn", {Text = "Enabled", Default = false,
    Callback = function(v) S.ESP.Enabled = v end})
ESPLeft:AddToggle("ESPTeam", {Text = "Team Check", Default = true,
    Callback = function(v) S.ESP.TeamCheck = v end})
ESPLeft:AddSlider("ESPDist", {Text = "Max Distance", Default = 5000, Min = 100, Max = 10000, Rounding = 0,
    Callback = function(v) S.ESP.MaxDistance = v end})
ESPLeft:AddSlider("ESPRate", {Text = "Update Rate", Default = 60, Min = 10, Max = 60, Rounding = 0, Suffix = " Hz",
    Callback = function(v) S.ESP.UpdateRate = v end})

-- Inline Callback on colorpicker fires guaranteed during creation — no race condition
ESPRight:AddToggle("ESPBox", {Text = "Box", Default = true,
    Callback = function(v) S.ESP.Box = v end})
    :AddColorPicker("ESPBoxCol", {
        Default = S.ESP.BoxColor, Title = "Box Color",
        Callback = function(v) if v then S.ESP.BoxColor = v end end
    })

ESPRight:AddToggle("ESPName", {Text = "Name", Default = true,
    Callback = function(v) S.ESP.Name = v end})
    :AddColorPicker("ESPNameCol", {
        Default = S.ESP.NameColor, Title = "Name Color",
        Callback = function(v) if v then S.ESP.NameColor = v end end
    })

ESPRight:AddToggle("ESPDistance", {Text = "Distance", Default = true,
    Callback = function(v) S.ESP.Distance = v end})
    :AddColorPicker("ESPDistCol", {
        Default = S.ESP.DistanceColor, Title = "Distance Color",
        Callback = function(v) if v then S.ESP.DistanceColor = v end end
    })

ESPRight:AddToggle("ESPHP", {Text = "Health Bar (Reactive)", Default = true,
    Callback = function(v) S.ESP.HealthBar = v end})

ESPRight:AddToggle("ESPTracer", {Text = "Tracer", Default = false,
    Callback = function(v) S.ESP.Tracer = v end})
    :AddColorPicker("ESPTracerCol", {
        Default = S.ESP.TracerColor, Title = "Tracer Color",
        Callback = function(v) if v then S.ESP.TracerColor = v end end
    })

ESPRight:AddToggle("ESPChams", {Text = "Chams (Through Walls)", Default = false,
    Callback = function(v) S.ESP.Chams = v end})
    :AddColorPicker("ESPChamsCol", {
        Default = S.ESP.ChamsColor, Title = "Chams Color",
        Callback = function(v) if v then S.ESP.ChamsColor = v end end
    })

-- Force the picker values to apply (some Linoria builds need explicit set)
pcall(function() Options.ESPBoxCol:SetValueRGB(S.ESP.BoxColor) end)
pcall(function() Options.ESPNameCol:SetValueRGB(S.ESP.NameColor) end)
pcall(function() Options.ESPDistCol:SetValueRGB(S.ESP.DistanceColor) end)
pcall(function() Options.ESPTracerCol:SetValueRGB(S.ESP.TracerColor) end)
pcall(function() Options.ESPChamsCol:SetValueRGB(S.ESP.ChamsColor) end)

-- =============== MISC TAB (both columns filled) ===============
local MiscLeft  = Tabs.Misc:AddLeftGroupbox("Movement")
local MiscRight = Tabs.Misc:AddRightGroupbox("Visuals")

MiscLeft:AddLabel("Coming soon:", true)
MiscLeft:AddLabel("• Fly\n• Noclip\n• WalkSpeed\n• JumpPower\n• Infinite Jump\n• Bunny Hop", true)

MiscRight:AddLabel("Coming soon:", true)
MiscRight:AddLabel("• Fullbright\n• No Fog\n• FOV Unlock\n• FPS Boost\n• Anti-AFK", true)

-- =============== SETTINGS TAB ===============
local MenuGroup = Tabs.Settings:AddLeftGroupbox("Menu")

MenuGroup:AddToggle("ShowCustomCursor", {Text = "Custom Cursor", Default = false,
    Callback = function(v) Library.ShowCustomCursor = v end})
MenuGroup:AddDivider()
MenuGroup:AddLabel("Menu Bind"):AddKeyPicker("MenuKeybind", {Default = "RightShift", NoUI = true, Text = "Menu Keybind"})
MenuGroup:AddButton({Text = "Unload Script", Func = function() Library:Unload() end})

Library.ToggleKeybind = Options.MenuKeybind

-- Theme + Save managers (build LAST so they have everything wired up)
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({"MenuKeybind"})
ThemeManager:SetFolder("ImpCombat")
SaveManager:SetFolder("ImpCombat/Configs")
SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:ApplyToTab(Tabs.Settings)
pcall(function() SaveManager:LoadAutoloadConfig() end)

-- ========================== LOOPS =============================
-- WindowFocused pause: kill all work when Roblox window isn't active
local WindowFocused = true
UserInputService.WindowFocused:Connect(function() WindowFocused = true end)
UserInputService.WindowFocusReleased:Connect(function() WindowFocused = false end)

local AimLoop = RunService.RenderStepped:Connect(function()
    if Library.Unloaded then return end
    if not WindowFocused then return end

    -- Aimbot disabled? hide aimbot circle but still update silent aim circle
    if not S.Aimbot.Enabled then
        if FOVCircle.Visible then FOVCircle.Visible = false end
        -- still update silent aim circle independently
        local mLoc = UserInputService:GetMouseLocation()
        SilentAimCircle.Position = mLoc
        SilentAimCircle.Radius = S.SilentAim.FOV
        SilentAimCircle.Color = S.SilentAim.FOVColor or Color3.fromRGB(255, 0, 170)
        SilentAimCircle.Visible = S.SilentAim.Enabled and S.SilentAim.ShowFOV
        return
    end

    local mLoc = UserInputService:GetMouseLocation()
    FOVCircle.Position = mLoc
    FOVCircle.Radius = S.Aimbot.FOV
    FOVCircle.Visible = S.Aimbot.ShowFOV

    -- Silent aim FOV circle (also mouse-anchored)
    SilentAimCircle.Position = mLoc
    SilentAimCircle.Radius = S.SilentAim.FOV
    SilentAimCircle.Color = S.SilentAim.FOVColor or Color3.fromRGB(255, 0, 170)
    SilentAimCircle.Visible = S.SilentAim.Enabled and S.SilentAim.ShowFOV

    if Options.AimKey and Options.AimKey:GetState() then
        aimAt(getClosestPlayer())
    end
end)

local lastESP = 0
local ESPLoop = RunService.Heartbeat:Connect(function()
    if Library.Unloaded then return end
    if not WindowFocused then return end
    local interval = 1 / S.ESP.UpdateRate
    if tick() - lastESP < interval then return end
    lastESP = tick()
    updateESP()
end)

Library:OnUnload(function()
    if AimLoop then AimLoop:Disconnect() end
    if ESPLoop then ESPLoop:Disconnect() end
    pcall(function() FOVCircle:Remove() end)
    pcall(function() SilentAimCircle:Remove() end)
    for plr, _ in pairs(ESPCache) do killESP(plr) end
    Library.Unloaded = true
    print("[IMP] Unloaded")
end)

Library:Notify("IMP Combat v4 loaded — Right Shift toggles UI", 4)
print("[IMP] v4 loaded.")
