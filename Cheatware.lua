--[[
    IMP // Aimbot + ESP
    Modern custom UI · Drawing API ESP · mousemoverel aimbot
--]]

-- ========================== SERVICES ==========================
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")
local TweenService     = game:GetService("TweenService")
local CoreGui          = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera
local Mouse       = LocalPlayer:GetMouse()

-- ========================== STATE =============================
local S = {
    Aimbot = {
        Enabled = true,
        FOV = 100,
        Smoothness = 5,
        ShowFOV = true,
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

local HoldingAimKey = false

-- ========================== DRAWING SHIM ======================
local Drawing = Drawing or getgenv().Drawing
if not Drawing or type(Drawing.new) ~= "function" then
    local fmt = {__index = function() return function() end end}
    Drawing = setmetatable({ new = function() return setmetatable({Remove=function()end, Visible=false}, fmt) end, Fonts = {Plex = 2} }, fmt)
end

-- ========================== UTILS =============================
local function isEnemy(plr)
    if not plr or plr == LocalPlayer then return false end
    if not S.ESP.TeamCheck then return true end
    if LocalPlayer.Team and plr.Team then
        return LocalPlayer.Team ~= plr.Team
    end
    return true
end

local function alive(plr)
    local c = plr and plr.Character
    if not c then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    local r = c:FindFirstChild("HumanoidRootPart")
    return h and r and h.Health > 0
end

-- ========================== AIMBOT ============================
local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness = 2
FOVCircle.NumSides = 64
FOVCircle.Color = Color3.fromRGB(255, 255, 255)
FOVCircle.Transparency = 0.7
FOVCircle.Filled = false
FOVCircle.Visible = true

local function getClosestPlayer()
    local closest, closestDist = nil, S.Aimbot.FOV
    local mouseLoc = UserInputService:GetMouseLocation()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and alive(p) and isEnemy(p) then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local sp, on = Camera:WorldToViewportPoint(hrp.Position)
                if on then
                    local d = (Vector2.new(sp.X, sp.Y) - mouseLoc).Magnitude
                    if d < closestDist then
                        closest = p; closestDist = d
                    end
                end
            end
        end
    end
    return closest
end

local function aimAt(target)
    if not target or not target.Character then return end
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local sp = Camera:WorldToViewportPoint(hrp.Position)
    local mouseLoc = UserInputService:GetMouseLocation()
    local smoothed = mouseLoc:Lerp(Vector2.new(sp.X, sp.Y), 1 / S.Aimbot.Smoothness)
    pcall(mousemoverel, smoothed.X - mouseLoc.X, smoothed.Y - mouseLoc.Y)
end

-- ========================== ESP ===============================
local ESPCache = {}

local function makeESP(plr)
    local e = {
        box      = Drawing.new("Square"),
        boxOL    = Drawing.new("Square"),
        name     = Drawing.new("Text"),
        dist     = Drawing.new("Text"),
        hp       = Drawing.new("Square"),
        hpBg     = Drawing.new("Square"),
        tracer   = Drawing.new("Line"),
        chams    = nil,
    }
    e.box.Thickness = 1; e.box.Filled = false
    e.boxOL.Thickness = 3; e.boxOL.Color = Color3.new(0,0,0); e.boxOL.Filled = false
    e.name.Center = true; e.name.Outline = true; e.name.Size = 13; e.name.Font = Drawing.Fonts.Plex
    e.dist.Center = true; e.dist.Outline = true; e.dist.Size = 13; e.dist.Font = Drawing.Fonts.Plex
    e.hp.Filled = true; e.hpBg.Filled = true; e.hpBg.Color = Color3.new(0,0,0)
    e.tracer.Thickness = 1
    ESPCache[plr] = e
end

local function hideESP(e)
    for k, v in pairs(e) do
        if k == "chams" then if v then v.Enabled = false end
        else v.Visible = false end
    end
end

local function killESP(plr)
    local e = ESPCache[plr]; if not e then return end
    for k, v in pairs(e) do
        if k == "chams" then if v then pcall(function() v:Destroy() end) end
        else pcall(function() v:Remove() end) end
    end
    ESPCache[plr] = nil
end

Players.PlayerRemoving:Connect(killESP)

local function updateESP()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and not ESPCache[p] then makeESP(p) end
    end

    for plr, e in pairs(ESPCache) do
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
                    local h = math.abs(bV.Y - tV.Y)
                    local w = h * 0.55
                    local x = tV.X - w/2
                    local y = tV.Y

                    e.box.Visible = S.ESP.Box
                    e.box.Position = Vector2.new(x, y); e.box.Size = Vector2.new(w, h); e.box.Color = S.ESP.BoxColor
                    e.boxOL.Visible = S.ESP.Box
                    e.boxOL.Position = Vector2.new(x, y); e.boxOL.Size = Vector2.new(w, h)

                    e.name.Visible = S.ESP.Name
                    e.name.Position = Vector2.new(x + w/2, y - 16)
                    e.name.Color = S.ESP.NameColor
                    e.name.Text = plr.DisplayName == plr.Name and plr.Name or (plr.DisplayName .. " (@" .. plr.Name .. ")")

                    e.dist.Visible = S.ESP.Distance
                    e.dist.Position = Vector2.new(x + w/2, y + h + 2)
                    e.dist.Color = S.ESP.DistanceColor
                    e.dist.Text = string.format("[%dm]", math.floor(dist3D))

                    if S.ESP.HealthBar then
                        local pct = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
                        e.hpBg.Visible = true; e.hpBg.Position = Vector2.new(x - 6, y); e.hpBg.Size = Vector2.new(3, h)
                        e.hp.Visible = true
                        e.hp.Position = Vector2.new(x - 6, y + h*(1-pct))
                        e.hp.Size = Vector2.new(3, h*pct)
                        e.hp.Color = Color3.fromHSV(pct * 0.33, 1, 1)
                    else
                        e.hp.Visible = false; e.hpBg.Visible = false
                    end

                    if S.ESP.Tracer then
                        local vs = Camera.ViewportSize
                        e.tracer.Visible = true
                        e.tracer.From = Vector2.new(vs.X/2, vs.Y)
                        e.tracer.To = Vector2.new(x + w/2, y + h)
                        e.tracer.Color = S.ESP.TracerColor
                    else
                        e.tracer.Visible = false
                    end

                    if S.ESP.Chams then
                        if not (e.chams and e.chams.Parent) then
                            e.chams = Instance.new("Highlight", char)
                            e.chams.Name = "IMP_Chams"
                            e.chams.Adornee = char
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

-- ========================== UI LIBRARY ========================
-- Modern custom UI built from Instances. Sidebar layout, dark theme,
-- animated toggles, blur background. No external dependencies.

local THEME = {
    bg       = Color3.fromRGB(13, 13, 18),
    panel    = Color3.fromRGB(20, 20, 28),
    card     = Color3.fromRGB(26, 26, 34),
    accent   = Color3.fromRGB(255, 60, 90),
    text     = Color3.fromRGB(240, 240, 240),
    subtext  = Color3.fromRGB(150, 150, 160),
    border   = Color3.fromRGB(40, 40, 50),
}

local function newInst(class, props)
    local i = Instance.new(class)
    for k, v in pairs(props or {}) do i[k] = v end
    return i
end

local function corner(parent, radius)
    return newInst("UICorner", {CornerRadius = UDim.new(0, radius or 6), Parent = parent})
end

local function stroke(parent, color, thickness)
    return newInst("UIStroke", {Color = color or THEME.border, Thickness = thickness or 1, Parent = parent})
end

local function padding(parent, p)
    return newInst("UIPadding", {
        PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p),
        PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p),
        Parent = parent
    })
