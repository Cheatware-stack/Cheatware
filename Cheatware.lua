--[[
    IMP // Aimbot + ESP  (Linoria edition, mstudio45 spec)
    UI: https://github.com/mstudio45/LinoriaLib
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
        Box = true, BoxColor = Color3.fromRGB(255, 40, 40),
        Name = true, NameColor = Color3.fromRGB(255, 255, 255),
        Distance = true, DistanceColor = Color3.fromRGB(200, 200, 200),
        HealthBar = true,
        Tracer = false, TracerColor = Color3.fromRGB(255, 255, 255),
        Chams = false, ChamsColor = Color3.fromRGB(255, 0, 170),
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

-- ========================== AIMBOT ============================
local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness = 2
FOVCircle.NumSides = 64
FOVCircle.Color = Color3.fromRGB(255, 255, 255)
FOVCircle.Transparency = 0.7
FOVCircle.Filled = false
FOVCircle.Visible = false

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
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and not ESPCache[p] then makeESP(p) end
    end
    for plr, _ in pairs(ESPCache) do
        if not plr.Parent then killESP(plr) end
    end

    for plr, e in pairs(ESPCache) do
        local char = plr.Character
        local head = char and char:FindFirstChild("Head")
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        local hum  = char and char:FindFirstChildOfClass("Humanoid")

        if not S.ESP.Enabled or not (head and hrp and hum and hum.Health > 0)
        or (S.ESP.TeamCheck and not isEnemy(plr)) then
            hideESP(e)
        else
            local dist3D = (hrp.Position - Camera.CFrame.Position).Magnitude
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

                    e.box.Visible = S.ESP.Box
                    e.box.Position = Vector2.new(x, y); e.box.Size = Vector2.new(w, h); e.box.Color = S.ESP.BoxColor
                    e.boxOL.Visible = S.ESP.Box
                    e.boxOL.Position = Vector2.new(x, y); e.boxOL.Size = Vector2.new(w, h)

                    e.name.Visible = S.ESP.Name
                    e.name.Position = Vector2.new(x + w/2, y - 16)
                    e.name.Color = S.ESP.NameColor
                    e.name.Text = plr.DisplayName == plr.Name and plr.Name or (plr.DisplayName.." (@"..plr.Name..")")

                    e.dist.Visible = S.ESP.Distance
                    e.dist.Position = Vector2.new(x + w/2, y + h + 2)
                    e.dist.Color = S.ESP.DistanceColor
                    e.dist.Text = string.format("[%dm]", math.floor(dist3D))

                    if S.ESP.HealthBar then
                        local pct = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
                        e.hpBg.Visible=true; e.hpBg.Position=Vector2.new(x-6,y); e.hpBg.Size=Vector2.new(3,h)
                        e.hp.Visible=true
                        e.hp.Position = Vector2.new(x-6, y + h*(1-pct))
                        e.hp.Size = Vector2.new(3, h*pct)
                        e.hp.Color = Color3.fromHSV(pct * 0.33, 1, 1)
                    else
                        e.hp.Visible=false; e.hpBg.Visible=false
                    end

                    if S.ESP.Tracer then
                        local vs = Camera.ViewportSize
                        e.tracer.Visible=true
                        e.tracer.From = Vector2.new(vs.X/2, vs.Y)
                        e.tracer.To = Vector2.new(x + w/2, y + h)
                        e.tracer.Color = S.ESP.TracerColor
                    else
                        e.tracer.Visible=false
                    end

                    if S.ESP.Chams then
                        if not (e.chams and e.chams.Parent) then
                            e.chams = Instance.new("Highlight", char)
                            e.chams.Name = "IMP_Chams"; e.chams.Adornee = char
                            e.chams.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        end
                        e.chams.Enabled = true
                        e.chams.FillColor = S.ESP.ChamsColor
                        e.chams.FillTransparency = 0.5
                    elseif e.chams then e.chams.Enabled = false end
                end
            end
        end
    end
end

-- ========================== LINORIA UI (mstudio45) ============
local repo = "https://raw.githubusercontent.com/mstudio45/LinoriaLib/main/"
local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

Library.ShowCustomCursor = true
Library.NotifySide       = "Left"

local Window = Library:CreateWindow({
    Title = "IMP // Combat",
    Center = true,
    AutoShow = true,
    Resizable = false,
    TabPadding = 8,
    MenuFadeTime = 0.2
})

local Tabs = {
    Aimbot              = Window:AddTab("Aimbot"),
    ESP                 = Window:AddTab("ESP"),
    ["UI Settings"]     = Window:AddTab("UI Settings"),
}

-- ============== AIMBOT TAB ==============
local AimLeft  = Tabs.Aimbot:AddLeftGroupbox("Core")
local AimRight = Tabs.Aimbot:AddRightGroupbox("Targeting")

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

-- Wire callbacks via OnChanged (mstudio45 recommended pattern)
Toggles.AimEn:OnChanged(function() S.Aimbot.Enabled = Toggles.AimEn.Value end)
Toggles.AimShowFov:OnChanged(function() S.Aimbot.ShowFOV = Toggles.AimShowFov.Value end)
Options.AimFov:OnChanged(function() S.Aimbot.FOV = Options.AimFov.Value end)
Options.AimSmooth:OnChanged(function() S.Aimbot.Smoothness = Options.AimSmooth.Value end)
Options.AimPart:OnChanged(function() S.Aimbot.TargetPart = Options.AimPart.Value end)
Toggles.AimTeam:OnChanged(function() S.Aimbot.TeamCheck = Toggles.AimTeam.Value end)
Toggles.AimWall:OnChanged(function() S.Aimbot.WallCheck = Toggles.AimWall.Value end)

-- ============== ESP TAB ==============
local ESPLeft  = Tabs.ESP:AddLeftGroupbox("Core")
local ESPRight = Tabs.ESP:AddRightGroupbox("Elements")

ESPLeft:AddToggle("ESPEn", {Text = "Enabled", Default = false})
ESPLeft:AddToggle("ESPTeam", {Text = "Team Check", Default = true})
ESPLeft:AddSlider("ESPDist", {Text = "Max Distance", Default = 5000, Min = 100, Max = 10000, Rounding = 0})

ESPRight:AddToggle("ESPBox", {Text = "Box", Default = true}):AddColorPicker("ESPBoxCol", {Default = S.ESP.BoxColor, Title = "Box Color"})
ESPRight:AddToggle("ESPName", {Text = "Name", Default = true}):AddColorPicker("ESPNameCol", {Default = S.ESP.NameColor, Title = "Name Color"})
ESPRight:AddToggle("ESPDistance", {Text = "Distance", Default = true}):AddColorPicker("ESPDistCol", {Default = S.ESP.DistanceColor, Title = "Distance Color"})
ESPRight:AddToggle("ESPHP", {Text = "Health Bar (Reactive)", Default = true})
ESPRight:AddToggle("ESPTracer", {Text = "Tracer", Default = false}):AddColorPicker("ESPTracerCol", {Default = S.ESP.TracerColor, Title = "Tracer Color"})
ESPRight:AddToggle("ESPChams", {Text = "Chams (Through Walls)", Default = false}):AddColorPicker("ESPChamsCol", {Default = S.ESP.ChamsColor, Title = "Chams Color"})

Toggles.ESPEn:OnChanged(function() S.ESP.Enabled = Toggles.ESPEn.Value end)
Toggles.ESPTeam:OnChanged(function() S.ESP.TeamCheck = Toggles.ESPTeam.Value end)
Options.ESPDist:OnChanged(function() S.ESP.MaxDistance = Options.ESPDist.Value end)

Toggles.ESPBox:OnChanged(function() S.ESP.Box = Toggles.ESPBox.Value end)
Toggles.ESPName:OnChanged(function() S.ESP.Name = Toggles.ESPName.Value end)
Toggles.ESPDistance:OnChanged(function() S.ESP.Distance = Toggles.ESPDistance.Value end)
Toggles.ESPHP:OnChanged(function() S.ESP.HealthBar = Toggles.ESPHP.Value end)
Toggles.ESPTracer:OnChanged(function() S.ESP.Tracer = Toggles.ESPTracer.Value end)
Toggles.ESPChams:OnChanged(function() S.ESP.Chams = Toggles.ESPChams.Value end)

Options.ESPBoxCol:OnChanged(function() S.ESP.BoxColor = Options.ESPBoxCol.Value end)
Options.ESPNameCol:OnChanged(function() S.ESP.NameColor = Options.ESPNameCol.Value end)
Options.ESPDistCol:OnChanged(function() S.ESP.DistanceColor = Options.ESPDistCol.Value end)
Options.ESPTracerCol:OnChanged(function() S.ESP.TracerColor = Options.ESPTracerCol.Value end)
Options.ESPChamsCol:OnChanged(function() S.ESP.ChamsColor = Options.ESPChamsCol.Value end)

-- ============== UI SETTINGS TAB ==============
local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu")

MenuGroup:AddToggle("KeybindMenuOpen", {Default = Library.KeybindFrame.Visible, Text = "Open Keybind Menu",
    Callback = function(v) Library.KeybindFrame.Visible = v end})
MenuGroup:AddToggle("ShowCustomCursor", {Text = "Custom Cursor", Default = true,
    Callback = function(v) Library.ShowCustomCursor = v end})
MenuGroup:AddDivider()
MenuGroup:AddLabel("Menu Bind"):AddKeyPicker("MenuKeybind", {Default = "RightShift", NoUI = true, Text = "Menu Keybind"})
MenuGroup:AddButton({Text = "Unload", Func = function() Library:Unload() end})

Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({"MenuKeybind"})
ThemeManager:SetFolder("ImpCombat")
SaveManager:SetFolder("ImpCombat/Aimbot")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()

-- ========================== MAIN LOOP =========================
local MainLoop = RunService.RenderStepped:Connect(function()
    if Library.Unloaded then return end
    local mLoc = UserInputService:GetMouseLocation()

    FOVCircle.Position = mLoc
    FOVCircle.Radius = S.Aimbot.FOV
    FOVCircle.Visible = S.Aimbot.Enabled and S.Aimbot.ShowFOV

    if S.Aimbot.Enabled and Options.AimKey and Options.AimKey:GetState() then
        aimAt(getClosestPlayer())
    end

    updateESP()
end)

Library:OnUnload(function()
    if MainLoop then MainLoop:Disconnect() end
    pcall(function() FOVCircle:Remove() end)
    for plr, _ in pairs(ESPCache) do killESP(plr) end
    Library.Unloaded = true
    print("[IMP] Unloaded")
end)

Library:Notify("IMP Combat loaded — Right Shift toggles UI", 4)
print("[IMP] Linoria edition v2 loaded.")
