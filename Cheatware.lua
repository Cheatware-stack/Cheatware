--[[
    Cheatware.lua
    Loadstring-ready cheat panel for Roblox
    Features: ESP | Aimbot | Silent Aim
]]

-- [[ UI Setup ]]
local UI = {
    Toggles = {},
    Sliders = {},
    Dropdowns = {},
    Colors = {
        Background = Color3.fromRGB(18, 18, 22),
        Surface = Color3.fromRGB(24, 24, 30),
        Element = Color3.fromRGB(30, 30, 38),
        Accent = Color3.fromRGB(88, 101, 242),
        AccentDark = Color3.fromRGB(66, 78, 207),
        Text = Color3.fromRGB(220, 220, 230),
        TextDim = Color3.fromRGB(140, 140, 150),
        Border = Color3.fromRGB(40, 40, 48),
        Success = Color3.fromRGB(80, 200, 120),
        Danger = Color3.fromRGB(220, 80, 80),
    }
}

-- [[ Services ]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Camera = Workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- [[ Config ]]
local Config = {
    ESP = {
        Enabled = false,
        Box = true,
        BoxColor = Color3.fromRGB(255, 255, 255),
        BoxOutline = true,
        Tracer = false,
        TracerOrigin = "Bottom", -- Bottom, Mouse, Crosshair
        TracerColor = Color3.fromRGB(255, 255, 255),
        Name = true,
        Health = true,
        Distance = true,
        TeamCheck = true,
        MaxDistance = 5000,
        FontSize = 13,
    },
    Aimbot = {
        Enabled = false,
        Smoothness = 0.6,
        FOV = 90,
        HitPart = "Head",
        TeamCheck = true,
        VisibleCheck = false,
        WallCheck = false,
        Keybind = Enum.UserInputType.MouseButton2,
        Prediction = 0.165,
    },
    SilentAim = {
        Enabled = false,
        HitChance = 100,
        HitPart = "Head",
        TeamCheck = true,
        VisibleCheck = false,
        WallCheck = false,
        FOV = 200,
        Prediction = 0.135,
    },
    World = {
        FOVCircle = false,
        FOVCircleColor = Color3.fromRGB(255, 255, 255),
        FOVCircleTransparency = 0.7,
        Crosshair = false,
    }
}

-- [[ Utility Functions ]]
local Utility = {}

function Utility:Round(num, decimals)
    return math.floor(num * (10 ^ decimals) + 0.5) / (10 ^ decimals)
end

function Utility:GetCharacter(player)
    return player.Character
end

function Utility:GetRootPart(character)
    return character and character:FindFirstChild("HumanoidRootPart")
end

function Utility:GetHumanoid(character)
    return character and character:FindFirstChildOfClass("Humanoid")
end

function Utility:IsAlive(player)
    local char = self:GetCharacter(player)
    local hum = self:GetHumanoid(char)
    return char and hum and hum.Health > 0
end

function Utility:IsTeamMate(player)
    if not LocalPlayer or not player then return false end
    if LocalPlayer.Team == nil or player.Team == nil then return false end
    return LocalPlayer.Team == player.Team
end

function Utility:GetClosestPart(character, partName)
    return character and (character:FindFirstChild(partName) or character:FindFirstChild("Head"))
end

function Utility:IsVisible(part)
    if not part then return false end
    local origin = Camera.CFrame.Position
    local _, hit = Workspace:FindPartOnRay(
        Ray.new(origin, (part.Position - origin).Unit * 1000),
        LocalPlayer.Character
    )
    return hit and hit:IsDescendantOf(part.Parent)
end

function Utility:GetDistanceFromCharacter(character)
    local root = self:GetRootPart(LocalPlayer.Character)
    local targetRoot = self:GetRootPart(character)
    if not root or not targetRoot then return math.huge end
    return (root.Position - targetRoot.Position).Magnitude
end

function Utility:WorldToScreen(position)
    local point, onScreen = Camera:WorldToScreenPoint(position)
    return Vector2.new(point.X, point.Y), onScreen
end

-- [[ ESP Drawing ]]
local Drawings = {}

function Drawings:New(type, props)
    local d = Drawing.new(type)
    for k, v in pairs(props or {}) do
        d[k] = v
    end
    return d
end

function Drawings:Clear()
    for _, v in pairs(self) do
        if type(v) == "table" and v.Remove then
            v:Remove()
        end
    end
end

local ESPCache = {}

function ESPCache:Create(player)
    if self[player] then return end
    local store = {
        BoxOutline = Drawings:New("Square", {Visible = false, Transparency = 1, Thickness = 3, Color = Color3.new(0, 0, 0)}),
        Box = Drawings:New("Square", {Visible = false, Transparency = 1, Thickness = 1, Color = Color3.new(255, 255, 255)}),
        Tracer = Drawings:New("Line", {Visible = false, Transparency = 1, Thickness = 1, Color = Color3.new(255, 255, 255)}),
        Name = Drawings:New("Text", {Visible = false, Transparency = 1, Size = 13, Center = true, Outline = true, Color = Color3.new(255, 255, 255)}),
        HealthText = Drawings:New("Text", {Visible = false, Transparency = 1, Size = 13, Center = true, Outline = true, Color = Color3.new(255, 255, 255)}),
        DistanceText = Drawings:New("Text", {Visible = false, Transparency = 1, Size = 12, Center = true, Outline = true, Color = Color3.new(180, 180, 180)}),
        HealthBarOutline = Drawings:New("Square", {Visible = false, Transparency = 1, Thickness = 1, Color = Color3.new(0, 0, 0)}),
        HealthBar = Drawings:New("Square", {Visible = false, Transparency = 1, Thickness = 1, Color = Color3.new(80, 200, 120)}),
    }
    self[player] = store
end

function ESPCache:Remove(player)
    if self[player] then
        for _, v in pairs(self[player]) do
            v:Remove()
        end
        self[player] = nil
    end
end

-- [[ Aimbot Logic ]]
local Aimbot = {}

function Aimbot:GetClosestTarget()
    local closest, closestAngle = nil, Config.Aimbot.FOV
    local origin = Camera.CFrame.Position
    local direction = (Mouse.Hit.Position - origin).Unit

    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if not Utility:IsAlive(player) then continue end
        if Config.Aimbot.TeamCheck and Utility:IsTeamMate(player) then continue end

        local char = Utility:GetCharacter(player)
        local part = Utility:GetClosestPart(char, Config.Aimbot.HitPart)
        if not part then continue end

        local dist = Utility:GetDistanceFromCharacter(char)
        if dist > Config.ESP.MaxDistance then continue end

        if Config.Aimbot.VisibleCheck and not Utility:IsVisible(part) then continue end

        local toTarget = (part.Position - origin).Unit
        local angle = math.deg(math.acos(math.clamp(direction:Dot(toTarget), -1, 1)))

        if angle < closestAngle then
            closestAngle = angle
            closest = player
        end
    end

    return closest
end

function Aimbot:GetPredictedPosition(part)
    if not part then return nil end
    local vel = part.Velocity or Vector3.new()
    return part.Position + (vel * Config.Aimbot.Prediction)
end

function Aimbot:Execute()
    if not Config.Aimbot.Enabled then return end
    if not UserInputService:IsMouseButtonPressed(Config.Aimbot.Keybind) then return end

    local target = self:GetClosestTarget()
    if not target then return end

    local char = Utility:GetCharacter(target)
    local part = Utility:GetClosestPart(char, Config.Aimbot.HitPart)
    if not part then return end

    local pos = self:GetPredictedPosition(part)
    if not pos then return end

    local screenPos = Camera:WorldToScreenPoint(pos)
    local smooth = Config.Aimbot.Smoothness

    local delta = Vector2.new(screenPos.X - Mouse.X, screenPos.Y - Mouse.Y) * smooth
    mousemoverel(delta.X, delta.Y)
end

-- [[ Silent Aim Logic ]]
local SilentAim = {}

function SilentAim:FindBestTarget()
    local best, bestFOV = nil, Config.SilentAim.FOV
    local origin = Camera.CFrame.Position

    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if not Utility:IsAlive(player) then continue end
        if Config.SilentAim.TeamCheck and Utility:IsTeamMate(player) then continue end

        local char = Utility:GetCharacter(player)
        local part = Utility:GetClosestPart(char, Config.SilentAim.HitPart)
        if not part then continue end

        local dist = Utility:GetDistanceFromCharacter(char)
        if dist > Config.ESP.MaxDistance then continue end

        if Config.SilentAim.VisibleCheck and not Utility:IsVisible(part) then continue end

        local screenPos, onScreen = Camera:WorldToScreenPoint(part.Position)
        if not onScreen then continue end

        local mousePos = Vector2.new(Mouse.X, Mouse.Y)
        local fov = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude

        if fov < bestFOV then
            bestFOV = fov
            best = player
        end
    end

    return best
end

function SilentAim:GetTargetPart(player)
    if not player then return nil end
    local char = Utility:GetCharacter(player)
    local part = Utility:GetClosestPart(char, Config.SilentAim.HitPart)
    return part
end

function SilentAim:ShouldSilent()
    return Config.SilentAim.Enabled
end

-- [[ UI Builder ]]
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "Cheatware"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local function CreateUI()
    -- Main Frame
    local Main = Instance.new("Frame")
    Main.Name = "Main"
    Main.Size = UDim2.new(0, 720, 0, 480)
    Main.Position = UDim2.new(0.5, -360, 0.5, -240)
    Main.BackgroundColor3 = UI.Colors.Background
    Main.BorderColor3 = UI.Colors.Border
    Main.BorderSizePixel = 1
    Main.Active = true
    Main.Draggable = true
    Main.ClipsDescendants = true
    Main.Visible = false
    Main.Parent = ScreenGui

    -- Drop Shadow
    local Shadow = Instance.new("ImageLabel")
    Shadow.Name = "Shadow"
    Shadow.Size = UDim2.new(1, 60, 1, 60)
    Shadow.Position = UDim2.new(0, -30, 0, -30)
    Shadow.BackgroundTransparency = 1
    Shadow.Image = "rbxassetid://1316045217"
    Shadow.ImageColor3 = Color3.new(0, 0, 0)
    Shadow.ImageTransparency = 0.6
    Shadow.ScaleType = Enum.ScaleType.Slice
    Shadow.SliceCenter = Rect.new(10, 10, 118, 118)
    Shadow.Parent = Main

    -- Header
    local Header = Instance.new("Frame")
    Header.Name = "Header"
    Header.Size = UDim2.new(1, 0, 0, 42)
    Header.BackgroundColor3 = UI.Colors.Surface
    Header.BorderSizePixel = 0
    Header.Parent = Main

    local HeaderAccent = Instance.new("Frame")
    HeaderAccent.Name = "HeaderAccent"
    HeaderAccent.Size = UDim2.new(1, 0, 0, 2)
    HeaderAccent.Position = UDim2.new(0, 0, 1, -2)
    HeaderAccent.BackgroundColor3 = UI.Colors.Accent
    HeaderAccent.BorderSizePixel = 0
    HeaderAccent.Parent = Header

    local Title = Instance.new("TextLabel")
    Title.Name = "Title"
    Title.Size = UDim2.new(0, 200, 1, 0)
    Title.Position = UDim2.new(0, 14, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Text = "Cheatware"
    Title.TextColor3 = UI.Colors.Text
    Title.TextSize = 18
    Title.Font = Enum.Font.GothamBold
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Parent = Header

    local Subtitle = Instance.new("TextLabel")
    Subtitle.Name = "Subtitle"
    Subtitle.Size = UDim2.new(0, 200, 1, 0)
    Subtitle.Position = UDim2.new(0, 120, 0, 0)
    Subtitle.BackgroundTransparency = 1
    Subtitle.Text = "v1.0.0"
    Subtitle.TextColor3 = UI.Colors.Accent
    Subtitle.TextSize = 12
    Subtitle.Font = Enum.Font.GothamMedium
    Subtitle.TextXAlignment = Enum.TextXAlignment.Left
    Subtitle.Parent = Header

    -- Toggle Button
    local ToggleBtn = Instance.new("TextButton")
    ToggleBtn.Name = "ToggleBtn"
    ToggleBtn.Size = UDim2.new(0, 28, 0, 28)
    ToggleBtn.Position = UDim2.new(1, -38, 0, 7)
    ToggleBtn.BackgroundColor3 = UI.Colors.Element
    ToggleBtn.BorderColor3 = UI.Colors.Border
    ToggleBtn.Text = ""
    ToggleBtn.Parent = Header

    local ToggleIcon = Instance.new("TextLabel")
    ToggleIcon.Name = "ToggleIcon"
    ToggleIcon.Size = UDim2.new(1, 0, 1, 0)
    ToggleIcon.BackgroundTransparency = 1
    ToggleIcon.Text = "—"
    ToggleIcon.TextColor3 = UI.Colors.TextDim
    ToggleIcon.TextSize = 18
    ToggleIcon.Font = Enum.Font.GothamBold
    ToggleIcon.Parent = ToggleBtn

    -- Tab Bar
    local TabBar = Instance.new("Frame")
    TabBar.Name = "TabBar"
    TabBar.Size = UDim2.new(0, 160, 1, -42)
    TabBar.Position = UDim2.new(0, 0, 0, 42)
    TabBar.BackgroundColor3 = UI.Colors.Surface
    TabBar.BorderSizePixel = 0
    TabBar.Parent = Main

    local TabBarAccent = Instance.new("Frame")
    TabBarAccent.Name = "TabBarAccent"
    TabBarAccent.Size = UDim2.new(0, 1, 1, 0)
    TabBarAccent.Position = UDim2.new(1, -1, 0, 0)
    TabBarAccent.BackgroundColor3 = UI.Colors.Border
    TabBarAccent.BorderSizePixel = 0
    TabBarAccent.Parent = TabBar

    -- Content Area
    local ContentArea = Instance.new("Frame")
    ContentArea.Name = "ContentArea"
    ContentArea.Size = UDim2.new(1, -160, 1, -42)
    ContentArea.Position = UDim2.new(0, 160, 0, 42)
    ContentArea.BackgroundColor3 = UI.Colors.Background
    ContentArea.BorderSizePixel = 0
    ContentArea.Parent = Main

    -- Tabs
    local Tabs = {
        {Name = "ESP", Icon = "◎", Color = UI.Colors.Accent},
        {Name = "Aimbot", Icon = "●", Color = UI.Colors.Accent},
        {Name = "Silent Aim", Icon = "◉", Color = UI.Colors.Accent},
    }

    local TabButtons = {}
    local TabContents = {}

    for i, tabData in ipairs(Tabs) do
        -- Tab Button
        local btn = Instance.new("TextButton")
        btn.Name = tabData.Name .. "Tab"
        btn.Size = UDim2.new(1, 0, 0, 40)
        btn.Position = UDim2.new(0, 0, 0, (i - 1) * 42)
        btn.BackgroundColor3 = UI.Colors.Surface
        btn.BorderSizePixel = 0
        btn.Text = ""
        btn.Parent = TabBar

        local btnIcon = Instance.new("TextLabel")
        btnIcon.Name = "Icon"
        btnIcon.Size = UDim2.new(0, 20, 1, 0)
        btnIcon.Position = UDim2.new(0, 14, 0, 0)
        btnIcon.BackgroundTransparency = 1
        btnIcon.Text = tabData.Icon
        btnIcon.TextColor3 = UI.Colors.TextDim
        btnIcon.TextSize = 16
        btnIcon.Font = Enum.Font.GothamBold
        btnIcon.Parent = btn

        local btnLabel = Instance.new("TextLabel")
        btnLabel.Name = "Label"
        btnLabel.Size = UDim2.new(1, -48, 1, 0)
        btnLabel.Position = UDim2.new(0, 42, 0, 0)
        btnLabel.BackgroundTransparency = 1
        btnLabel.Text = tabData.Name
        btnLabel.TextColor3 = UI.Colors.TextDim
        btnLabel.TextSize = 13
        btnLabel.Font = Enum.Font.GothamMedium
        btnLabel.TextXAlignment = Enum.TextXAlignment.Left
        btnLabel.Parent = btn

        local btnIndicator = Instance.new("Frame")
        btnIndicator.Name = "Indicator"
        btnIndicator.Size = UDim2.new(0, 3, 1, 0)
        btnIndicator.Position = UDim2.new(0, 0, 0, 0)
        btnIndicator.BackgroundColor3 = tabData.Color
        btnIndicator.BorderSizePixel = 0
        btnIndicator.Visible = false
        btnIndicator.Parent = btn

        -- Content Frame
        local content = Instance.new("ScrollingFrame")
        content.Name = tabData.Name .. "Content"
        content.Size = UDim2.new(1, -20, 1, -20)
        content.Position = UDim2.new(0, 10, 0, 10)
        content.BackgroundTransparency = 1
        content.BorderSizePixel = 0
        content.ScrollBarThickness = 3
        content.ScrollBarImageColor3 = UI.Colors.Accent
        content.CanvasSize = UDim2.new(0, 0, 0, 0)
        content.Visible = false
        content.Parent = ContentArea

        TabButtons[i] = btn
        TabContents[i] = content

        -- Button Hover/Select
        local isSelected = (i == 1)
        if isSelected then
            btnIndicator.Visible = true
            btnLabel.TextColor3 = UI.Colors.Text
            btnIcon.TextColor3 = UI.Colors.Accent
            content.Visible = true
        end

        btn.MouseButton1Click:Connect(function()
            for j, otherBtn in ipairs(TabButtons) do
                local ind = otherBtn:FindFirstChild("Indicator")
                local lbl = otherBtn:FindFirstChild("Label")
                local icn = otherBtn:FindFirstChild("Icon")
                if ind then ind.Visible = false end
                if lbl then lbl.TextColor3 = UI.Colors.TextDim end
                if icn then icn.TextColor3 = UI.Colors.TextDim end
            end
            btnIndicator.Visible = true
            btnLabel.TextColor3 = UI.Colors.Text
            btnIcon.TextColor3 = UI.Colors.Accent

            for j, otherContent in ipairs(TabContents) do
                otherContent.Visible = (j == i)
            end
        end)
    end

    -- [[ UI Elements Factory ]]
    local yOffset = 0
    local tabContents = TabContents

    function CreateSection(parent, title)
        local section = Instance.new("Frame")
        section.Name = title .. "Section"
        section.Size = UDim2.new(1, 0, 0, 30)
        section.Position = UDim2.new(0, 0, 0, yOffset)
        section.BackgroundTransparency = 1
        section.BorderSizePixel = 0
        section.Parent = parent

        local line = Instance.new("Frame")
        line.Name = "Line"
        line.Size = UDim2.new(0, 24, 0, 2)
        line.Position = UDim2.new(0, 0, 0.5, -1)
        line.BackgroundColor3 = UI.Colors.Accent
        line.BorderSizePixel = 0
        line.Parent = section

        local label = Instance.new("TextLabel")
        label.Name = "Label"
        label.Size = UDim2.new(1, -36, 1, 0)
        label.Position = UDim2.new(0, 32, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = title
        label.TextColor3 = UI.Colors.Text
        label.TextSize = 13
        label.Font = Enum.Font.GothamBold
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = section

        yOffset = yOffset + 38
        return section
    end

    function CreateToggle(parent, configPath, label, desc)
        local toggle = Instance.new("TextButton")
        toggle.Name = label .. "Toggle"
        toggle.Size = UDim2.new(1, 0, 0, 36)
        toggle.Position = UDim2.new(0, 0, 0, yOffset)
        toggle.BackgroundColor3 = UI.Colors.Element
        toggle.BorderColor3 = UI.Colors.Border
        toggle.BorderSizePixel = 1
        toggle.Text = ""
        toggle.Parent = parent

        local toggleLabel = Instance.new("TextLabel")
        toggleLabel.Name = "Label"
        toggleLabel.Size = UDim2.new(1, -56, 1, 0)
        toggleLabel.Position = UDim2.new(0, 12, 0, 0)
        toggleLabel.BackgroundTransparency = 1
        toggleLabel.Text = label
        toggleLabel.TextColor3 = UI.Colors.Text
        toggleLabel.TextSize = 13
        toggleLabel.Font = Enum.Font.GothamMedium
        toggleLabel.TextXAlignment = Enum.TextXAlignment.Left
        toggleLabel.Parent = toggle

        if desc then
            local descLabel = Instance.new("TextLabel")
            descLabel.Name = "Desc"
            descLabel.Size = UDim2.new(1, -56, 0, 14)
            descLabel.Position = UDim2.new(0, 12, 0, 18)
            descLabel.BackgroundTransparency = 1
            descLabel.Text = desc
            descLabel.TextColor3 = UI.Colors.TextDim
            descLabel.TextSize = 11
            descLabel.Font = Enum.Font.Gotham
            descLabel.TextXAlignment = Enum.TextXAlignment.Left
            descLabel.Parent = toggle
            toggle.Size = UDim2.new(1, 0, 0, 36)
        end

        local toggleBg = Instance.new("Frame")
        toggleBg.Name = "ToggleBg"
        toggleBg.Size = UDim2.new(0, 34, 0, 18)
        toggleBg.Position = UDim2.new(1, -46, 0, 9)
        toggleBg.BackgroundColor3 = UI.Colors.Background
        toggleBg.BorderColor3 = UI.Colors.Border
        toggleBg.BorderSizePixel = 1
        toggleBg.Parent = toggle

        local toggleFill = Instance.new("Frame")
        toggleFill.Name = "ToggleFill"
        toggleFill.Size = UDim2.new(0, 0, 1, 0)
        toggleFill.BackgroundColor3 = UI.Colors.Accent
        toggleFill.BorderSizePixel = 0
        toggleFill.Parent = toggleBg

        local toggleCircle = Instance.new("Frame")
        toggleCircle.Name = "ToggleCircle"
        toggleCircle.Size = UDim2.new(0, 14, 0, 14)
        toggleCircle.Position = UDim2.new(0, 2, 0, 2)
        toggleCircle.BackgroundColor3 = UI.Colors.TextDim
        toggleCircle.BorderSizePixel = 0
        toggleCircle.Parent = toggleBg

        local keys = {}
            for part in configPath:gmatch("[%w_]+") do
                table.insert(keys, part)
            end
        local enabled = false

        local function updateVisuals()
            if enabled then
                toggleFill:TweenSize(UDim2.new(1, -2, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 0.2, true)
                toggleCircle:TweenPosition(UDim2.new(1, -16, 0, 2), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 0.2, true)
                toggleCircle.BackgroundColor3 = UI.Colors.Accent
                toggleFill.BackgroundColor3 = UI.Colors.Accent
            else
                toggleFill:TweenSize(UDim2.new(0, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 0.2, true)
                toggleCircle:TweenPosition(UDim2.new(0, 2, 0, 2), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 0.2, true)
                toggleCircle.BackgroundColor3 = UI.Colors.TextDim
                toggleFill.BackgroundColor3 = UI.Colors.Accent
            end
        end

        local function updateConfig()
            local obj = Config
            for i = 1, #keys - 1 do
                obj = obj[keys[i]]
            end
            obj[keys[#keys]] = enabled
        end

        toggle.MouseButton1Click:Connect(function()
            enabled = not enabled
            updateConfig()
            updateVisuals()
        end)

        yOffset = yOffset + 44
        return toggle
    end

    function CreateSlider(parent, configPath, label, min, max, decimals, suffix)
        local slider = Instance.new("Frame")
        slider.Name = label .. "Slider"
        slider.Size = UDim2.new(1, 0, 0, 50)
        slider.Position = UDim2.new(0, 0, 0, yOffset)
        slider.BackgroundColor3 = UI.Colors.Element
        slider.BorderColor3 = UI.Colors.Border
        slider.BorderSizePixel = 1
        slider.Parent = parent

        local sliderLabel = Instance.new("TextLabel")
        sliderLabel.Name = "Label"
        sliderLabel.Size = UDim2.new(1, -100, 1, 0)
        sliderLabel.Position = UDim2.new(0, 12, 0, 0)
        sliderLabel.BackgroundTransparency = 1
        sliderLabel.Text = label
        sliderLabel.TextColor3 = UI.Colors.Text
        sliderLabel.TextSize = 13
        sliderLabel.Font = Enum.Font.GothamMedium
        sliderLabel.TextXAlignment = Enum.TextXAlignment.Left
        sliderLabel.Parent = slider

        local valueLabel = Instance.new("TextLabel")
        valueLabel.Name = "Value"
        valueLabel.Size = UDim2.new(0, 50, 1, 0)
        valueLabel.Position = UDim2.new(1, -62, 0, 0)
        valueLabel.BackgroundTransparency = 1
        valueLabel.Text = ""
        valueLabel.TextColor3 = UI.Colors.Accent
        valueLabel.TextSize = 13
        valueLabel.Font = Enum.Font.GothamBold
        valueLabel.TextXAlignment = Enum.TextXAlignment.Right
        valueLabel.Parent = slider

        local barBg = Instance.new("Frame")
        barBg.Name = "BarBg"
        barBg.Size = UDim2.new(1, -24, 0, 4)
        barBg.Position = UDim2.new(0, 12, 0, 38)
        barBg.BackgroundColor3 = UI.Colors.Background
        barBg.BorderSizePixel = 0
        barBg.Parent = slider

        local barFill = Instance.new("Frame")
        barFill.Name = "BarFill"
        barFill.Size = UDim2.new(0, 0, 1, 0)
        barFill.BackgroundColor3 = UI.Colors.Accent
        barFill.BorderSizePixel = 0
        barFill.Parent = barBg

        local keys = {}
            for part in configPath:gmatch("[%w_]+") do
                table.insert(keys, part)
            end

        local obj = Config
        for i = 1, #keys - 1 do
            obj = obj[keys[i]]
        end
        local currentValue = obj[keys[#keys]]
        if currentValue == nil then currentValue = min end

        local function formatValue(v)
            local formatted = Utility:Round(v, decimals or 0)
            return tostring(formatted) .. (suffix or "")
        end

        local function setValue(v)
            v = math.clamp(v, min, max)
            currentValue = v
            local obj2 = Config
            for i = 1, #keys - 1 do
                obj2 = obj2[keys[i]]
            end
            obj2[keys[#keys]] = v
            valueLabel.Text = formatValue(v)
            local ratio = (v - min) / (max - min)
            barFill:TweenSize(UDim2.new(ratio, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 0.1, true)
        end

        setValue(currentValue)

        local dragging = false

        slider.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                local mousePos = UserInputService:GetMouseLocation()
                local absPos = barBg.AbsolutePosition
                local absSize = barBg.AbsoluteSize.X
                local ratio = math.clamp((mousePos.X - absPos.X) / absSize, 0, 1)
                setValue(min + (max - min) * ratio)
            end
        end)

        slider.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
            end
       	end)

        UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local mousePos = UserInputService:GetMouseLocation()
                local absPos = barBg.AbsolutePosition
                local absSize = barBg.AbsoluteSize.X
                local ratio = math.clamp((mousePos.X - absPos.X) / absSize, 0, 1)
                setValue(min + (max - min) * ratio)
            end
        end)

        yOffset = yOffset + 58
        return slider
    end

    function CreateKeybind(parent, configPath, label)
        local bind = Instance.new("TextButton")
        bind.Name = label .. "Keybind"
        bind.Size = UDim2.new(1, 0, 0, 36)
        bind.Position = UDim2.new(0, 0, 0, yOffset)
        bind.BackgroundColor3 = UI.Colors.Element
        bind.BorderColor3 = UI.Colors.Border
        bind.BorderSizePixel = 1
        bind.Text = ""
        bind.Parent = parent

        local bindLabel = Instance.new("TextLabel")
        bindLabel.Name = "Label"
        bindLabel.Size = UDim2.new(1, -56, 1, 0)
        bindLabel.Position = UDim2.new(0, 12, 0, 0)
        bindLabel.BackgroundTransparency = 1
        bindLabel.Text = label
        bindLabel.TextColor3 = UI.Colors.Text
        bindLabel.TextSize = 13
        bindLabel.Font = Enum.Font.GothamMedium
        bindLabel.TextXAlignment = Enum.TextXAlignment.Left
        bindLabel.Parent = bind

        local bindValue = Instance.new("TextLabel")
        bindValue.Name = "Value"
        bindValue.Size = UDim2.new(0, 60, 1, 0)
        bindValue.Position = UDim2.new(1, -70, 0, 0)
        bindValue.BackgroundTransparency = 1
        bindValue.Text = "RBUTTON"
        bindValue.TextColor3 = UI.Colors.Accent
        bindValue.TextSize = 12
        bindValue.Font = Enum.Font.GothamMedium
        bindValue.TextXAlignment = Enum.TextXAlignment.Right
        bindValue.Parent = bind

        local isBinding = false

        bind.MouseButton1Click:Connect(function()
            if isBinding then return end
            isBinding = true
            bindValue.Text = "..."
            bindValue.TextColor3 = UI.Colors.Danger

            local conn
            conn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
                if gameProcessed then return end
                if input.UserInputType == Enum.UserInputType.Keyboard then
                    bindValue.Text = input.KeyCode.Name
                    bindValue.TextColor3 = UI.Colors.Accent
                    local obj = Config
                    for part in configPath:gmatch("[%w_]+") do
                        obj = obj[part]
                    end
                    if Config[configPath:match("^[%w_]+")] then
                        local parts = {}
                        for part in configPath:gmatch("[%w_]+") do
                            table.insert(parts, part)
                        end
                        local target = Config
                        for i = 1, #parts - 1 do
                            target = target[parts[i]]
                        end
                        target[parts[#parts]] = input.KeyCode
                    end
                elseif input.UserInputType == Enum.UserInputType.MouseButton1 or
                       input.UserInputType == Enum.UserInputType.MouseButton2 or
                       input.UserInputType == Enum.UserInputType.MouseButton3 then
                    local names = {[0]="MB1", [1]="MB2", [2]="MB3"}
                    local idx = input.UserInputType == Enum.UserInputType.MouseButton2 and 1 or
                               input.UserInputType == Enum.UserInputType.MouseButton3 and 2 or 0
                    bindValue.Text = names[idx]
                    bindValue.TextColor3 = UI.Colors.Accent
                    local parts = {}
                    for part in configPath:gmatch("[%w_]+") do
                        table.insert(parts, part)
                    end
                    local target = Config
                    for i = 1, #parts - 1 do
                        target = target[parts[i]]
                    end
                    target[parts[#parts]] = input.UserInputType
                end
                isBinding = false
                conn:Disconnect()
            end)
        end)

        yOffset = yOffset + 44
        return bind
    end

    function CreateDropdown(parent, configPath, label, options)
        local dropdown = Instance.new("Frame")
        dropdown.Name = label .. "Dropdown"
        dropdown.Size = UDim2.new(1, 0, 0, 58)
        dropdown.Position = UDim2.new(0, 0, 0, yOffset)
        dropdown.BackgroundColor3 = UI.Colors.Element
        dropdown.BorderColor3 = UI.Colors.Border
        dropdown.BorderSizePixel = 1
        dropdown.Parent = parent

        local ddLabel = Instance.new("TextLabel")
        ddLabel.Name = "Label"
        ddLabel.Size = UDim2.new(1, -24, 0, 20)
        ddLabel.Position = UDim2.new(0, 12, 0, 6)
        ddLabel.BackgroundTransparency = 1
        ddLabel.Text = label
        ddLabel.TextColor3 = UI.Colors.Text
        ddLabel.TextSize = 13
        ddLabel.Font = Enum.Font.GothamMedium
        ddLabel.TextXAlignment = Enum.TextXAlignment.Left
        ddLabel.Parent = dropdown

        local ddButton = Instance.new("TextButton")
        ddButton.Name = "DropdownBtn"
        ddButton.Size = UDim2.new(1, -24, 0, 26)
        ddButton.Position = UDim2.new(0, 12, 0, 28)
        ddButton.BackgroundColor3 = UI.Colors.Background
        ddButton.BorderColor3 = UI.Colors.Border
        ddButton.BorderSizePixel = 1
        ddButton.Text = ""
        ddButton.Parent = dropdown

        local ddValue = Instance.new("TextLabel")
        ddValue.Name = "Value"
        ddValue.Size = UDim2.new(1, -12, 1, 0)
        ddValue.Position = UDim2.new(0, 10, 0, 0)
        ddValue.BackgroundTransparency = 1
        ddValue.Text = options[1] or "None"
        ddValue.TextColor3 = UI.Colors.Accent
        ddValue.TextSize = 12
        ddValue.Font = Enum.Font.GothamMedium
        ddValue.TextXAlignment = Enum.TextXAlignment.Left
        ddValue.Parent = ddButton

        local keys = {}
        for part in configPath:gmatch("[%w_]+") do
            table.insert(keys, part)
        end

        local ddOpen = false
        local ddList = Instance.new("Frame")
        ddList.Name = "DropdownList"
        ddList.Size = UDim2.new(1, -24, 0, 0)
        ddList.Position = UDim2.new(0, 12, 0, 56)
        ddList.BackgroundColor3 = UI.Colors.Surface
        ddList.BorderColor3 = UI.Colors.Border
        ddList.BorderSizePixel = 1
        ddList.Visible = false
        ddList.Parent = dropdown

        local ddListLayout = Instance.new("UIListLayout")
        ddListLayout.Parent = ddList

        for _, opt in ipairs(options) do
            local optBtn = Instance.new("TextButton")
            optBtn.Name = opt
            optBtn.Size = UDim2.new(1, 0, 0, 26)
            optBtn.BackgroundColor3 = UI.Colors.Surface
            optBtn.BorderSizePixel = 0
            optBtn.Text = "  " .. opt
            optBtn.TextColor3 = UI.Colors.Text
            optBtn.TextSize = 12
            optBtn.Font = Enum.Font.GothamMedium
            optBtn.TextXAlignment = Enum.TextXAlignment.Left
            optBtn.Parent = ddList

            optBtn.MouseEnter:Connect(function()
                optBtn.BackgroundColor3 = UI.Colors.Element
            end)
            optBtn.MouseLeave:Connect(function()
                optBtn.BackgroundColor3 = UI.Colors.Surface
            end)

            optBtn.MouseButton1Click:Connect(function()
                ddValue.Text = opt
                local obj = Config
                for i = 1, #keys - 1 do
                    obj = obj[keys[i]]
                end
                obj[keys[#keys]] = opt
                ddOpen = false
                ddList.Visible = false
                dropdown.Size = UDim2.new(1, 0, 0, 58)
            end)
        end

        ddButton.MouseButton1Click:Connect(function()
            ddOpen = not ddOpen
            ddList.Visible = ddOpen
            local count = #options
            local height = math.min(count, 5) * 26
            dropdown.Size = ddOpen and UDim2.new(1, 0, 0, 64 + height) or UDim2.new(1, 0, 0, 58)
            ddList.Size = UDim2.new(1, -24, 0, height)
        end)

        yOffset = yOffset + 66
        return dropdown
    end

    function CreateButton(parent, label, callback)
        local btn = Instance.new("TextButton")
        btn.Name = label .. "Btn"
        btn.Size = UDim2.new(1, 0, 0, 36)
        btn.Position = UDim2.new(0, 0, 0, yOffset)
        btn.BackgroundColor3 = UI.Colors.Accent
        btn.BorderSizePixel = 0
        btn.Text = label
        btn.TextColor3 = Color3.new(255, 255, 255)
        btn.TextSize = 13
        btn.Font = Enum.Font.GothamMedium
        btn.Parent = parent

        btn.MouseEnter:Connect(function()
            btn.BackgroundColor3 = UI.Colors.AccentDark
        end)
        btn.MouseLeave:Connect(function()
            btn.BackgroundColor3 = UI.Colors.Accent
        end)

        btn.MouseButton1Click:Connect(callback)

        yOffset = yOffset + 44
        return btn
    end

    -- [[ Build ESP Tab ]]
    yOffset = 0
    local espContent = tabContents[1]
    CreateSection(espContent, "Visuals")
    CreateToggle(espContent, "ESP.Enabled", "Enabled", "Toggle all ESP visuals")
    CreateToggle(espContent, "ESP.Box", "Box ESP", "Draw 2D boxes around players")
    CreateToggle(espContent, "ESP.BoxOutline", "Box Outline", "Outline for box ESP")
    CreateToggle(espContent, "ESP.Tracer", "Tracers", "Draw lines to players")
    CreateToggle(espContent, "ESP.Name", "Names", "Display player names")
    CreateToggle(espContent, "ESP.Health", "Health", "Show health bars and values")
    CreateToggle(espContent, "ESP.Distance", "Distance", "Show distance to target")
    CreateToggle(espContent, "ESP.TeamCheck", "Team Check", "Ignore teammates")
    CreateSlider(espContent, "ESP.MaxDistance", "Max Distance", 100, 10000, 0, "m")
    CreateSection(espContent, "World")
    CreateToggle(espContent, "World.FOVCircle", "FOV Circle", "Draw aimbot FOV circle")
    CreateToggle(espContent, "World.Crosshair", "Crosshair", "Custom crosshair")

    -- [[ Build Aimbot Tab ]]
    yOffset = 0
    local aimContent = tabContents[2]
    CreateSection(aimContent, "Settings")
    CreateToggle(aimContent, "Aimbot.Enabled", "Enabled", "Toggle aimbot")
    CreateKeybind(aimContent, "Aimbot.Keybind", "Keybind")
    CreateSlider(aimContent, "Aimbot.Smoothness", "Smoothness", 0.1, 1, 1, "")
    CreateSlider(aimContent, "Aimbot.FOV", "Field of View", 1, 360, 0, "°")
    CreateSlider(aimContent, "Aimbot.Prediction", "Prediction", 0, 0.5, 3, "s")
    CreateSection(aimContent, "Targeting")
    CreateDropdown(aimContent, "Aimbot.HitPart", "Hit Part", {"Head", "HumanoidRootPart", "Torso", "UpperTorso", "LowerTorso"})
    CreateToggle(aimContent, "Aimbot.TeamCheck", "Team Check", "Ignore teammates")
    CreateToggle(aimContent, "Aimbot.VisibleCheck", "Visibility Check", "Only target visible players")
    CreateToggle(aimContent, "Aimbot.WallCheck", "Wall Check", "Check for walls")

    -- [[ Build Silent Aim Tab ]]
    yOffset = 0
    local silentContent = tabContents[3]
    CreateSection(silentContent, "Settings")
    CreateToggle(silentContent, "SilentAim.Enabled", "Enabled", "Toggle silent aim")
    CreateSlider(silentContent, "SilentAim.FOV", "Field of View", 1, 360, 0, "°")
    CreateSlider(silentContent, "SilentAim.HitChance", "Hit Chance", 0, 100, 0, "%")
    CreateSlider(silentContent, "SilentAim.Prediction", "Prediction", 0, 0.5, 3, "s")
    CreateSection(silentContent, "Targeting")
    CreateDropdown(silentContent, "SilentAim.HitPart", "Hit Part", {"Head", "HumanoidRootPart", "Torso", "UpperTorso", "LowerTorso"})
    CreateToggle(silentContent, "SilentAim.TeamCheck", "Team Check", "Ignore teammates")
    CreateToggle(silentContent, "SilentAim.VisibleCheck", "Visibility Check", "Only target visible players")
    CreateToggle(silentContent, "SilentAim.WallCheck", "Wall Check", "Check for walls")

    -- Update canvas sizes
    for _, content in ipairs(tabContents) do
        local layout = Instance.new("UIListLayout")
        layout.Parent = content
        layout:Destroy()
        content.CanvasSize = UDim2.new(0, 0, 0, yOffset + 20)
    end

    return Main
end

local MainUI = CreateUI()

-- [[ Toggle UI ]]
local uiVisible = false
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        uiVisible = not uiVisible
        MainUI.Visible = uiVisible
        if uiVisible then
            Mouse.Icon = "rbxasset://textures//MouseUnselected.png"
        end
    end
end)

-- [[ FOV Circle Drawing ]]
local FOVCircle = Drawing.new("Circle")
FOVCircle.Visible = false
FOVCircle.Transparency = 0.7
FOVCircle.Color = UI.Colors.World.FOVCircleColor
FOVCircle.Thickness = 1
FOVCircle.NumSides = 64

-- [[ Crosshair Drawing ]]
local Crosshair = {
    HLine = Drawing.new("Line"),
    VLine = Drawing.new("Line"),
}
for _, v in pairs(Crosshair) do
    v.Visible = false
    v.Transparency = 1
    v.Thickness = 1
    v.Color = Color3.new(255, 255, 255)
end

-- [[ Main Loop ]]
RunService:BindToRenderStep("CheatwareLoop", Enum.RenderPriority.Camera.Value + 1, function()
    -- ESP
    local espEnabled = Config.ESP.Enabled

    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then
            if ESPCache[player] then
                for _, v in pairs(ESPCache[player]) do
                    v.Visible = false
                end
            end
            continue
        end

        local alive = Utility:IsAlive(player)
        local char = Utility:GetCharacter(player)
        local root = Utility:GetRootPart(char)
        local hum = Utility:GetHumanoid(char)
        local isTeamMate = Utility:IsTeamMate(player)
        local show = espEnabled and alive and root and (not Config.ESP.TeamCheck or not isTeamMate)

        if show then
            local dist = Utility:GetDistanceFromCharacter(char)
            if dist > Config.ESP.MaxDistance then show = false end
        end

        if not show then
            if ESPCache[player] then
                for _, v in pairs(ESPCache[player]) do
                    v.Visible = false
                end
            end
            continue
        end

        ESPCache:Create(player)
        local store = ESPCache[player]

        local head = char:FindFirstChild("Head")
        local humRP = root

        if not head or not humRP then
            for _, v in pairs(store) do
                v.Visible = false
            end
            continue
        end

        local dist = Utility:GetDistanceFromCharacter(char)
        local headPos = head.Position
        local rootPos = humRP.Position

        -- Calculate box dimensions
        local headScreen, headOnScreen = Camera:WorldToScreenPoint(headPos + Vector3.new(0, 0.5, 0))
        local rootScreen, rootOnScreen = Camera:WorldToScreenPoint(rootPos - Vector3.new(0, 0, 0))

        if not headOnScreen and not rootOnScreen then
            for _, v in pairs(store) do
                v.Visible = false
            end
            continue
        end

        local height = math.abs(headScreen.Y - rootScreen.Y)
        local width = height * 0.6
        local boxPos = Vector2.new(headScreen.X - width / 2, headScreen.Y)

        -- Color by health
        local healthPercent = hum and (hum.Health / hum.MaxHealth) or 1
        local healthColor = Color3.fromRGB(
            math.floor(255 * (1 - healthPercent)),
            math.floor(255 * healthPercent),
            60
        )
        local boxColor = isTeamMate and Color3.fromRGB(80, 200, 255) or Config.ESP.BoxColor

        -- Box
        if Config.ESP.Box then
            store.Box.Visible = true
            store.Box.Size = Vector2.new(width, height)
            store.Box.Position = boxPos
            store.Box.Color = boxColor

            if Config.ESP.BoxOutline then
                store.BoxOutline.Visible = true
                store.BoxOutline.Size = store.Box.Size
                store.BoxOutline.Position = store.Box.Position
            else
                store.BoxOutline.Visible = false
            end
        else
            store.Box.Visible = false
            store.BoxOutline.Visible = false
        end

        -- Tracer
        if Config.ESP.Tracer then
            local originType = Config.ESP.TracerOrigin
            local origin = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)

            if originType == "Mouse" then
                origin = Vector2.new(Mouse.X, Mouse.Y)
            elseif originType == "Crosshair" then
                origin = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
            end

            local rootScreenPos, _ = Camera:WorldToScreenPoint(rootPos)
            store.Tracer.Visible = true
            store.Tracer.From = origin
            store.Tracer.To = Vector2.new(rootScreenPos.X, rootScreenPos.Y)
            store.Tracer.Color = boxColor
        else
            store.Tracer.Visible = false
        end

        -- Name
        if Config.ESP.Name then
            store.Name.Visible = true
            store.Name.Position = Vector2.new(boxPos.X + width / 2, boxPos.Y - 16)
            store.Name.Text = player.DisplayName or player.Name
            store.Name.Size = Config.ESP.FontSize
            store.Name.Color = boxColor
        else
            store.Name.Visible = false
        end

        -- Health text + bar
        if Config.ESP.Health and hum then
            store.HealthText.Visible = true
            store.HealthText.Position = Vector2.new(boxPos.X + width / 2, boxPos.Y + height + 2)
            store.HealthText.Text = tostring(math.floor(hum.Health)) .. "/" .. tostring(math.floor(hum.MaxHealth))
            store.HealthText.Size = Config.ESP.FontSize - 1
            store.HealthText.Color = healthColor

            store.HealthBar.Visible = true
            store.HealthBar.Size = Vector2.new(4, height * healthPercent)
            store.HealthBar.Position = Vector2.new(boxPos.X - 8, boxPos.Y + height * (1 - healthPercent))
            store.HealthBar.Color = healthColor

            store.HealthBarOutline.Visible = true
            store.HealthBarOutline.Size = Vector2.new(6, height)
            store.HealthBarOutline.Position = Vector2.new(boxPos.X - 9, boxPos.Y)
        else
            store.HealthText.Visible = false
            store.HealthBar.Visible = false
            store.HealthBarOutline.Visible = false
        end

        -- Distance
        if Config.ESP.Distance then
            store.DistanceText.Visible = true
            store.DistanceText.Position = Vector2.new(boxPos.X + width / 2, boxPos.Y + height + (Config.ESP.Health and 18 or 4))
            store.DistanceText.Text = tostring(math.floor(dist)) .. "m"
            store.DistanceText.Size = Config.ESP.FontSize - 2
        else
            store.DistanceText.Visible = false
        end
    end

    -- Cleanup ESP for players that left
    for player, _ in pairs(ESPCache) do
        if not Players:FindFirstChild(player.Name) then
            ESPCache:Remove(player)
        end
    end

    -- FOV Circle
    if Config.World.FOVCircle then
        local aimbotFov = Config.Aimbot.Enabled and Config.Aimbot.FOV or Config.SilentAim.Enabled and Config.SilentAim.FOV or 90
        local radius = math.tan(math.rad(aimbotFov) / 2) * Camera.ViewportSize.Y
        FOVCircle.Visible = true
        FOVCircle.Position = Vector2.new(Mouse.X, Mouse.Y)
        FOVCircle.Radius = radius
        FOVCircle.Color = Config.World.FOVCircleColor
        FOVCircle.Transparency = Config.World.FOVCircleTransparency
    else
        FOVCircle.Visible = false
    end

    -- Crosshair
    if Config.World.Crosshair then
        local center = Camera.ViewportSize / 2
        local size = 8
        Crosshair.HLine.Visible = true
        Crosshair.VLine.Visible = true
        Crosshair.HLine.From = Vector2.new(center.X - size, center.Y)
        Crosshair.HLine.To = Vector2.new(center.X + size, center.Y)
        Crosshair.VLine.From = Vector2.new(center.X, center.Y - size)
        Crosshair.VLine.To = Vector2.new(center.X, center.Y + size)
    else
        Crosshair.HLine.Visible = false
        Crosshair.VLine.Visible = false
    end

    -- Aimbot
    Aimbot:Execute()
end)

-- [[ Silent Aim Hook (via Character/Weapon) ]]
local oldNamecall
local mt = getrawmetatable(game)
if mt then
    oldNamecall = mt.__namecall
    setreadonly(mt, false)

    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()

        if Config.SilentAim.Enabled and method == "FireServer" then
            local args = {...}
            local target = SilentAim:FindBestTarget()
            if target then
                local part = SilentAim:GetTargetPart(target)
                if part then
                    local hitChance = Config.SilentAim.HitChance / 100
                    if math.random() <= hitChance then
                        -- Calculate predicted position
                        local vel = part.Velocity or Vector3.new()
                        local predictedPos = part.Position + (vel * Config.SilentAim.Prediction)

                        -- Replace the position args (common patterns)
                        for i = 1, #args do
                            if typeof(args[i]) == "Vector3" then
                                args[i] = predictedPos
                            elseif typeof(args[i]) == "CFrame" then
                                args[i] = CFrame.new(predictedPos) * (args[i] - args[i].Position)
                            end
                        end

                        -- Replace mouse.hit equivalent
                        if #args >= 2 and typeof(args[#args - 1]) == "Vector3" and typeof(args[#args]) == "Vector3" then
                            args[#args - 1] = predictedPos
                            args[#args] = (predictedPos - Camera.CFrame.Position).Unit * 1000
                        end

                        return oldNamecall(self, unpack(args))
                    end
                end
            end
        end

        return oldNamecall(self, ...)
    end)

    setreadonly(mt, true)
end

-- [[ Player Added / Removed ]]
Players.PlayerRemoving:Connect(function(player)
    ESPCache:Remove(player)
end)

-- [[ Notification on load ]]
local notification = Instance.new("Message")
notification.Text = "Cheatware loaded. Press Right Shift to toggle the menu."
notification.Parent = LocalPlayer:WaitForChild("PlayerGui")
task.wait(3)
notification:Destroy()

print("Cheatware loaded successfully.")