end

-- BLUR
local blur = newInst("BlurEffect", {Size = 0, Parent = Lighting, Name = "IMP_BLUR"})

-- ROOT GUI
local ScreenGui = newInst("ScreenGui", {
    Name = "IMP_Combat", ResetOnSpawn = false, IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Parent = (gethui and gethui()) or CoreGui
})

-- Main window
local Window = newInst("Frame", {
    Size = UDim2.new(0, 640, 0, 440),
    Position = UDim2.new(0.5, -320, 0.5, -220),
    BackgroundColor3 = THEME.bg,
    BorderSizePixel = 0, Parent = ScreenGui, ZIndex = 5,
    Active = true, Draggable = true,
})
corner(Window, 10)
stroke(Window, THEME.border, 1)

-- Title bar
local TitleBar = newInst("Frame", {
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundColor3 = THEME.panel,
    BorderSizePixel = 0, Parent = Window, ZIndex = 6,
})
corner(TitleBar, 10)

newInst("Frame", {  -- mask the bottom rounded corners of title
    Position = UDim2.new(0, 0, 1, -10), Size = UDim2.new(1, 0, 0, 10),
    BackgroundColor3 = THEME.panel, BorderSizePixel = 0, Parent = TitleBar, ZIndex = 6,
})

newInst("TextLabel", {
    Position = UDim2.new(0, 16, 0, 0), Size = UDim2.new(0, 200, 1, 0),
    BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
    Text = "IMP // Combat", TextSize = 16, TextColor3 = THEME.text,
    TextXAlignment = Enum.TextXAlignment.Left, Parent = TitleBar, ZIndex = 7,
})

newInst("TextLabel", {
    Position = UDim2.new(0, 16, 0, 18), Size = UDim2.new(0, 200, 0, 14),
    BackgroundTransparency = 1, Font = Enum.Font.Gotham,
    Text = "Insert = toggle UI", TextSize = 11, TextColor3 = THEME.subtext,
    TextXAlignment = Enum.TextXAlignment.Left, Parent = TitleBar, ZIndex = 7,
})

-- Sidebar
local Sidebar = newInst("Frame", {
    Position = UDim2.new(0, 0, 0, 40), Size = UDim2.new(0, 140, 1, -40),
    BackgroundColor3 = THEME.panel, BorderSizePixel = 0, Parent = Window, ZIndex = 6,
})
newInst("UIListLayout", {
    Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    Parent = Sidebar,
})
padding(Sidebar, 12)

-- Content area
local Content = newInst("Frame", {
    Position = UDim2.new(0, 140, 0, 40), Size = UDim2.new(1, -140, 1, -40),
    BackgroundColor3 = THEME.bg, BorderSizePixel = 0, Parent = Window, ZIndex = 6,
})

-- Tab system
local Tabs, ActiveTab = {}, nil

local function selectTab(name)
    for n, t in pairs(Tabs) do
        t.page.Visible = (n == name)
        t.btn.BackgroundColor3 = (n == name) and THEME.accent or THEME.card
        t.btn.TextColor3 = (n == name) and Color3.new(1,1,1) or THEME.text
    end
    ActiveTab = name
end

local function makeTab(name)
    local btn = newInst("TextButton", {
        Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = THEME.card,
        BorderSizePixel = 0, Font = Enum.Font.GothamMedium, Text = name,
        TextSize = 13, TextColor3 = THEME.text, AutoButtonColor = false,
        Parent = Sidebar, ZIndex = 7,
    })
    corner(btn, 6)

    local page = newInst("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
        BorderSizePixel = 0, ScrollBarThickness = 4,
        ScrollBarImageColor3 = THEME.accent,
        CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = Content, Visible = false, ZIndex = 7,
    })
    newInst("UIListLayout", {Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page})
    padding(page, 16)

    btn.MouseButton1Click:Connect(function() selectTab(name) end)
    Tabs[name] = {btn = btn, page = page}
    return page
end

-- COMPONENT FACTORIES

local function section(parent, title)
    local sec = newInst("Frame", {
        Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1,
        Parent = parent, ZIndex = 7,
    })
    newInst("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, Text = title:upper(),
        TextSize = 11, TextColor3 = THEME.accent,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = sec, ZIndex = 8,
    })
end

local function makeToggle(parent, label, default, callback)
    local row = newInst("Frame", {
        Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = THEME.card,
        BorderSizePixel = 0, Parent = parent, ZIndex = 7,
    })
    corner(row, 6); stroke(row)

    newInst("TextLabel", {
        Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -60, 1, 0),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = label,
        TextSize = 13, TextColor3 = THEME.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row, ZIndex = 8,
    })

    local switch = newInst("Frame", {
        Position = UDim2.new(1, -44, 0.5, -10), Size = UDim2.new(0, 32, 0, 20),
        BackgroundColor3 = default and THEME.accent or Color3.fromRGB(60, 60, 70),
        BorderSizePixel = 0, Parent = row, ZIndex = 8,
    })
    corner(switch, 10)

    local knob = newInst("Frame", {
        Position = default and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
        Size = UDim2.new(0, 16, 0, 16),
        BackgroundColor3 = Color3.new(1,1,1), BorderSizePixel = 0,
        Parent = switch, ZIndex = 9,
    })
    corner(knob, 8)

    local state = default
    local clickArea = newInst("TextButton", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
        Text = "", Parent = row, ZIndex = 10, AutoButtonColor = false,
    })
    clickArea.MouseButton1Click:Connect(function()
        state = not state
        TweenService:Create(switch, TweenInfo.new(0.15), {
            BackgroundColor3 = state and THEME.accent or Color3.fromRGB(60, 60, 70)
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
        }):Play()
        callback(state)
    end)
    return clickArea
end

local function makeSlider(parent, label, min, max, default, decimals, callback)
    local row = newInst("Frame", {
        Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = THEME.card,
        BorderSizePixel = 0, Parent = parent, ZIndex = 7,
    })
    corner(row, 6); stroke(row)

    local lbl = newInst("TextLabel", {
        Position = UDim2.new(0, 12, 0, 8), Size = UDim2.new(1, -24, 0, 16),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham,
        Text = label .. ": " .. tostring(default), TextSize = 12, TextColor3 = THEME.text,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = row, ZIndex = 8,
    })

    local bar = newInst("Frame", {
        Position = UDim2.new(0, 12, 1, -18), Size = UDim2.new(1, -24, 0, 6),
        BackgroundColor3 = Color3.fromRGB(40, 40, 50), BorderSizePixel = 0,
        Parent = row, ZIndex = 8,
    })
    corner(bar, 3)

    local fill = newInst("Frame", {
        Size = UDim2.new((default - min) / (max - min), 0, 1, 0),
        BackgroundColor3 = THEME.accent, BorderSizePixel = 0, Parent = bar, ZIndex = 9,
    })
    corner(fill, 3)

    local dragging = false
    local function update(input)
        local x = input.Position.X
        local pct = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local raw = min + (max - min) * pct
        local val = decimals and math.floor(raw * (10 ^ decimals) + 0.5) / (10 ^ decimals) or math.floor(raw + 0.5)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        lbl.Text = label .. ": " .. tostring(val)
        callback(val)
    end

    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true; update(i)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then update(i) end
    end)
end

-- ========================== BUILD UI ==========================

-- AIMBOT TAB
local pageAim = makeTab("Aimbot")
section(pageAim, "Core")
makeToggle(pageAim, "Enabled", S.Aimbot.Enabled, function(v) S.Aimbot.Enabled = v end)
makeToggle(pageAim, "Show FOV Circle", S.Aimbot.ShowFOV, function(v) S.Aimbot.ShowFOV = v end)
makeSlider(pageAim, "FOV (px)", 30, 500, S.Aimbot.FOV, nil, function(v) S.Aimbot.FOV = v end)
makeSlider(pageAim, "Smoothness", 1, 20, S.Aimbot.Smoothness, nil, function(v) S.Aimbot.Smoothness = v end)
section(pageAim, "Info")
local info = newInst("Frame", {Size = UDim2.new(1, 0, 0, 60), BackgroundColor3 = THEME.card, BorderSizePixel = 0, Parent = pageAim, ZIndex = 7})
corner(info, 6); stroke(info)
newInst("TextLabel", {
    Size = UDim2.new(1, -24, 1, 0), Position = UDim2.new(0, 12, 0, 0),
    BackgroundTransparency = 1, Font = Enum.Font.Gotham,
    Text = "Hold RIGHT-CLICK to aim.\nLower smoothness = harder lock.",
    TextSize = 12, TextColor3 = THEME.subtext, TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
    Parent = info, ZIndex = 8,
})

-- ESP TAB
local pageESP = makeTab("ESP")
section(pageESP, "Core")
makeToggle(pageESP, "Enabled", S.ESP.Enabled, function(v) S.ESP.Enabled = v end)
makeToggle(pageESP, "Team Check", S.ESP.TeamCheck, function(v) S.ESP.TeamCheck = v end)
makeSlider(pageESP, "Max Distance", 100, 10000, S.ESP.MaxDistance, nil, function(v) S.ESP.MaxDistance = v end)
section(pageESP, "Elements")
makeToggle(pageESP, "Box", S.ESP.Box, function(v) S.ESP.Box = v end)
makeToggle(pageESP, "Name", S.ESP.Name, function(v) S.ESP.Name = v end)
makeToggle(pageESP, "Distance", S.ESP.Distance, function(v) S.ESP.Distance = v end)
makeToggle(pageESP, "Health Bar (Reactive)", S.ESP.HealthBar, function(v) S.ESP.HealthBar = v end)
makeToggle(pageESP, "Tracer", S.ESP.Tracer, function(v) S.ESP.Tracer = v end)
makeToggle(pageESP, "Chams (Through Walls)", S.ESP.Chams, function(v) S.ESP.Chams = v end)

-- SETTINGS TAB
local pageSet = makeTab("Settings")
section(pageSet, "About")
local about = newInst("Frame", {Size = UDim2.new(1, 0, 0, 80), BackgroundColor3 = THEME.card, BorderSizePixel = 0, Parent = pageSet, ZIndex = 7})
corner(about, 6); stroke(about)
newInst("TextLabel", {
    Size = UDim2.new(1, -24, 1, 0), Position = UDim2.new(0, 12, 0, 0),
    BackgroundTransparency = 1, Font = Enum.Font.Gotham,
    Text = "IMP // Combat\nAimbot + Drawing API ESP\nPress INSERT to toggle UI",
    TextSize = 12, TextColor3 = THEME.subtext, TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
    Parent = about, ZIndex = 8,
})

selectTab("Aimbot")

-- ========================== UI TOGGLE =========================
local function setUIVisible(visible)
    Window.Visible = visible
    TweenService:Create(blur, TweenInfo.new(0.2), {Size = visible and 18 or 0}):Play()
end
setUIVisible(true)

-- ========================== INPUT =============================
UserInputService.InputBegan:Connect(function(input, gpe)
    if input.KeyCode == Enum.KeyCode.Insert then
        setUIVisible(not Window.Visible)
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 and not gpe then
        HoldingAimKey = true
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        HoldingAimKey = false
    end
end)

-- ========================== MAIN LOOP =========================
RunService.RenderStepped:Connect(function()
    -- FOV Circle
    FOVCircle.Position = UserInputService:GetMouseLocation()
    FOVCircle.Radius = S.Aimbot.FOV
    FOVCircle.Visible = S.Aimbot.Enabled and S.Aimbot.ShowFOV

    -- Aimbot
    if S.Aimbot.Enabled and HoldingAimKey then
        aimAt(getClosestPlayer())
    end

    -- ESP
    updateESP()
end)

print("[IMP] Loaded — INSERT toggles menu, RIGHT-CLICK aims.")
