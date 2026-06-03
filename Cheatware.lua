--[[
    Cheatware // Combat Suite  v18 (Linoria)

    v18 changes:
        - FULL REBRAND: IMP -> Cheatware everywhere (title, theme names, save/theme
          folders, banner notify, print tags, comments).
        - Main window narrowed: 600 -> 500 px. All four nav buttons recompute
          dynamically off TabArea.AbsoluteSize and get a +2 px tweak per button.
        - Combat tab now ALSO monkey-patches its outer Tab.Resize (Library.lua line
          7445), which Linoria invokes on every Tab:ShowTab() (line 7531). This is
          the regression source -- LeftSide.Size was being reset to (0.5, -10, 1, -14)
          whenever the user switched main tabs and came back. Now the override is
          re-applied inside the patched Resize, so full-width sticks across switches.
        - Combat sub-tab buttons trimmed -0.5 px each per request, and BoxOuter is
          stretched to fill the full tab height so the inner content extends further
          down instead of hugging only the current control list height.
        - Skin Changer rebuilt for ACTUAL Rivals named skins (AK-47, Boneclaw,
          Karambit, AUG, Pixel Sniper, etc.). Discovery walks every known asset
          path: ItemLibrary.Items[Weapon].Skins, ReplicatedStorage.Skins,
          PlayerScripts.Assets.Skins, PlayerScripts.Assets.ViewModels.Weapons (flat
          variant list), and per-weapon nested .Skins subfolders. Apply clones the
          skin's instances into the live weapon ViewModel, with original-state
          caching for one-click Restore.
        - Wrap/material editor preserved underneath as "Wrap & Color Editor".

    v17 changes:
        - Main window narrowed: 650 -> 600 px (50 px slimmer). All four nav buttons
          recompute dynamically off TabArea.AbsoluteSize so they fill the bar with
          ZERO empty space, no matter what window size is set.
        - Combat sub-tab bar (Aimbot / Silent Aim / Triggerbot / Gun Mods) now
          monkey-patches Linoria's internal Tab:Resize so the (1/N, 0, 1, 0)
          override Linoria forces on every tab-switch gets re-corrected to
          (1/N, -gap*(N-1)/N, 1, 0). Result: 4 buttons + 3 gaps fill the full
          tabbox bar exactly, every time, even after clicking a different sub-tab.
        - Tabbox UIListLayout.Padding raised from 0 -> 8 px for visible spacing.

    v16 changes:
        - Nav bar buttons trimmed from 149 -> 130 px (~19 px smaller per tab).
        - Combat tab restructured: the left Tabbox now spans the FULL window width and
          contains 4 sub-tabs (Aimbot / Silent Aim / Triggerbot / Gun Mods). Sub-tab
          buttons auto-size to fill the bar evenly with explicit gap padding, and each
          sub-tab content area gets extra inner padding.
        - Misc tab now ships a full Rivals Skin Changer (wraps, material variants,
          base material, color, transparency, reflectance, apply-to-all, auto re-apply
          on equip, randomize, reset).
        - All Linoria built-in themes wiped; only the 7 IMP editor palettes remain,
          with IMP Catppuccin as the default scheme.

    v15 changes:
        - Combat tab now uses a left-side Tabbox with three sub-tabs: Aimbot, Silent Aim,
          Triggerbot. Right side keeps Gun Mods as a permanent groupbox.
        - Top-bar tab buttons are explicitly sized to 149 px each so the four buttons
          (Combat / Visuals / Misc / Settings) fill the entire 650-wide nav bar with
          their existing TabPadding=8 gaps intact. No padding-string hack anymore.
        - Theme list replaced with 7 modern editor-grade palettes (Catppuccin Mocha,
          Tokyo Night, Rose Pine, Gruvbox, Dracula, Nord, One Dark). All contrast-checked.

    v14 fixes:
        - killESP no longer crashes on Color3 fields. The old loop iterated EVERY entry
          key, including cached `_boxColor`/`_nameColor`/etc., and accessing `.Remove`
          on a Color3 userdata throws "Remove is not a valid member of Color3" (the
          access itself errors, so the pcall around the call never fired). Now uses
          an explicit drawing-key list.
        - All Drawing objects (FOVCircle, SilentAimCircle, ESP box/name/dist/hp/tracer)
          now explicitly set Transparency = 1. Many executors default Drawing
          Transparency to 0 (invisible), which was hiding everything that wasn't a
          Roblox Highlight (Chams was working precisely because it bypasses Drawing).
        - JumpPower/WalkSpeed restoration now uses the game's original values captured
          on first humanoid touch instead of hard-coded 16/50, fixing the "jump is always
          high on respawn" bug.

    v13 fixes:
        - REMOVED `WindowFocused` render-loop gate completely.
        - Moved all Aimbot UI hooks to use inline `Callback`.
    v12 changelog (kept for context):
        - REMOVED broken ThemeManager:ApplyTheme() call (method doesn't exist in Linoria, was killing
          script execution mid-init â€” that's why everything after it stopped working in v11)
        - FIXED custom theme format: hex strings + correct {order, {nested}} structure
          (verified against mstudio45/LinoriaLib/addons/ThemeManager.lua source)
        - Added IMP Cyber + IMP Vampire bonus themes

    v11 carryover (kept):
        - ZIndex wrapped in pcall (Solara/Delta safety)
        - JumpPower/WalkSpeed proper restore via UseJumpPower = false
        - Smoothness 1=Snappy, 20=Smooth (1/N lerp)
        - Prediction X/Z + Y split sliders
        - Hitbox Resolver (velocity clamp >150 studs/s)
        - No "Only When Shooting" toggle, no "Hold MB2 to Trigger" toggle
        - Padded tab names + TabPadding=8 + 650x600 window
--]]

-- ========================== SERVICES ==========================
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local Lighting         = game:GetService("Lighting")
local VirtualUser      = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

local Vector2_new, Vector3_new   = Vector2.new, Vector3.new
local Color3_new, Color3_fromRGB = Color3.new, Color3.fromRGB
local mathFloor, mathAbs, mathMax, mathMin, mathRandom = math.floor, math.abs, math.max, math.min, math.random
local tickFn, ipairsFn, pairsFn  = tick, ipairs, pairs
local strFormat, strByte         = string.format, string.byte
local typeofFn = typeof

-- ========================== STATE =============================
local S = {
    Aimbot = {
        Enabled = false, FOV = 100, Smoothness = 5, ShowFOV = true,
        TargetPart = "HumanoidRootPart", TeamCheck = true, WallCheck = false,
        PredictX = 0.15, PredictY = 0.15, Resolver = true,
    },
    ESP = {
        Enabled = false, TeamCheck = true, MaxDistance = 5000, UpdateRate = 60,
        Box = true, BoxColor = Color3_fromRGB(255, 40, 40),
        Name = true, NameColor = Color3_fromRGB(255, 255, 255),
        Distance = true, DistanceColor = Color3_fromRGB(200, 200, 200),
        HealthBar = true,
        Tracer = false, TracerColor = Color3_fromRGB(255, 255, 255),
        Chams = false, ChamsColor = Color3_fromRGB(255, 0, 170),
    },
    SilentAim = {
        Enabled = false, FOV = 200, ShowFOV = false, FOVColor = Color3_fromRGB(255, 0, 170),
        HitChance = 100, TargetPart = "Head", TeamCheck = true, AliveCheck = true, MaxDistance = 1000,
        Method = "ViewportSize"
    },
    Trigger = {
        Enabled = false, Delay = 50, FireDelay = 100, MaxDistance = 1000,
        TeamCheck = true, AliveCheck = true
    },
    GunMods = { NoRecoil = false, FastFire = false },
    Misc = {
        Fly = false, FlySpeed = 50, Noclip = false,
        WalkSpeedEn = false, WalkSpeed = 16,
        JumpPowerEn = false, JumpPower = 50,
        InfJump = false,
        Fullbright = false, NoFog = false,
        CustomFOVEn = false, CustomFOV = 90,
        AntiAFK = false
    },
    Skin = {
        Weapon = nil, WrapTex = nil, WrapVariant = nil, Material = "SmoothPlastic",
        Color = Color3.fromRGB(255, 255, 255), Transparency = 0, Reflectance = 0,
        UseColor = false, UseMaterial = false, UseTransparency = false,
        UseWrap = false, UseWrapMat = false,
        ApplyAll = false, AutoReapply = false,
    }
}

-- ========================== DRAWING SHIM ======================
local Drawing = Drawing or getgenv().Drawing
if not Drawing or type(Drawing.new) ~= "function" then
    local fmt = {__index = function() return function() end end}
    Drawing = setmetatable({ new = function() return setmetatable({Remove=function()end, Visible=false}, fmt) end, Fonts = {Plex = 2} }, fmt)
end

-- ========================== HP COLOR LUT ======================
local HP_LUT = {}
do
    for i = 0, 20 do
        local pct = i / 20; local r, g, b
        if pct > 0.5 then
            local t = (pct - 0.5) * 2; r = mathFloor(255 * (1 - t)); g = mathFloor(165 + (255 - 165) * t); b = 0
        else
            local t = pct * 2; r = 255; g = mathFloor(165 * t); b = 0
        end
        HP_LUT[i] = Color3_fromRGB(r, g, b)
    end
end

-- ========================== PLAYER CACHE ======================
local PlayerCache = {}; local PlayerList = {}
local function rebuildList()
    local t, n = {}, 0
    for p in pairsFn(PlayerCache) do n = n + 1; t[n] = p end
    PlayerList = t
end

local function bindCharacter(plr, char)
    local entry = PlayerCache[plr]; if not entry then return end
    entry.char = char
    entry.hum  = char:FindFirstChildOfClass("Humanoid")
    entry.hrp  = char:FindFirstChild("HumanoidRootPart")
    entry.head = char:FindFirstChild("Head")
    if not entry.hum or not entry.hrp or not entry.head then
        task.spawn(function()
            entry.hum  = entry.hum  or char:WaitForChild("Humanoid", 5)
            entry.hrp  = entry.hrp  or char:WaitForChild("HumanoidRootPart", 5)
            entry.head = entry.head or char:WaitForChild("Head", 5)
        end)
    end
end

local function trackPlayer(plr)
    if plr == LocalPlayer then return end
    if PlayerCache[plr] then return end
    PlayerCache[plr] = { char=nil, hum=nil, hrp=nil, head=nil, _conns={} }
    if plr.Character then bindCharacter(plr, plr.Character) end
    PlayerCache[plr]._conns[#PlayerCache[plr]._conns+1] = plr.CharacterAdded:Connect(function(c) bindCharacter(plr, c) end)
    rebuildList()
end

local function untrackPlayer(plr)
    local entry = PlayerCache[plr]; if not entry then return end
    for _, c in ipairsFn(entry._conns) do c:Disconnect() end
    PlayerCache[plr] = nil; rebuildList()
end

for _, p in ipairsFn(Players:GetPlayers()) do trackPlayer(p) end
Players.PlayerAdded:Connect(trackPlayer)
Players.PlayerRemoving:Connect(untrackPlayer)

-- ========================== UTILS =============================
local function byteOf(s) return strByte(s or "\0") end
local function rivalsEnemyCheck(plr, requireTeam)
    if not plr or plr == LocalPlayer then return false end
    local ourEnv  = LocalPlayer:GetAttribute("EnvironmentID")
    local theirEnv = plr:GetAttribute("EnvironmentID")
    if ourEnv and theirEnv and byteOf(ourEnv) ~= byteOf(theirEnv) then return false end
    if requireTeam then
        local ourTeam = LocalPlayer:GetAttribute("TeamID")
        local theirTeam = plr:GetAttribute("TeamID")
        if ourTeam and theirTeam and byteOf(ourTeam) == byteOf(theirTeam) then return false end
        if (not ourTeam or not theirTeam) and LocalPlayer.Team and plr.Team and LocalPlayer.Team == plr.Team then return false end
    end
    return true
end

local function aliveEntry(entry) return entry and entry.hum and entry.hrp and entry.hum.Health > 0 end

local function visible(pos, ignoreChar)
    local parts = Camera:GetPartsObscuringTarget({pos}, {LocalPlayer.Character, Camera, ignoreChar})
    return #parts == 0
end

-- ========================== AIMBOT ============================
local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness=2; FOVCircle.NumSides=64; FOVCircle.Color=Color3_fromRGB(255,255,255); FOVCircle.Transparency=1; FOVCircle.Filled=false; FOVCircle.Visible=false

local SilentAimCircle = Drawing.new("Circle")
SilentAimCircle.Thickness=2; SilentAimCircle.NumSides=64; SilentAimCircle.Color=Color3_fromRGB(255,0,170); SilentAimCircle.Transparency=1; SilentAimCircle.Filled=false; SilentAimCircle.Visible=false

local function getClosestPlayer()
    local closest, closestDist = nil, S.Aimbot.FOV
    local mouseLoc = UserInputService:GetMouseLocation()
    local targetPartName, teamCheck, wallCheck = S.Aimbot.TargetPart, S.Aimbot.TeamCheck, S.Aimbot.WallCheck

    for i = 1, #PlayerList do
        local p = PlayerList[i]
        local entry = PlayerCache[p]
        if entry and aliveEntry(entry) and (not teamCheck or rivalsEnemyCheck(p, true)) then
            local char = entry.char
            local part = char and (char:FindFirstChild(targetPartName) or entry.hrp)
            if part then
                local sp, on = Camera:WorldToViewportPoint(part.Position)
                if on then
                    local dx = sp.X - mouseLoc.X; local dy = sp.Y - mouseLoc.Y; local d = (dx*dx + dy*dy) ^ 0.5
                    if d < closestDist then
                        if not wallCheck or visible(part.Position, char) then closest = p; closestDist = d end
                    end
                end
            end
        end
    end
    return closest
end

local function aimAt(target)
    if not target then return end
    local entry = PlayerCache[target]; if not entry or not entry.char then return end
    local part = entry.char:FindFirstChild(S.Aimbot.TargetPart) or entry.hrp
    if not part then return end

    local pos = part.Position
    local px, py = S.Aimbot.PredictX, S.Aimbot.PredictY

    if px > 0 or py > 0 then
        local ok, vel = pcall(function() return part.AssemblyLinearVelocity end)
        if ok and vel then
            -- Hitbox Resolver: Clamp absurd velocities (desyncs)
            if S.Aimbot.Resolver and vel.Magnitude > 150 then vel = Vector3_new(0, 0, 0) end
            pos = pos + Vector3_new(vel.X * px, vel.Y * py, vel.Z * px)
        end
    end

    local sp = Camera:WorldToViewportPoint(pos)
    local mouseLoc = UserInputService:GetMouseLocation()

    -- Smoothness mapping: 1 = instant (alpha=1), 20 = slow (alpha=0.05)
    local alpha = mathMax(0.01, mathMin(1, 1 / S.Aimbot.Smoothness))
    local smoothed = mouseLoc:Lerp(Vector2_new(sp.X, sp.Y), alpha)
    pcall(mousemoverel, smoothed.X - mouseLoc.X, smoothed.Y - mouseLoc.Y)
end

-- ========================== TRIGGERBOT ========================
local TriggerLastFire = 0
local TriggerRayParams = RaycastParams.new()
TriggerRayParams.FilterType = Enum.RaycastFilterType.Exclude

local function triggerCheck()
    if not S.Trigger.Enabled then return end
    local nowMs = tickFn() * 1000
    if nowMs - TriggerLastFire < S.Trigger.FireDelay then return end

    TriggerRayParams.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
    local origin = Camera.CFrame.Position
    local direction = Camera.CFrame.LookVector * S.Trigger.MaxDistance
    local result = workspace:Raycast(origin, direction, TriggerRayParams)
    if not result then return end

    local model = result.Instance:FindFirstAncestorOfClass("Model")
    if not model then return end
    local plr = Players:GetPlayerFromCharacter(model)
    if not plr or plr == LocalPlayer then return end

    if not rivalsEnemyCheck(plr, S.Trigger.TeamCheck) then return end
    local entry = PlayerCache[plr]
    if S.Trigger.AliveCheck and not aliveEntry(entry) then return end

    TriggerLastFire = nowMs
    task.delay(S.Trigger.Delay / 1000, function()
        if mouse1press and mouse1release then
            mouse1press(); task.wait(0.04); mouse1release()
        end
    end)
end

-- ========================== SHOOTING STATE ====================
local IsShooting = false
UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then IsShooting = true end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then IsShooting = false end
end)

-- ========================== SILENT AIM ========================
local SilentTarget = nil
local LastSilentScan = 0

local function pickSilentTarget()
    if not S.SilentAim.Enabled then SilentTarget = nil; return end
    if mathRandom(1, 100) > S.SilentAim.HitChance then SilentTarget = nil; return end

    local camPos = Camera.CFrame.Position
    local center = Camera.ViewportSize / 2
    local fovPx, maxD = S.SilentAim.FOV, S.SilentAim.MaxDistance
    local partName, teamCheck, aliveCheck = S.SilentAim.TargetPart, S.SilentAim.TeamCheck, S.SilentAim.AliveCheck

    local best, bestDist = nil, fovPx
    for i = 1, #PlayerList do
        local plr = PlayerList[i]
        local entry = PlayerCache[plr]
        if entry and (not aliveCheck or aliveEntry(entry)) and rivalsEnemyCheck(plr, teamCheck) then
            local char = entry.char
            local part = char and (char:FindFirstChild(partName) or entry.head)
            if part then
                local worldPos = part.Position
                if (worldPos - camPos).Magnitude <= maxD then
                    local sp, on = Camera:WorldToViewportPoint(worldPos)
                    if on then
                        local dx = sp.X - center.X; local dy = sp.Y - center.Y; local d = (dx*dx + dy*dy) ^ 0.5
                        if d < bestDist then bestDist = d; best = worldPos end
                    end
                end
            end
        end
    end
    SilentTarget = best
end

local hookmm = hookmetamethod
local newcc  = newcclosure or function(f) return f end
local checkcal = checkcaller or function() return false end
local getncm = getnamecallmethod

if hookmm then
    local oldIndex
    oldIndex = hookmm(game, "__index", newcc(function(self, key, ...)
        if SilentTarget and self == Camera and key == "ViewportSize" and not checkcal() then
            local m = S.SilentAim.Method
            if m == "ViewportSize" or m == "Both" then
                local sp, on = Camera:WorldToViewportPoint(SilentTarget)
                if on then return Vector2_new(sp.X * 2, sp.Y * 2) end
            end
        end
        return oldIndex(self, key, ...)
    end))

    local oldNamecall
    oldNamecall = hookmm(game, "__namecall", newcc(function(self, ...)
        if SilentTarget and IsShooting and not checkcal() then
            local m = S.SilentAim.Method
            if (m == "Raycast" or m == "Both") and self == workspace then
                local method = getncm()
                if method == "Raycast" then
                    local args = {...}
                    if typeofFn(args[1]) == "Vector3" and typeofFn(args[2]) == "Vector3" then
                        local origin = args[1]
                        local mag = args[2].Magnitude
                        if mag > 0 then
                            args[2] = (SilentTarget - origin).Unit * mag
                            return oldNamecall(self, table.unpack(args))
                        end
                    end
                elseif method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist" then
                    local args = {...}
                    if typeofFn(args[1]) == "Ray" then
                        local origin = args[1].Origin
                        local mag = args[1].Direction.Magnitude
                        if mag < 1 then mag = 5000 end
                        args[1] = Ray.new(origin, (SilentTarget - origin).Unit * mag)
                        return oldNamecall(self, table.unpack(args))
                    end
                end
            end
        end
        return oldNamecall(self, ...)
    end))
end

-- ========================== GUN MODS ==========================
local OrigGunStats = {}
local function updateGunMods()
    local ok, ItemLib = pcall(function() return require(ReplicatedStorage:WaitForChild("Modules", 5):WaitForChild("ItemLibrary", 5)) end)
    if not ok or not ItemLib or not ItemLib.Items then return end
    local exceptions = { Sniper=true, Crossbow=true, Bow=true, RPG=true }

    for name, data in pairsFn(ItemLib.Items) do
        if type(data) == "table" and not exceptions[name] then
            if not OrigGunStats[name] then
                OrigGunStats[name] = {
                    ShootSpread = data.ShootSpread, ShootAccuracy = data.ShootAccuracy, ShootRecoil = data.ShootRecoil,
                    ShootCooldown = data.ShootCooldown, ShootBurstCooldown = data.ShootBurstCooldown,
                }
            end
            local orig = OrigGunStats[name]
            if orig.ShootSpread        ~= nil then data.ShootSpread        = S.GunMods.NoRecoil and 0    or orig.ShootSpread end
            if orig.ShootAccuracy      ~= nil then data.ShootAccuracy      = S.GunMods.NoRecoil and 0    or orig.ShootAccuracy end
            if orig.ShootRecoil        ~= nil then data.ShootRecoil        = S.GunMods.NoRecoil and 0    or orig.ShootRecoil end
            if orig.ShootCooldown      ~= nil then data.ShootCooldown      = S.GunMods.FastFire and 0.05 or orig.ShootCooldown end
            if orig.ShootBurstCooldown ~= nil then data.ShootBurstCooldown = S.GunMods.FastFire and 0.05 or orig.ShootBurstCooldown end
        end
    end
end

-- ========================== ESP ==============================
local ESPCache = {}
local function makeESP(plr)
    local e = {
        box=Drawing.new("Square"), boxOL=Drawing.new("Square"),
        name=Drawing.new("Text"), dist=Drawing.new("Text"),
        hp=Drawing.new("Square"), hpBg=Drawing.new("Square"), tracer=Drawing.new("Line"), chams=nil,
        _nameText="", _distInt=-1, _hpKey=-1,
        _boxColor=nil, _nameColor=nil, _distColor=nil, _tracerColor=nil,
    }
    -- Safely assign ZIndex, executor might not support it
    pcall(function() e.boxOL.ZIndex=1; e.box.ZIndex=2; e.hpBg.ZIndex=1; e.hp.ZIndex=2; e.name.ZIndex=3; e.dist.ZIndex=3; e.tracer.ZIndex=2 end)

    -- Force Transparency=1 (fully opaque) on every drawing because some executors
    -- default it to 0 (invisible). This single bug was hiding box/name/dist/hp/tracer
    -- while Chams (a Roblox Highlight instance) still rendered fine.
    e.boxOL.Thickness=3; e.boxOL.Color=Color3_new(0,0,0); e.boxOL.Filled=false; e.boxOL.Transparency=1
    e.box.Thickness=1; e.box.Filled=false; e.box.Transparency=1
    e.hpBg.Filled=true; e.hpBg.Color=Color3_new(0,0,0); e.hpBg.Transparency=1
    e.hp.Filled=true; e.hp.Transparency=1
    e.name.Center=true; e.name.Outline=true; e.name.Size=13; e.name.Font=Drawing.Fonts.Plex; e.name.Transparency=1
    e.dist.Center=true; e.dist.Outline=true; e.dist.Size=13; e.dist.Font=Drawing.Fonts.Plex; e.dist.Transparency=1
    e.tracer.Thickness=1; e.tracer.Transparency=1
    ESPCache[plr] = e
end
local function hideESP(e)
    e.box.Visible=false; e.boxOL.Visible=false; e.name.Visible=false; e.dist.Visible=false
    e.hp.Visible=false; e.hpBg.Visible=false; e.tracer.Visible=false
    if e.chams then e.chams.Enabled=false end
end
local ESP_DRAW_KEYS = {"box","boxOL","name","dist","hp","hpBg","tracer"}
local function killESP(plr)
    local e = ESPCache[plr]; if not e then return end
    if e.chams then pcall(function() e.chams:Destroy() end); e.chams = nil end
    for _, k in ipairsFn(ESP_DRAW_KEYS) do
        local d = e[k]
        if d then pcall(function() d:Remove() end) end
    end
    ESPCache[plr] = nil
end
Players.PlayerRemoving:Connect(killESP)

local function updateESP()
    if not S.ESP.Enabled then
        if next(ESPCache) then for _, e in pairsFn(ESPCache) do hideESP(e) end end
        return
    end
    local camPos = Camera.CFrame.Position
    local vsX_half = Camera.ViewportSize.X * 0.5; local vsY = Camera.ViewportSize.Y
    local maxDist, teamCheck = S.ESP.MaxDistance, S.ESP.TeamCheck
    local showBox, showName, showDist, showHP, showTracer, showChams = S.ESP.Box, S.ESP.Name, S.ESP.Distance, S.ESP.HealthBar, S.ESP.Tracer, S.ESP.Chams
    local boxCol = S.ESP.BoxColor or Color3_fromRGB(255,40,40)
    local nameCol = S.ESP.NameColor or Color3_new(1,1,1)
    local distCol = S.ESP.DistanceColor or Color3_fromRGB(200,200,200)
    local tracerCol = S.ESP.TracerColor or Color3_new(1,1,1)
    local chamsCol = S.ESP.ChamsColor or Color3_fromRGB(255,0,170)

    for i = 1, #PlayerList do if not ESPCache[PlayerList[i]] then makeESP(PlayerList[i]) end end

    for plr, e in pairsFn(ESPCache) do
        local entry = PlayerCache[plr]
        if not entry or not plr.Parent then hideESP(e)
        else
            local hum, hrp, head = entry.hum, entry.hrp, entry.head
            if not (hum and hrp and head) or hum.Health <= 0 or (teamCheck and not rivalsEnemyCheck(plr, true)) then hideESP(e)
            else
                local hrpPos = hrp.Position
                local dx, dy, dz = hrpPos.X - camPos.X, hrpPos.Y - camPos.Y, hrpPos.Z - camPos.Z
                local dist3D = (dx*dx + dy*dy + dz*dz) ^ 0.5
                if dist3D > maxDist then hideESP(e)
                else
                    local tV, tOn = Camera:WorldToViewportPoint(head.Position + Vector3_new(0, 0.5, 0))
                    local bV, bOn = Camera:WorldToViewportPoint(hrpPos - Vector3_new(0, 3, 0))
                    if not (tOn and bOn) then hideESP(e)
                    else
                        local h = mathAbs(bV.Y - tV.Y); local w = h * 0.55
                        local x = tV.X - w/2; local y = tV.Y

                        e.box.Visible = showBox; e.boxOL.Visible = showBox
                        if showBox then
                            e.box.Position = Vector2_new(x, y); e.box.Size = Vector2_new(w, h)
                            e.boxOL.Position = Vector2_new(x, y); e.boxOL.Size = Vector2_new(w, h)
                            if e._boxColor ~= boxCol then e.box.Color = boxCol; e._boxColor = boxCol end
                        end
                        e.name.Visible = showName
                        if showName then
                            e.name.Position = Vector2_new(x + w/2, y - 16)
                            if e._nameColor ~= nameCol then e.name.Color = nameCol; e._nameColor = nameCol end
                            local newName = plr.DisplayName == plr.Name and plr.Name or (plr.DisplayName.." (@"..plr.Name..")")
                            if e._nameText ~= newName then e.name.Text = newName; e._nameText = newName end
                        end
                        e.dist.Visible = showDist
                        if showDist then
                            e.dist.Position = Vector2_new(x + w/2, y + h + 2)
                            if e._distColor ~= distCol then e.dist.Color = distCol; e._distColor = distCol end
                            local di = mathFloor(dist3D)
                            if e._distInt ~= di then e.dist.Text = strFormat("[%dm]", di); e._distInt = di end
                        end
                        if showHP then
                            local pct = mathMax(0, mathMin(1, hum.Health / mathMax(1, hum.MaxHealth)))
                            e.hpBg.Visible=true; e.hpBg.Position=Vector2_new(x-6, y); e.hpBg.Size=Vector2_new(3, h)
                            e.hp.Visible=true; e.hp.Position=Vector2_new(x-6, y + h*(1-pct)); e.hp.Size=Vector2_new(3, mathMax(1, h*pct))
                            local key = mathFloor(pct * 20 + 0.5)
                            if e._hpKey ~= key then e.hp.Color = HP_LUT[key]; e._hpKey = key end
                        else e.hp.Visible=false; e.hpBg.Visible=false end
                        if showTracer then
                            e.tracer.Visible=true; e.tracer.From = Vector2_new(vsX_half, vsY); e.tracer.To = Vector2_new(x + w/2, y + h)
                            if e._tracerColor ~= tracerCol then e.tracer.Color = tracerCol; e._tracerColor = tracerCol end
                        else e.tracer.Visible=false end
                        if showChams then
                            if not (e.chams and e.chams.Parent) then
                                local hl = Instance.new("Highlight"); hl.Name = "Cheatware_Chams"; hl.Adornee = entry.char
                                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Parent = entry.char
                                e.chams = hl
                            end
                            e.chams.Enabled = true; e.chams.FillColor = chamsCol; e.chams.FillTransparency = 0.5
                        elseif e.chams then e.chams.Enabled = false end
                    end
                end
            end
        end
    end
end

-- ========================== HUMANOID OVERRIDES ====================
-- Snapshot of the game's natural humanoid stats so we can restore exactly what the
-- game configured instead of hard-coding 16 WS / 50 JP (which was overriding games
-- that intentionally set high JumpHeight or low custom WalkSpeed).
local HumOverrideConns = {}
local HumOriginals = {} -- per-humanoid original {WalkSpeed, JumpPower, JumpHeight, UseJumpPower}

local function snapshotHum(hum)
    if not hum or HumOriginals[hum] then return end
    HumOriginals[hum] = {
        WalkSpeed    = hum.WalkSpeed,
        JumpPower    = hum.JumpPower,
        JumpHeight   = hum.JumpHeight,
        UseJumpPower = hum.UseJumpPower,
    }
end

local function hookHumanoid(hum)
    if not hum or HumOverrideConns[hum] then return end
    snapshotHum(hum)
    HumOverrideConns[hum] = {
        hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
            if S.Misc.WalkSpeedEn and hum.WalkSpeed ~= S.Misc.WalkSpeed then hum.WalkSpeed = S.Misc.WalkSpeed end
        end),
        hum:GetPropertyChangedSignal("JumpPower"):Connect(function()
            if S.Misc.JumpPowerEn and hum.JumpPower ~= S.Misc.JumpPower then hum.UseJumpPower = true; hum.JumpPower = S.Misc.JumpPower end
        end),
    }
end

local function applyWS()
    local c = LocalPlayer.Character; if not c then return end
    local hum = c:FindFirstChildOfClass("Humanoid"); if not hum then return end
    snapshotHum(hum)
    if S.Misc.WalkSpeedEn then
        hum.WalkSpeed = S.Misc.WalkSpeed
    else
        hum.WalkSpeed = HumOriginals[hum].WalkSpeed  -- restore exactly what the game configured
    end
end

local function applyJP()
    local c = LocalPlayer.Character; if not c then return end
    local hum = c:FindFirstChildOfClass("Humanoid"); if not hum then return end
    snapshotHum(hum)
    if S.Misc.JumpPowerEn then
        hum.UseJumpPower = true
        hum.JumpPower    = S.Misc.JumpPower
    else
        -- Restore exactly what the game configured, not a hard-coded 50 â€” this was
        -- the cause of jump speed feeling wrong on every respawn.
        local o = HumOriginals[hum]
        hum.UseJumpPower = o.UseJumpPower
        hum.JumpPower    = o.JumpPower
        hum.JumpHeight   = o.JumpHeight
    end
end

-- ========================== NOCLIP ==============================
local NoclipCache = {}
local function applyNoclip(on)
    local char = LocalPlayer.Character; if not char then return end
    if on then
        for _, p in ipairsFn(char:GetDescendants()) do
            if p:IsA("BasePart") then
                if NoclipCache[p] == nil then NoclipCache[p] = p.CanCollide end
                p.CanCollide = false
            end
        end
    else
        for p, orig in pairsFn(NoclipCache) do if p.Parent then pcall(function() p.CanCollide = orig end) end end
        NoclipCache = {}
    end
end

-- ========================== LIGHTING SNAPSHOT ===================
local LightingSnap = {}
local function snapshotLighting()
    LightingSnap = {
        Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
        ColorShift_Bottom = Lighting.ColorShift_Bottom, ColorShift_Top = Lighting.ColorShift_Top,
        Brightness = Lighting.Brightness, GlobalShadows = Lighting.GlobalShadows,
        FogStart = Lighting.FogStart, FogEnd = Lighting.FogEnd,
    }
end
snapshotLighting()

local function applyFullbright(on)
    if on then
        Lighting.Ambient = Color3_new(1, 1, 1); Lighting.OutdoorAmbient = Color3_new(1, 1, 1)
        Lighting.ColorShift_Bottom = Color3_new(1, 1, 1); Lighting.Brightness = 2; Lighting.GlobalShadows = false
    else
        Lighting.Ambient = LightingSnap.Ambient; Lighting.OutdoorAmbient = LightingSnap.OutdoorAmbient
        Lighting.ColorShift_Bottom = LightingSnap.ColorShift_Bottom; Lighting.Brightness = LightingSnap.Brightness
        Lighting.GlobalShadows = LightingSnap.GlobalShadows
    end
end
local function applyNoFog(on)
    if on then Lighting.FogStart = 9e9; Lighting.FogEnd = 9e9
    else Lighting.FogStart = LightingSnap.FogStart; Lighting.FogEnd = LightingSnap.FogEnd end
end

-- ========================== LINORIA UI ========================
local repo = "https://raw.githubusercontent.com/mstudio45/LinoriaLib/main/"
local urls = { repo .. "Library.lua", repo .. "addons/ThemeManager.lua", repo .. "addons/SaveManager.lua" }
local sources = {}; local pending = #urls
for i, url in ipairsFn(urls) do
    task.spawn(function()
        local ok, body = pcall(game.HttpGet, game, url)
        sources[i] = ok and body or ""; pending = pending - 1
    end)
end
while pending > 0 do task.wait() end

local Library = loadstring(sources[1])()
local ThemeManager = loadstring(sources[2])()
local SaveManager = loadstring(sources[3])()
local Options = Library.Options; local Toggles = Library.Toggles
Library.ShowCustomCursor = false; Library.NotifySide = "Left"

-- Modern, clean theme set -- 7 Cheatware editor-grade palettes (battle-tested hex,
-- pulled from popular editor color schemes (verified hex values, accent contrast > 4.5:1).
-- v18: wipe EVERY Linoria stock theme (Default, BBot, Fatality, Jester, Mint, Tokyo Night,
-- Ubuntu, Quartz, Pastel, etc.) so only the 7 Cheatware palettes remain. Force Cheatware Catppuccin
-- as the default scheme so config-less startups land on a known-good palette.
for k in pairs(ThemeManager.BuiltInThemes) do ThemeManager.BuiltInThemes[k] = nil end
ThemeManager.DefaultScheme = "Cheatware Catppuccin"

ThemeManager.BuiltInThemes["Cheatware Catppuccin"] = { 1, {
    FontColor       = "cdd6f4",
    MainColor       = "1e1e2e",
    AccentColor     = "cba6f7",
    BackgroundColor = "11111b",
    OutlineColor    = "313244",
} }
ThemeManager.BuiltInThemes["Cheatware Tokyo Night"] = { 2, {
    FontColor       = "c0caf5",
    MainColor       = "1a1b26",
    AccentColor     = "7aa2f7",
    BackgroundColor = "16161e",
    OutlineColor    = "292e42",
} }
ThemeManager.BuiltInThemes["Cheatware Rose Pine"] = { 3, {
    FontColor       = "e0def4",
    MainColor       = "191724",
    AccentColor     = "eb6f92",
    BackgroundColor = "1f1d2e",
    OutlineColor    = "26233a",
} }
ThemeManager.BuiltInThemes["Cheatware Gruvbox"] = { 4, {
    FontColor       = "ebdbb2",
    MainColor       = "282828",
    AccentColor     = "fabd2f",
    BackgroundColor = "1d2021",
    OutlineColor    = "504945",
} }
ThemeManager.BuiltInThemes["Cheatware Dracula"] = { 5, {
    FontColor       = "f8f8f2",
    MainColor       = "282a36",
    AccentColor     = "bd93f9",
    BackgroundColor = "1e1f29",
    OutlineColor    = "44475a",
} }
ThemeManager.BuiltInThemes["Cheatware Nord"] = { 6, {
    FontColor       = "eceff4",
    MainColor       = "2e3440",
    AccentColor     = "88c0d0",
    BackgroundColor = "242933",
    OutlineColor    = "434c5e",
} }
ThemeManager.BuiltInThemes["Cheatware One Dark"] = { 7, {
    FontColor       = "abb2bf",
    MainColor       = "282c34",
    AccentColor     = "61afef",
    BackgroundColor = "21252b",
    OutlineColor    = "3e4451",
} }

local Window = Library:CreateWindow({ Title = "Cheatware // Combat Suite", Center = true, AutoShow = true, Resizable = false, TabPadding = 8, MenuFadeTime = 0, Size = UDim2.fromOffset(500, 600) })

-- Padded strings force the buttons to stretch across the navbar width
local Tabs = {
    Combat   = Window:AddTab("Combat"),
    Visuals  = Window:AddTab("Visuals"),
    Misc     = Window:AddTab("Misc"),
    Settings = Window:AddTab("Settings")
}

-- =============== COMBAT TAB ===============
-- Full-width Tabbox with 4 sub-tabs (Aimbot / Silent Aim / Triggerbot / Gun Mods).
-- Left side is expanded to span the full window width; right side is hidden later.
local CombatModes = Tabs.Combat:AddLeftTabbox("Combat Modes")
local AimTab     = CombatModes:AddTab("Aimbot")
local SAimTab    = CombatModes:AddTab("Silent Aim")
local TrigTab    = CombatModes:AddTab("Triggerbot")
local GunTab     = CombatModes:AddTab("Gun Mods")

-- ---- Aimbot sub-tab ----
AimTab:AddToggle("AimEn", {Text = "Enabled", Default = false, Callback = function(v) S.Aimbot.Enabled = v end})
AimTab:AddToggle("AimShowFov", {Text = "Show FOV Circle", Default = true, Callback = function(v) S.Aimbot.ShowFOV = v end})
AimTab:AddSlider("AimFov", {Text = "FOV", Default = 100, Min = 30, Max = 500, Rounding = 0, Suffix = "px", Callback = function(v) S.Aimbot.FOV = v end})
AimTab:AddSlider("AimSmooth", {Text = "Smoothness (1=Snappy, 20=Smooth)", Default = 5, Min = 1, Max = 20, Rounding = 0, Callback = function(v) S.Aimbot.Smoothness = v end})
AimTab:AddSlider("AimPredictX", {Text = "Prediction X/Z", Default = 0.15, Min = 0, Max = 1, Rounding = 2, Callback = function(v) S.Aimbot.PredictX = v end})
AimTab:AddSlider("AimPredictY", {Text = "Prediction Y", Default = 0.15, Min = 0, Max = 1, Rounding = 2, Callback = function(v) S.Aimbot.PredictY = v end})
AimTab:AddToggle("AimResolver", {Text = "Hitbox Resolver (Desync Fix)", Default = true,
    Tooltip = "Clamps extreme velocities to prevent aimbot breaking on anti-aim",
    Callback = function(v) S.Aimbot.Resolver = v end})
AimTab:AddDropdown("AimPart", {Text = "Target Part", Values = {"Head", "UpperTorso", "HumanoidRootPart", "Torso"}, Default = "HumanoidRootPart", Multi = false, Callback = function(v) S.Aimbot.TargetPart = v end})
AimTab:AddToggle("AimTeam", {Text = "Team Check", Default = true, Callback = function(v) S.Aimbot.TeamCheck = v end})
AimTab:AddToggle("AimWall", {Text = "Wall Check", Default = false, Callback = function(v) S.Aimbot.WallCheck = v end})
AimTab:AddLabel("Aim Key"):AddKeyPicker("AimKey", {Default = "MB2", SyncToggleState = false, Mode = "Hold", Text = "Aim Key"})

-- ---- Silent Aim sub-tab ----
SAimTab:AddToggle("SAEn", {Text = "Enabled", Default = false, Callback = function(v) S.SilentAim.Enabled = v end})
SAimTab:AddToggle("SAShow", {Text = "Show FOV Circle", Default = false, Callback = function(v) S.SilentAim.ShowFOV = v end})
    :AddColorPicker("SAColor", {Default = S.SilentAim.FOVColor, Title = "FOV Color", Callback = function(v) if v then S.SilentAim.FOVColor = v end end})
SAimTab:AddSlider("SAFOV", {Text = "FOV", Default = 200, Min = 50, Max = 1000, Rounding = 0, Suffix = "px", Callback = function(v) S.SilentAim.FOV = v end})
SAimTab:AddSlider("SAChance", {Text = "Hit Chance", Default = 100, Min = 1, Max = 100, Rounding = 0, Suffix = "%", Callback = function(v) S.SilentAim.HitChance = v end})
SAimTab:AddSlider("SADist", {Text = "Max Distance", Default = 1000, Min = 100, Max = 5000, Rounding = 0, Callback = function(v) S.SilentAim.MaxDistance = v end})
SAimTab:AddDropdown("SAMethod", {
    Text = "Aim Method", Values = {"ViewportSize", "Raycast", "Both"}, Default = "ViewportSize", Multi = false,
    Tooltip = "ViewportSize = Rivals default (UI shifts slightly)\nRaycast = Bullets curve, UI doesn't shift",
    Callback = function(v) S.SilentAim.Method = v end
})
SAimTab:AddDropdown("SAPart", {Text = "Target Part", Values = {"Head", "UpperTorso", "HumanoidRootPart", "Torso"}, Default = "Head", Multi = false, Callback = function(v) S.SilentAim.TargetPart = v end})
SAimTab:AddToggle("SATeam", {Text = "Team Check", Default = true, Callback = function(v) S.SilentAim.TeamCheck = v end})
SAimTab:AddToggle("SAAlive", {Text = "Alive Check", Default = true, Callback = function(v) S.SilentAim.AliveCheck = v end})

-- ---- Triggerbot sub-tab ----
TrigTab:AddToggle("TrigEn", {Text = "Enabled", Default = false, Callback = function(v) S.Trigger.Enabled = v end})
TrigTab:AddSlider("TrigDelay", {Text = "Fire Delay (ms)", Default = 50, Min = 0, Max = 500, Rounding = 0, Callback = function(v) S.Trigger.Delay = v end})
TrigTab:AddSlider("TrigCooldown", {Text = "Time Between Shots (ms)", Default = 100, Min = 50, Max = 1000, Rounding = 0, Callback = function(v) S.Trigger.FireDelay = v end})
TrigTab:AddSlider("TrigDist", {Text = "Max Distance", Default = 1000, Min = 100, Max = 5000, Rounding = 0, Callback = function(v) S.Trigger.MaxDistance = v end})
TrigTab:AddToggle("TrigTeam", {Text = "Team Check", Default = true, Callback = function(v) S.Trigger.TeamCheck = v end})
TrigTab:AddToggle("TrigAlive", {Text = "Alive Check", Default = true, Callback = function(v) S.Trigger.AliveCheck = v end})

-- ---- Gun Mods sub-tab ----
GunTab:AddToggle("GunModsRecoil", {Text = "No Spread / Recoil", Default = false,
    Tooltip = "Zeros spread/recoil. Restores original on toggle off.",
    Callback = function(v) S.GunMods.NoRecoil = v; updateGunMods() end})
GunTab:AddToggle("GunModsFire", {Text = "Fast Fire Rate", Default = false,
    Tooltip = "Sets cooldown to 0.05s. Detectable by server. Restores on toggle off.",
    Callback = function(v) S.GunMods.FastFire = v; updateGunMods() end})
GunTab:AddDivider()
GunTab:AddButton({Text = "Re-apply Gun Mods Now", Func = function()
    updateGunMods(); Library:Notify("Gun Mods re-applied", 1.5)
end})
GunTab:AddLabel("Gun mods modify the client-side ItemLibrary so equipped weapons inherit your tweaks instantly.")

pcall(function() Options.SAColor:SetValueRGB(S.SilentAim.FOVColor) end)

-- =============== VISUALS TAB ===============
local ESPLeft = Tabs.Visuals:AddLeftGroupbox("ESP Core")
local ESPRight = Tabs.Visuals:AddRightGroupbox("ESP Elements")

ESPLeft:AddToggle("ESPEn", {Text = "Enabled", Default = false, Callback = function(v) S.ESP.Enabled = v end})
ESPLeft:AddToggle("ESPTeam", {Text = "Team Check", Default = true, Callback = function(v) S.ESP.TeamCheck = v end})
ESPLeft:AddSlider("ESPDist", {Text = "Max Distance", Default = 5000, Min = 100, Max = 10000, Rounding = 0, Callback = function(v) S.ESP.MaxDistance = v end})
ESPLeft:AddSlider("ESPRate", {Text = "Update Rate", Default = 60, Min = 15, Max = 60, Rounding = 0, Suffix = " Hz", Callback = function(v) S.ESP.UpdateRate = v end})

ESPRight:AddToggle("ESPBox", {Text = "Box", Default = true, Callback = function(v) S.ESP.Box = v end})
    :AddColorPicker("ESPBoxCol", {Default = S.ESP.BoxColor, Title = "Box Color", Callback = function(v) if v then S.ESP.BoxColor = v end end})
ESPRight:AddToggle("ESPName", {Text = "Name", Default = true, Callback = function(v) S.ESP.Name = v end})
    :AddColorPicker("ESPNameCol", {Default = S.ESP.NameColor, Title = "Name Color", Callback = function(v) if v then S.ESP.NameColor = v end end})
ESPRight:AddToggle("ESPDistance", {Text = "Distance", Default = true, Callback = function(v) S.ESP.Distance = v end})
    :AddColorPicker("ESPDistCol", {Default = S.ESP.DistanceColor, Title = "Distance Color", Callback = function(v) if v then S.ESP.DistanceColor = v end end})
ESPRight:AddToggle("ESPHP", {Text = "Health Bar (Reactive)", Default = true, Callback = function(v) S.ESP.HealthBar = v end})
ESPRight:AddToggle("ESPTracer", {Text = "Tracer", Default = false, Callback = function(v) S.ESP.Tracer = v end})
    :AddColorPicker("ESPTracerCol", {Default = S.ESP.TracerColor, Title = "Tracer Color", Callback = function(v) if v then S.ESP.TracerColor = v end end})
ESPRight:AddToggle("ESPChams", {Text = "Chams (Through Walls)", Default = false, Callback = function(v) S.ESP.Chams = v end})
    :AddColorPicker("ESPChamsCol", {Default = S.ESP.ChamsColor, Title = "Chams Color", Callback = function(v) if v then S.ESP.ChamsColor = v end end})

-- =============== MISC TAB ===============
local MiscLeft = Tabs.Misc:AddLeftGroupbox("Movement")
local MiscRight = Tabs.Misc:AddRightGroupbox("Visuals & Utilities")

MiscLeft:AddToggle("MiscFly", {Text = "Fly (Space/Ctrl for up/down)", Default = false, Callback = function(v) S.Misc.Fly = v end})
    :AddKeyPicker("FlyKey", {Default = "F", SyncToggleState = true, Mode = "Toggle", Text = "Fly Toggle"})
MiscLeft:AddSlider("MiscFlySpeed", {Text = "Fly Speed", Default = 50, Min = 10, Max = 200, Rounding = 0, Callback = function(v) S.Misc.FlySpeed = v end})
MiscLeft:AddToggle("MiscNoclip", {Text = "Noclip", Default = false, Callback = function(v) S.Misc.Noclip = v; applyNoclip(v) end})
MiscLeft:AddDivider()
MiscLeft:AddToggle("MiscWSEn", {Text = "Override WalkSpeed", Default = false, Callback = function(v) S.Misc.WalkSpeedEn = v; applyWS() end})
MiscLeft:AddSlider("MiscWS", {Text = "WalkSpeed", Default = 16, Min = 16, Max = 200, Rounding = 0,
    Callback = function(v) S.Misc.WalkSpeed = v; if S.Misc.WalkSpeedEn then applyWS() end end})
MiscLeft:AddToggle("MiscJPEn", {Text = "Override JumpPower", Default = false, Callback = function(v) S.Misc.JumpPowerEn = v; applyJP() end})
MiscLeft:AddSlider("MiscJP", {Text = "JumpPower", Default = 50, Min = 50, Max = 300, Rounding = 0,
    Callback = function(v) S.Misc.JumpPower = v; if S.Misc.JumpPowerEn then applyJP() end end})
MiscLeft:AddDivider()
MiscLeft:AddToggle("MiscInfJump", {Text = "Infinite Jump", Default = false, Callback = function(v) S.Misc.InfJump = v end})

MiscRight:AddToggle("MiscFB", {Text = "Fullbright", Default = false, Callback = function(v) S.Misc.Fullbright = v; applyFullbright(v) end})
MiscRight:AddToggle("MiscNoFog", {Text = "No Fog", Default = false, Callback = function(v) S.Misc.NoFog = v; applyNoFog(v) end})
MiscRight:AddToggle("MiscFOVEn", {Text = "Custom FOV", Default = false, Callback = function(v) S.Misc.CustomFOVEn = v end})
MiscRight:AddSlider("MiscFOV", {Text = "Field of View", Default = 90, Min = 70, Max = 120, Rounding = 0, Callback = function(v) S.Misc.CustomFOV = v end})
MiscRight:AddDivider()
MiscRight:AddButton({Text = "FPS Boost (one-shot)", Func = function()
    Lighting.GlobalShadows = false
    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
    for _, v in ipairsFn(workspace:GetDescendants()) do
        if v:IsA("BasePart") then v.Material = Enum.Material.Plastic; v.Reflectance = 0
        elseif v:IsA("Decal") or v:IsA("Texture") then pcall(function() v.Transparency = 1 end)
        elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Fire") or v:IsA("Smoke") or v:IsA("Sparkles") then
            pcall(function() v.Enabled = false end)
        end
    end
    Library:Notify("FPS Boost applied", 2)
end})
MiscRight:AddToggle("MiscAntiAFK", {Text = "Anti-AFK", Default = false, Callback = function(v) S.Misc.AntiAFK = v end})

-- =============== SKIN CHANGER (Rivals named skins) ===============
-- Discovery-based: probes every known Rivals asset path for skin models grouped by
-- weapon. Applies by replacing the live weapon ViewModel's children with the skin
-- ViewModel's children, with original-state caching for one-click Restore.
--
-- Searched paths (in priority order):
--   1) require(ReplicatedStorage.Modules.ItemLibrary).Items[Weapon].Skins[Name]
--   2) ReplicatedStorage.Skins / .WeaponSkins / .ToolSkins (flat or per-weapon)
--   3) PlayerScripts.Assets.Skins / .ViewModels.Skins (flat or per-weapon)
--   4) PlayerScripts.Assets.ViewModels.Weapons[Weapon].Skins[Name]
--   5) PlayerScripts.Assets.ViewModels.Weapons children treated as a flat skin/variant
--      list (Rivals often stores skins as standalone ViewModels next to the base)
local NamedSkinBox = Tabs.Misc:AddRightGroupbox("Skin Changer (Rivals)")

local SkinsByWeapon = {}          -- weapon -> { skinName -> { kind, src } }
local SkinOriginalChildren = {}   -- targetInstance -> { clonedOriginals... }

local function rivalsPS()  return LocalPlayer:FindFirstChild("PlayerScripts") end
local function rivalsAssets()
    local ps = rivalsPS()
    return ps and ps:FindFirstChild("Assets") or nil
end
local function rivalsViewModels()
    local a = rivalsAssets()
    return a and a:FindFirstChild("ViewModels") or nil
end
local function rivalsWeapons()
    local vm = rivalsViewModels()
    return vm and vm:FindFirstChild("Weapons") or nil
end

local function addSkin(weapon, name, kind, src)
    if not weapon or not name then return end
    SkinsByWeapon[weapon] = SkinsByWeapon[weapon] or {}
    if SkinsByWeapon[weapon][name] then return end
    SkinsByWeapon[weapon][name] = {kind = kind, src = src}
end

local function discoverRivalsSkins()
    SkinsByWeapon = {}

    -- (1) ItemLibrary
    pcall(function()
        local mods = ReplicatedStorage:FindFirstChild("Modules")
        local lib = mods and mods:FindFirstChild("ItemLibrary")
        if not lib then return end
        local ok, ItemLib = pcall(require, lib); if not ok then return end
        if not ItemLib or not ItemLib.Items then return end
        for itemName, data in pairsFn(ItemLib.Items) do
            if type(data) == "table" and type(data.Skins) == "table" then
                for skinName, skinData in pairsFn(data.Skins) do
                    addSkin(itemName, tostring(skinName), "itemlib", {weapon = itemName, name = skinName, data = skinData})
                end
            end
        end
    end)

    -- (2) ReplicatedStorage.Skins / WeaponSkins / ToolSkins
    local function scanLevel(root, defaultWeapon)
        if not root then return end
        for _, child in ipairsFn(root:GetChildren()) do
            if child:IsA("Folder") or child:IsA("Model") or child:IsA("Configuration") then
                if #child:GetChildren() > 0 then
                    -- Treat child.Name as weapon, its children as skins
                    local treatedAsWeapon = false
                    for _, sub in ipairsFn(child:GetChildren()) do
                        if sub:IsA("Folder") or sub:IsA("Model") or sub:IsA("Tool") or sub:IsA("BasePart") then
                            addSkin(child.Name, sub.Name, "model", sub)
                            treatedAsWeapon = true
                        end
                    end
                    if not treatedAsWeapon then
                        addSkin(defaultWeapon or "All Weapons", child.Name, "model", child)
                    end
                else
                    addSkin(defaultWeapon or "All Weapons", child.Name, "model", child)
                end
            end
        end
    end
    scanLevel(ReplicatedStorage:FindFirstChild("Skins"))
    scanLevel(ReplicatedStorage:FindFirstChild("WeaponSkins"))
    scanLevel(ReplicatedStorage:FindFirstChild("ToolSkins"))

    -- (3) PlayerScripts.Assets.Skins / .ViewModels.Skins
    local assets = rivalsAssets()
    if assets then
        scanLevel(assets:FindFirstChild("Skins"))
    end
    local vm = rivalsViewModels()
    if vm then
        scanLevel(vm:FindFirstChild("Skins"))
    end

    -- (4) Per-weapon nested .Skins folders inside each weapon ViewModel
    local weps = rivalsWeapons()
    if weps then
        for _, weapon in ipairsFn(weps:GetChildren()) do
            local sub = weapon:FindFirstChild("Skins")
            if sub then
                for _, skin in ipairsFn(sub:GetChildren()) do
                    addSkin(weapon.Name, skin.Name, "viewmodel", skin)
                end
            end
        end

        -- (5) Flat ViewModels.Weapons list -- in Rivals, every weapon AND skin variant
        --     often lives here as a sibling. We expose them as "All ViewModels" so
        --     the user can pick e.g. "AK47" and slam it onto "AssaultRifle".
        for _, weapon in ipairsFn(weps:GetChildren()) do
            addSkin("All ViewModels", weapon.Name, "viewmodel", weapon)
        end
    end
end

local function weaponList()
    local out = {}
    for k in pairsFn(SkinsByWeapon) do table.insert(out, k) end
    table.sort(out)
    if #out == 0 then out = {"<no skins detected -- click Discover>"} end
    return out
end
local function skinList(weapon)
    local out = {}
    local set = SkinsByWeapon[weapon]
    if set then
        for k in pairsFn(set) do table.insert(out, k) end
        table.sort(out)
    end
    if #out == 0 then out = {"<none>"} end
    return out
end

discoverRivalsSkins()

local SkinSel = { Weapon = weaponList()[1], Skin = nil, AutoReapply = false, TargetOverride = "" }
SkinSel.Skin = skinList(SkinSel.Weapon)[1]

NamedSkinBox:AddDropdown("CWSkinWeapon", {
    Text = "Weapon", Values = weaponList(), Default = 1, Multi = false,
    Tooltip = "Source weapon -- skins listed below apply to whatever weapon you select in 'Apply To'.",
    Callback = function(v)
        SkinSel.Weapon = v
        pcall(function() Options.CWSkinName:SetValues(skinList(v)) end)
        local first = skinList(v)[1]
        pcall(function() Options.CWSkinName:SetValue(first) end)
        SkinSel.Skin = first
    end
})
NamedSkinBox:AddDropdown("CWSkinName", {
    Text = "Skin", Values = skinList(SkinSel.Weapon), Default = 1, Multi = false,
    Callback = function(v) SkinSel.Skin = v end
})
NamedSkinBox:AddDropdown("CWSkinTarget", {
    Text = "Apply To", Values = (function()
        local weps = rivalsWeapons()
        if not weps then return {"<weapons not loaded>"} end
        local out = {}
        for _, w in ipairsFn(weps:GetChildren()) do table.insert(out, w.Name) end
        table.sort(out)
        if #out == 0 then out = {"<weapons not loaded>"} end
        return out
    end)(),
    Default = 1, Multi = false,
    Tooltip = "Which live ViewModel in PlayerScripts.Assets.ViewModels.Weapons to overwrite.",
    Callback = function(v) SkinSel.TargetOverride = v end
})

local function resolveSource(weapon, skinName)
    local set = SkinsByWeapon[weapon]
    local entry = set and set[skinName]
    if not entry then return nil end
    if entry.kind == "model" or entry.kind == "viewmodel" then
        return entry.src
    elseif entry.kind == "itemlib" then
        -- ItemLibrary entries are pure data -- if data table has a Model/Asset
        -- attribute we'll deref it; otherwise we can't visually swap.
        local d = entry.src and entry.src.data
        if type(d) == "table" then
            return d.Model or d.Asset or d.ViewModel or nil
        end
    end
    return nil
end

local function cacheOriginal(target)
    if SkinOriginalChildren[target] then return end
    local kids = {}
    for _, c in ipairsFn(target:GetChildren()) do
        local ok, clone = pcall(function() return c:Clone() end)
        if ok and clone then table.insert(kids, clone) end
    end
    SkinOriginalChildren[target] = kids
end

local function applyNamedSkin()
    local weps = rivalsWeapons()
    if not weps then Library:Notify("ViewModels not loaded -- play a round first", 2); return end
    local target = weps:FindFirstChild(SkinSel.TargetOverride or "")
    if not target then Library:Notify("Target weapon not found in ViewModels", 2); return end
    local src = resolveSource(SkinSel.Weapon, SkinSel.Skin)
    if not src then
        Library:Notify("Skin source has no instance data (try a different skin)", 2); return
    end

    cacheOriginal(target)

    -- Wipe target's current children, then clone source's children in.
    for _, c in ipairsFn(target:GetChildren()) do pcall(function() c:Destroy() end) end
    for _, c in ipairsFn(src:GetChildren()) do
        local ok, clone = pcall(function() return c:Clone() end)
        if ok and clone then clone.Parent = target end
    end
    -- Tag the target so we can detect/restore later
    target:SetAttribute("CheatwareSkinApplied", tostring(SkinSel.Skin))
    Library:Notify("Applied skin: " .. SkinSel.Skin .. " -> " .. target.Name, 2)
end

local function restoreSkin()
    local weps = rivalsWeapons()
    if not weps then return end
    local target = weps:FindFirstChild(SkinSel.TargetOverride or "")
    if not target then Library:Notify("Target weapon not found", 2); return end
    local kids = SkinOriginalChildren[target]
    if not kids or #kids == 0 then Library:Notify("Nothing cached to restore", 2); return end
    for _, c in ipairsFn(target:GetChildren()) do pcall(function() c:Destroy() end) end
    for _, c in ipairsFn(kids) do
        local ok, clone = pcall(function() return c:Clone() end)
        if ok and clone then clone.Parent = target end
    end
    target:SetAttribute("CheatwareSkinApplied", nil)
    Library:Notify("Restored " .. target.Name, 2)
end

NamedSkinBox:AddDivider()
NamedSkinBox:AddButton({Text = "Discover Skins", Func = function()
    discoverRivalsSkins()
    pcall(function() Options.CWSkinWeapon:SetValues(weaponList()) end)
    pcall(function() Options.CWSkinName:SetValues(skinList(SkinSel.Weapon)) end)
    local weps = rivalsWeapons()
    if weps then
        local list = {}
        for _, w in ipairsFn(weps:GetChildren()) do table.insert(list, w.Name) end
        table.sort(list)
        pcall(function() Options.CWSkinTarget:SetValues(list) end)
    end
    local total = 0
    for _, set in pairsFn(SkinsByWeapon) do for _ in pairsFn(set) do total = total + 1 end end
    Library:Notify("Discovered " .. total .. " skin entries", 2)
end})
NamedSkinBox:AddButton({Text = "Apply Skin",       Func = applyNamedSkin})
NamedSkinBox:AddButton({Text = "Restore Original", Func = restoreSkin})
NamedSkinBox:AddToggle("CWSkinAutoReapply", {
    Text = "Auto Re-apply on Equip", Default = false,
    Tooltip = "Re-applies the chosen skin to the target whenever the ViewModel gets replaced (respawn / map change).",
    Callback = function(v) SkinSel.AutoReapply = v end
})

-- Auto re-apply on DescendantAdded inside ViewModels.Weapons. Throttled by
-- target attribute so we only fire when the target weapon repopulates.
do
    local weps = rivalsWeapons()
    if weps then
        weps.ChildAdded:Connect(function(w)
            task.wait(0.1)
            if SkinSel.AutoReapply and w.Name == SkinSel.TargetOverride then
                applyNamedSkin()
            end
        end)
        for _, w in ipairsFn(weps:GetChildren()) do
            w.ChildAdded:Connect(function()
                if SkinSel.AutoReapply and w.Name == SkinSel.TargetOverride
                   and w:GetAttribute("CheatwareSkinApplied") == nil then
                    task.wait(0.1); applyNamedSkin()
                end
            end)
        end
    end
end

-- =============== WRAP & COLOR EDITOR (toast RTC port) ===============
-- Lower-level paint editor for when the named-skin swap doesn't cover what you need.
-- Walks every BasePart of the chosen weapon ViewModel and applies Color, Material,
-- Transparency, Reflectance, plus optional wrap-texture or MaterialVariant injection
-- from PlayerScripts.Assets.WrapTextures and MaterialService.Wraps.
local SkinBox = Tabs.Misc:AddRightGroupbox("Wrap & Color Editor")

local function safeGet(parent, ...)
    local node = parent
    for _, name in ipairsFn({...}) do
        if not node then return nil end
        node = node:FindFirstChild(name)
    end
    return node
end

local function buildSkinSources()
    local ps = LocalPlayer:FindFirstChild("PlayerScripts")
    local weaponsFolder  = safeGet(ps, "Assets", "ViewModels", "Weapons")
    local wrapsFolder    = safeGet(ps, "Assets", "WrapTextures")
    local matService     = game:GetService("MaterialService")
    local wrapMatsFolder = matService and matService:FindFirstChild("Wraps")

    local weapons       = weaponsFolder and weaponsFolder:GetChildren() or {}
    local wraps         = wrapsFolder and wrapsFolder:GetChildren() or {}
    local wrapMats      = wrapMatsFolder and wrapMatsFolder:GetChildren() or {}

    local wn, wrapMatNames, wrapTextureNames, wrapVariantList, filteredWraps = {}, {}, {}, {}, {}
    for _, v in ipairsFn(weapons) do table.insert(wn, v.Name) end
    table.sort(wn)
    for _, v in ipairsFn(wraps) do wrapTextureNames[v.Name] = true end
    for _, v in ipairsFn(wrapMats) do
        wrapMatNames[v.Name] = v
        if not wrapTextureNames[v.Name] then table.insert(wrapVariantList, v.Name) end
    end
    table.sort(wrapVariantList)
    for _, v in ipairsFn(wraps) do
        if not wrapMatNames[v.Name] then table.insert(filteredWraps, v.Name) end
    end
    table.sort(filteredWraps)

    local materials = {}
    for _, m in ipairsFn(Enum.Material:GetEnumItems()) do table.insert(materials, m.Name) end
    table.sort(materials)

    return weapons, wraps, wrapMatNames, filteredWraps, wrapVariantList, wn, materials
end

local SkinWeapons, SkinWraps, SkinWrapMats, SkinTexList, SkinVariantList, SkinWeaponNames, SkinMaterials = buildSkinSources()

if #SkinWeaponNames == 0 then SkinWeaponNames = {"<load a match first>"} end
if #SkinTexList     == 0 then SkinTexList     = {"<none>"} end
if #SkinVariantList == 0 then SkinVariantList = {"<none>"} end

S.Skin.Weapon      = SkinWeaponNames[1]
S.Skin.WrapTex     = SkinTexList[1]
S.Skin.WrapVariant = SkinVariantList[1]

SkinBox:AddDropdown("SkinWeapon", {
    Text = "Weapon", Values = SkinWeaponNames, Default = 1, Multi = false,
    Callback = function(v) S.Skin.Weapon = v end
})
SkinBox:AddDropdown("SkinWrapTex", {
    Text = "Wrap Texture", Values = SkinTexList, Default = 1, Multi = false,
    Tooltip = "Classic decal/texture/SurfaceAppearance wraps cloned onto every part.",
    Callback = function(v)
        S.Skin.WrapTex = v
        if v and SkinWrapMats[v] then
            pcall(function() Options.SkinWrapVariant:SetValue(v) end)
            pcall(function() Toggles.SkinUseWrapMat:SetValue(true) end)
        end
    end
})
SkinBox:AddDropdown("SkinWrapVariant", {
    Text = "Wrap Material Variant", Values = SkinVariantList, Default = 1, Multi = false,
    Tooltip = "Newer MaterialVariant-style wraps. Requires base material set to Fabric.",
    Callback = function(v) S.Skin.WrapVariant = v end
})
SkinBox:AddDropdown("SkinBaseMat", {
    Text = "Base Material", Values = SkinMaterials, Default = table.find(SkinMaterials, "SmoothPlastic") or 1, Multi = false,
    Callback = function(v) S.Skin.Material = v end
})
SkinBox:AddToggle("SkinUseColor",       {Text = "Apply Color",         Default = false, Callback = function(v) S.Skin.UseColor = v end})
    :AddColorPicker("SkinColor", {Default = S.Skin.Color, Title = "Weapon Color",
        Callback = function(v) if v then S.Skin.Color = v end end})
SkinBox:AddToggle("SkinUseMaterial",    {Text = "Apply Base Material", Default = false, Callback = function(v) S.Skin.UseMaterial = v end})
SkinBox:AddToggle("SkinUseTransparency",{Text = "Apply Transparency",  Default = false, Callback = function(v) S.Skin.UseTransparency = v end})
SkinBox:AddSlider("SkinTransparency", {Text = "Transparency", Default = 0, Min = 0, Max = 1, Rounding = 2,
    Callback = function(v) S.Skin.Transparency = v end})
SkinBox:AddSlider("SkinReflectance",  {Text = "Reflectance",  Default = 0, Min = 0, Max = 1, Rounding = 2,
    Callback = function(v) S.Skin.Reflectance = v end})
SkinBox:AddToggle("SkinUseWrap",    {Text = "Apply Wrap Texture",  Default = false, Callback = function(v) S.Skin.UseWrap = v end})
SkinBox:AddToggle("SkinUseWrapMat", {Text = "Use Wrap Material",   Default = false, Callback = function(v) S.Skin.UseWrapMat = v end})
SkinBox:AddDivider()
SkinBox:AddToggle("SkinApplyAll",    {Text = "Apply To All Weapons", Default = false, Callback = function(v) S.Skin.ApplyAll = v end})
SkinBox:AddToggle("SkinAutoReapply", {Text = "Auto Reapply On Equip", Default = false, Callback = function(v) S.Skin.AutoReapply = v end})

local function applyToPart(d)
    if not d:IsA("BasePart") or d.Transparency == 1 then return end
    if S.Skin.UseColor then d.Color = S.Skin.Color end
    if S.Skin.UseTransparency then d.Transparency = S.Skin.Transparency end
    d.Reflectance = S.Skin.Reflectance

    local matVariant = SkinWrapMats[S.Skin.WrapVariant]
    if not matVariant and SkinWrapMats[S.Skin.WrapTex] then matVariant = SkinWrapMats[S.Skin.WrapTex] end

    if S.Skin.UseWrapMat and matVariant then
        d.Material = Enum.Material.Fabric
        pcall(function() d.MaterialVariant = matVariant.Name end)
        for _, t in ipairsFn(d:GetChildren()) do
            if t:IsA("Texture") or t:IsA("Decal") or t:IsA("SurfaceAppearance") then t:Destroy() end
        end
    else
        if S.Skin.UseMaterial then
            local ok, enumVal = pcall(function() return Enum.Material[S.Skin.Material] end)
            if ok and enumVal then d.Material = enumVal end
        end
        pcall(function() d.MaterialVariant = "" end)

        if S.Skin.UseWrap and S.Skin.WrapTex then
            for _, t in ipairsFn(d:GetChildren()) do
                if t:IsA("Texture") or t:IsA("Decal") or t:IsA("SurfaceAppearance") then t:Destroy() end
            end
            for _, w in ipairsFn(SkinWraps) do
                if w.Name == S.Skin.WrapTex then
                    for _, c in ipairsFn(w:GetChildren()) do
                        if c:IsA("Decal") or c:IsA("Texture") or c:IsA("SurfaceAppearance") then
                            local clone = c:Clone(); clone.Parent = d
                        end
                    end
                    break
                end
            end
        end
    end
end

local function pickTargets()
    local out = {}
    if S.Skin.ApplyAll then
        for _, v in ipairsFn(SkinWeapons) do table.insert(out, v) end
    else
        for _, v in ipairsFn(SkinWeapons) do
            if v.Name == S.Skin.Weapon then table.insert(out, v) end
        end
    end
    return out
end

local function applySkin()
    SkinWeapons, SkinWraps, SkinWrapMats = (function()
        local a,b,c = buildSkinSources(); return a,b,c
    end)()
    local targets = pickTargets()
    if #targets == 0 then Library:Notify("Wrap Editor: no matching weapon", 2); return end
    for _, v in ipairsFn(targets) do
        for _, d in ipairsFn(v:GetDescendants()) do applyToPart(d) end
    end
    Library:Notify("Wrap applied to " .. #targets .. " weapon(s)", 1.5)
end

local function resetSkin()
    local targets = pickTargets()
    for _, v in ipairsFn(targets) do
        for _, d in ipairsFn(v:GetDescendants()) do
            if d:IsA("BasePart") then
                d.Material = Enum.Material.SmoothPlastic
                pcall(function() d.MaterialVariant = "" end)
                d.Reflectance = 0
                for _, t in ipairsFn(d:GetChildren()) do
                    if t:IsA("Decal") or t:IsA("Texture") or t:IsA("SurfaceAppearance") then t:Destroy() end
                end
            end
        end
    end
    Library:Notify("Wrap reset on " .. #targets .. " weapon(s)", 1.5)
end

SkinBox:AddButton({Text = "Apply Wrap",   Func = applySkin})
SkinBox:AddButton({Text = "Reset Weapon", Func = resetSkin})
SkinBox:AddButton({Text = "Randomize",    Func = function()
    pcall(function() Options.SkinColor:SetValueRGB(Color3.fromRGB(mathRandom(0,255), mathRandom(0,255), mathRandom(0,255))) end)
    pcall(function() Options.SkinReflectance:SetValue(mathRandom() ) end)
    if #SkinMaterials   > 0 then pcall(function() Options.SkinBaseMat:SetValue(SkinMaterials[mathRandom(#SkinMaterials)]) end) end
    if #SkinTexList     > 0 then pcall(function() Options.SkinWrapTex:SetValue(SkinTexList[mathRandom(#SkinTexList)]) end) end
    if #SkinVariantList > 0 then pcall(function() Options.SkinWrapVariant:SetValue(SkinVariantList[mathRandom(#SkinVariantList)]) end) end
    applySkin()
end})
SkinBox:AddButton({Text = "Refresh Asset Lists", Func = function()
    local _, _, _, tex, vari, weps, _ = buildSkinSources()
    pcall(function() Options.SkinWeapon:SetValues(weps) end)
    pcall(function() Options.SkinWrapTex:SetValues(tex) end)
    pcall(function() Options.SkinWrapVariant:SetValues(vari) end)
    Library:Notify("Wrap Editor: asset lists refreshed", 1.5)
end})

local ps = LocalPlayer:FindFirstChild("PlayerScripts")
local weaponsFolder = safeGet(ps, "Assets", "ViewModels", "Weapons")
if weaponsFolder then
    weaponsFolder.DescendantAdded:Connect(function(d)
        if not S.Skin.AutoReapply then return end
        if not d:IsA("BasePart") then return end
        local wep = d
        while wep and wep.Parent ~= weaponsFolder do wep = wep.Parent end
        if not wep then return end
        if not S.Skin.ApplyAll and wep.Name ~= S.Skin.Weapon then return end
        task.defer(applyToPart, d)
    end)
end

pcall(function() Options.SkinColor:SetValueRGB(S.Skin.Color) end)

-- =============== SETTINGS TAB ===============

local function safeGet(parent, ...)
    local node = parent
    for _, name in ipairsFn({...}) do
        if not node then return nil end
        node = node:FindFirstChild(name)
    end
    return node
end

local function buildSkinSources()
    local ps = LocalPlayer:FindFirstChild("PlayerScripts")
    local weaponsFolder  = safeGet(ps, "Assets", "ViewModels", "Weapons")
    local wrapsFolder    = safeGet(ps, "Assets", "WrapTextures")
    local matService     = game:GetService("MaterialService")
    local wrapMatsFolder = matService and matService:FindFirstChild("Wraps")

    local weapons       = weaponsFolder and weaponsFolder:GetChildren() or {}
    local wraps         = wrapsFolder and wrapsFolder:GetChildren() or {}
    local wrapMats      = wrapMatsFolder and wrapMatsFolder:GetChildren() or {}

    local wn, wrapMatNames, wrapTextureNames, wrapVariantList, filteredWraps = {}, {}, {}, {}, {}
    for _, v in ipairsFn(weapons) do table.insert(wn, v.Name) end
    table.sort(wn)
    for _, v in ipairsFn(wraps) do wrapTextureNames[v.Name] = true end
    for _, v in ipairsFn(wrapMats) do
        wrapMatNames[v.Name] = v
        if not wrapTextureNames[v.Name] then table.insert(wrapVariantList, v.Name) end
    end
    table.sort(wrapVariantList)
    for _, v in ipairsFn(wraps) do
        if not wrapMatNames[v.Name] then table.insert(filteredWraps, v.Name) end
    end
    table.sort(filteredWraps)

    local materials = {}
    for _, m in ipairsFn(Enum.Material:GetEnumItems()) do table.insert(materials, m.Name) end
    table.sort(materials)

    return weapons, wraps, wrapMatNames, filteredWraps, wrapVariantList, wn, materials
end

local SkinWeapons, SkinWraps, SkinWrapMats, SkinTexList, SkinVariantList, SkinWeaponNames, SkinMaterials = buildSkinSources()

-- Defensive defaults if the player joined before assets streamed
if #SkinWeaponNames == 0 then SkinWeaponNames = {"<load a match first>"} end
if #SkinTexList     == 0 then SkinTexList     = {"<none>"} end
if #SkinVariantList == 0 then SkinVariantList = {"<none>"} end

S.Skin.Weapon      = SkinWeaponNames[1]
S.Skin.WrapTex     = SkinTexList[1]
S.Skin.WrapVariant = SkinVariantList[1]

SkinBox:AddDropdown("SkinWeapon", {
    Text = "Weapon", Values = SkinWeaponNames, Default = 1, Multi = false,
    Callback = function(v) S.Skin.Weapon = v end
})
SkinBox:AddDropdown("SkinWrapTex", {
    Text = "Wrap Texture", Values = SkinTexList, Default = 1, Multi = false,
    Tooltip = "Classic decal/texture/SurfaceAppearance wraps cloned onto every part.",
    Callback = function(v)
        S.Skin.WrapTex = v
        -- Mirror the upstream behavior: if the chosen texture also exists as a
        -- MaterialVariant, auto-select it and flip "Use Wrap Material" on.
        if v and SkinWrapMats[v] then
            pcall(function() Options.SkinWrapVariant:SetValue(v) end)
            pcall(function() Toggles.SkinUseWrapMat:SetValue(true) end)
        end
    end
})
SkinBox:AddDropdown("SkinWrapVariant", {
    Text = "Wrap Material Variant", Values = SkinVariantList, Default = 1, Multi = false,
    Tooltip = "Newer MaterialVariant-style wraps. Requires base material set to Fabric.",
    Callback = function(v) S.Skin.WrapVariant = v end
})
SkinBox:AddDropdown("SkinBaseMat", {
    Text = "Base Material", Values = SkinMaterials, Default = table.find(SkinMaterials, "SmoothPlastic") or 1, Multi = false,
    Callback = function(v) S.Skin.Material = v end
})
SkinBox:AddToggle("SkinUseColor",       {Text = "Apply Color",         Default = false, Callback = function(v) S.Skin.UseColor = v end})
    :AddColorPicker("SkinColor", {Default = S.Skin.Color, Title = "Weapon Color",
        Callback = function(v) if v then S.Skin.Color = v end end})
SkinBox:AddToggle("SkinUseMaterial",    {Text = "Apply Base Material", Default = false, Callback = function(v) S.Skin.UseMaterial = v end})
SkinBox:AddToggle("SkinUseTransparency",{Text = "Apply Transparency",  Default = false, Callback = function(v) S.Skin.UseTransparency = v end})
SkinBox:AddSlider("SkinTransparency", {Text = "Transparency", Default = 0, Min = 0, Max = 1, Rounding = 2,
    Callback = function(v) S.Skin.Transparency = v end})
SkinBox:AddSlider("SkinReflectance",  {Text = "Reflectance",  Default = 0, Min = 0, Max = 1, Rounding = 2,
    Callback = function(v) S.Skin.Reflectance = v end})
SkinBox:AddToggle("SkinUseWrap",    {Text = "Apply Wrap Texture",  Default = false, Callback = function(v) S.Skin.UseWrap = v end})
SkinBox:AddToggle("SkinUseWrapMat", {Text = "Use Wrap Material",   Default = false, Callback = function(v) S.Skin.UseWrapMat = v end})
SkinBox:AddDivider()
SkinBox:AddToggle("SkinApplyAll",    {Text = "Apply To All Weapons", Default = false, Callback = function(v) S.Skin.ApplyAll = v end})
SkinBox:AddToggle("SkinAutoReapply", {Text = "Auto Reapply On Equip", Default = false, Callback = function(v) S.Skin.AutoReapply = v end})

local function applyToPart(d)
    if not d:IsA("BasePart") or d.Transparency == 1 then return end
    if S.Skin.UseColor then d.Color = S.Skin.Color end
    if S.Skin.UseTransparency then d.Transparency = S.Skin.Transparency end
    d.Reflectance = S.Skin.Reflectance

    local matVariant = SkinWrapMats[S.Skin.WrapVariant]
    if not matVariant and SkinWrapMats[S.Skin.WrapTex] then matVariant = SkinWrapMats[S.Skin.WrapTex] end

    if S.Skin.UseWrapMat and matVariant then
        d.Material = Enum.Material.Fabric
        pcall(function() d.MaterialVariant = matVariant.Name end)
        for _, t in ipairsFn(d:GetChildren()) do
            if t:IsA("Texture") or t:IsA("Decal") or t:IsA("SurfaceAppearance") then t:Destroy() end
        end
    else
        if S.Skin.UseMaterial then
            local ok, enumVal = pcall(function() return Enum.Material[S.Skin.Material] end)
            if ok and enumVal then d.Material = enumVal end
        end
        pcall(function() d.MaterialVariant = "" end)

        if S.Skin.UseWrap and S.Skin.WrapTex then
            for _, t in ipairsFn(d:GetChildren()) do
                if t:IsA("Texture") or t:IsA("Decal") or t:IsA("SurfaceAppearance") then t:Destroy() end
            end
            for _, w in ipairsFn(SkinWraps) do
                if w.Name == S.Skin.WrapTex then
                    for _, c in ipairsFn(w:GetChildren()) do
                        if c:IsA("Decal") or c:IsA("Texture") or c:IsA("SurfaceAppearance") then
                            local clone = c:Clone(); clone.Parent = d
                        end
                    end
                    break
                end
            end
        end
    end
end

local function pickTargets()
    local out = {}
    if S.Skin.ApplyAll then
        for _, v in ipairsFn(SkinWeapons) do table.insert(out, v) end
    else
        for _, v in ipairsFn(SkinWeapons) do
            if v.Name == S.Skin.Weapon then table.insert(out, v) end
        end
    end
    return out
end

local function applySkin()
    SkinWeapons, SkinWraps, SkinWrapMats = (function()
        local a,b,c = buildSkinSources(); return a,b,c
    end)()
    local targets = pickTargets()
    if #targets == 0 then Library:Notify("Skin Changer: no matching weapon", 2); return end
    for _, v in ipairsFn(targets) do
        for _, d in ipairsFn(v:GetDescendants()) do applyToPart(d) end
    end
    Library:Notify("Skin applied to " .. #targets .. " weapon(s)", 1.5)
end

local function resetSkin()
    local targets = pickTargets()
    for _, v in ipairsFn(targets) do
        for _, d in ipairsFn(v:GetDescendants()) do
            if d:IsA("BasePart") then
                d.Material = Enum.Material.SmoothPlastic
                pcall(function() d.MaterialVariant = "" end)
                d.Reflectance = 0
                for _, t in ipairsFn(d:GetChildren()) do
                    if t:IsA("Decal") or t:IsA("Texture") or t:IsA("SurfaceAppearance") then t:Destroy() end
                end
            end
        end
    end
    Library:Notify("Skin reset on " .. #targets .. " weapon(s)", 1.5)
end

SkinBox:AddButton({Text = "Apply Skin",   Func = applySkin})
SkinBox:AddButton({Text = "Reset Weapon", Func = resetSkin})
SkinBox:AddButton({Text = "Randomize",    Func = function()
    pcall(function() Options.SkinColor:SetValueRGB(Color3.fromRGB(mathRandom(0,255), mathRandom(0,255), mathRandom(0,255))) end)
    pcall(function() Options.SkinReflectance:SetValue(mathRandom() ) end)
    if #SkinMaterials   > 0 then pcall(function() Options.SkinBaseMat:SetValue(SkinMaterials[mathRandom(#SkinMaterials)]) end) end
    if #SkinTexList     > 0 then pcall(function() Options.SkinWrapTex:SetValue(SkinTexList[mathRandom(#SkinTexList)]) end) end
    if #SkinVariantList > 0 then pcall(function() Options.SkinWrapVariant:SetValue(SkinVariantList[mathRandom(#SkinVariantList)]) end) end
    applySkin()
end})
SkinBox:AddButton({Text = "Refresh Asset Lists", Func = function()
    local _, _, _, tex, vari, weps, _ = buildSkinSources()
    pcall(function() Options.SkinWeapon:SetValues(weps) end)
    pcall(function() Options.SkinWrapTex:SetValues(tex) end)
    pcall(function() Options.SkinWrapVariant:SetValues(vari) end)
    Library:Notify("Skin Changer: asset lists refreshed", 1.5)
end})

-- Auto re-apply on descendant added (handles weapons streamed in after a respawn /
-- map change). Runs only when AutoReapply is enabled and the part belongs to a
-- weapon viewmodel that matches the current selection.
local ps = LocalPlayer:FindFirstChild("PlayerScripts")
local weaponsFolder = safeGet(ps, "Assets", "ViewModels", "Weapons")
if weaponsFolder then
    weaponsFolder.DescendantAdded:Connect(function(d)
        if not S.Skin.AutoReapply then return end
        if not d:IsA("BasePart") then return end
        local wep = d
        while wep and wep.Parent ~= weaponsFolder do wep = wep.Parent end
        if not wep then return end
        if not S.Skin.ApplyAll and wep.Name ~= S.Skin.Weapon then return end
        task.defer(applyToPart, d)
    end)
end

pcall(function() Options.SkinColor:SetValueRGB(S.Skin.Color) end)

-- =============== SETTINGS TAB ===============
local MenuGroup = Tabs.Settings:AddLeftGroupbox("Menu")
MenuGroup:AddLabel("Menu Bind"):AddKeyPicker("MenuKeybind", {Default = "RightShift", NoUI = true, Text = "Menu Keybind"})
MenuGroup:AddButton({Text = "Unload Script", Func = function() Library:Unload() end})
Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library); SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings(); SaveManager:SetIgnoreIndexes({"MenuKeybind"})
ThemeManager:SetFolder("Cheatware"); SaveManager:SetFolder("Cheatware/Configs")
SaveManager:BuildConfigSection(Tabs.Settings); ThemeManager:ApplyToTab(Tabs.Settings)
pcall(function() SaveManager:LoadAutoloadConfig() end)

-- ============================================================
-- v18: NAV BAR + COMBAT SUB-TAB LAYOUT (zero empty space, every resize)
-- ============================================================
-- Linoria layout reference (verified against Library.lua HEAD):
--   Window.Inner.Size  = (1, 0, 1, 0)                          -> Window - 2 (1 px border each side)
--   MainSectionOuter   = Position(0,8,0,25),  Size(1,-16,1,-33) -> Inner   - 16
--   MainSectionInner   = (1, 0, 1, 0)                          -> = MainSectionOuter
--   TabArea            = Position(0, 8-TabPadding, 0, 4), Size(1,-10,0,26)
--                                                              -> MainSectionInner - 10
--   TabArea has 2 zero-size sentinel Frames (LayoutOrder -1 and 9999999) flanking the
--   real tab buttons. UIListLayout.Padding = TabPadding, so layout consumes
--      N*B + (N+1)*TabPadding   (N=4 buttons, 5 gaps: leading sentinel..trailing sentinel)
--   The Position X shift of -TabPadding absorbs one gap visually, so the safe
--   pixel-perfect formula for one button is:
--      B = floor((TabArea.AbsoluteSize.X - (N+1)*TabPadding) / N) + NAV_PX_TWEAK
--
-- Combat outer Tab.Resize reference (Library.lua line 7445-7484, fires from line 7531
-- inside Tab:ShowTab on EVERY main-nav click). Without monkey-patching this, our
-- LeftSide.Size = (1, -14, 1, -14) full-width override gets reset back to
-- (0.5, -10, 1, -14) every time the user clicks away and returns to Combat.
--
-- Combat Tabbox reference (lines 7700-7820 of Library.lua):
--   TabboxButtons      = Size(1, 0, 0, 18) inside BoxInner
--   UIListLayout.Padding = 0 by default (no gap between sub-tab buttons)
--   Linoria's Tab:Resize() force-sets every sub-tab button to (1/N, 0, 1, 0) on EVERY
--   show/click. We raise UIListLayout.Padding to SUBTAB_GAP, then monkey-patch each
--   sub-tab's Resize so the post-reset re-application
--      Size = (1/N, -SUBTAB_GAP*(N-1)/N - SUBTAB_PX_SHRINK, 1, 0)
--   gets re-asserted. We also stretch BoxOuter to (1, 0, 1, 0) post-Resize so the
--   Tabbox extends down to fill the Combat tab height instead of hugging content.
do
    local TAB_PADDING     = 8       -- = WindowInfo.TabPadding (main nav gap)
    local NAV_PX_TWEAK    = 2       -- +2 px per nav button (user request)
    local SUBTAB_GAP      = 8       -- visual gap between Combat sub-tab buttons
    local SUBTAB_PX_SHRINK = 0.5    -- -0.5 px per sub-tab button (user request)

    local sample = Tabs.Combat and Tabs.Combat.LeftSideFrame
    if not sample then return end
    local mainInner = sample.Parent and sample.Parent.Parent and sample.Parent.Parent.Parent
    if not mainInner then return end

    -- =================================================================
    -- (1) MAIN NAV BAR -- dynamic perfect-fit sizing + 2 px tweak
    -- =================================================================
    local tabArea
    for _, c in ipairsFn(mainInner:GetChildren()) do
        if c:IsA("ScrollingFrame") then tabArea = c; break end
    end
    if tabArea then
        local function sizeNavButtons()
            local realButtons = {}
            for _, child in ipairsFn(tabArea:GetChildren()) do
                if child:IsA("Frame") and child:FindFirstChildWhichIsA("TextLabel") then
                    table.insert(realButtons, child)
                end
            end
            local n = #realButtons
            if n == 0 then return end
            local width = tabArea.AbsoluteSize.X
            if width <= 0 then return end
            local per = math.floor((width - (n + 1) * TAB_PADDING) / n) + NAV_PX_TWEAK
            if per < 40 then per = 40 end
            for _, b in ipairsFn(realButtons) do
                b.Size = UDim2.new(0, per, 0.85, 0)
            end
        end
        task.defer(sizeNavButtons)
        task.delay(0.05, sizeNavButtons)
        tabArea:GetPropertyChangedSignal("AbsoluteSize"):Connect(sizeNavButtons)
    end

    -- =================================================================
    -- (2) COMBAT OUTER Tab.Resize MONKEY-PATCH (fixes the regression)
    --     This is the v17 -> v18 bug fix: switching away from Combat and back
    --     caused Linoria's Tab:Resize (called from Tab:ShowTab on every reveal)
    --     to reset LeftSide.Size to (0.5, -10, 1, -14). We wrap Tabs.Combat.Resize
    --     so our full-width override is re-applied AFTER Linoria's reset, every time.
    -- =================================================================
    local origCombatResize = Tabs.Combat.Resize
    local function applyCombatFullWidth()
        local ls = Tabs.Combat.LeftSideFrame
        local rs = Tabs.Combat.RightSideFrame
        if ls then
            ls.Position = UDim2.new(0, 7, 0, 7)
            ls.Size     = UDim2.new(1, -14, 1, -14)
        end
        if rs then
            rs.Visible = false
        end
    end
    if origCombatResize then
        Tabs.Combat.Resize = function(self)
            origCombatResize(self)
            applyCombatFullWidth()
        end
    end
    applyCombatFullWidth()
    task.defer(applyCombatFullWidth)
    task.delay(0.05, applyCombatFullWidth)

    -- =================================================================
    -- (3) COMBAT SUB-TABS -- gap-aware sizing that survives every internal resize
    --     Plus BoxOuter stretched to full height so the sub-tab content area
    --     extends all the way down inside the Combat tab.
    -- =================================================================
    local subTabs = {AimTab, SAimTab, TrigTab, GunTab}
    local refContainer = AimTab and AimTab.Container
    if refContainer then
        local boxInner = refContainer.Parent       -- BoxInner
        local boxOuter = boxInner and boxInner.Parent  -- BoxOuter
        local tabboxButtons
        if boxInner then
            for _, c in ipairsFn(boxInner:GetChildren()) do
                if c:IsA("Frame") and c:FindFirstChildOfClass("UIListLayout")
                   and c.Size.Y.Offset == 18 then
                    tabboxButtons = c; break
                end
            end
        end

        if tabboxButtons then
            local layout = tabboxButtons:FindFirstChildOfClass("UIListLayout")
            if layout then layout.Padding = UDim.new(0, SUBTAB_GAP) end

            local function applyGappedSizes()
                local count = 0
                for _, c in ipairsFn(tabboxButtons:GetChildren()) do
                    if not c:IsA("UIListLayout") then count = count + 1 end
                end
                if count <= 0 then return end
                local sharedOffset = -(SUBTAB_GAP * (count - 1)) / count - SUBTAB_PX_SHRINK
                for _, c in ipairsFn(tabboxButtons:GetChildren()) do
                    if not c:IsA("UIListLayout") then
                        c.Size = UDim2.new(1 / count, sharedOffset, 1, 0)
                    end
                end
                -- Stretch BoxOuter to fill the full Combat tab height so sub-tab
                -- content reaches down to the bottom.
                if boxOuter then
                    boxOuter.Size = UDim2.new(1, 0, 1, 0)
                end
            end

            for _, t in ipairsFn(subTabs) do
                if t and t.Resize then
                    local orig = t.Resize
                    t.Resize = function(self)
                        orig(self)
                        applyGappedSizes()
                    end
                end
            end

            applyGappedSizes()
            task.defer(applyGappedSizes)
            task.delay(0.05, applyGappedSizes)
            -- Also re-assert whenever the Combat tab itself re-renders
            Tabs.Combat.LeftSideFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyGappedSizes)
        end

        -- =================================================================
        -- (4) Inner content padding per sub-tab (breathing room)
        -- =================================================================
        for _, sub in ipairsFn(subTabs) do
            local container = sub and sub.Container
            if container and not container:FindFirstChild("CheatwareInnerPad") then
                local pad = Instance.new("UIPadding")
                pad.Name = "CheatwareInnerPad"
                pad.PaddingTop    = UDim.new(0, 6)
                pad.PaddingBottom = UDim.new(0, 6)
                pad.PaddingLeft   = UDim.new(0, 6)
                pad.PaddingRight  = UDim.new(0, 6)
                pad.Parent = container
            end
        end
    end
end


-- Hook humanoid on spawn for WS/JP force-back
if LocalPlayer.Character then
    local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hookHumanoid(hum) end
end
LocalPlayer.CharacterAdded:Connect(function(c)
    NoclipCache = {}
    local hum = c:WaitForChild("Humanoid", 5)
    if hum then hookHumanoid(hum); applyWS(); applyJP() end
    if S.GunMods.NoRecoil or S.GunMods.FastFire then task.wait(0.5); updateGunMods() end
    if S.Misc.Noclip then task.wait(0.2); applyNoclip(true) end
end)

-- ========================== HOOKS =============================
-- Anti-AFK
LocalPlayer.Idled:Connect(function()
    if S.Misc.AntiAFK then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2_new())
    end
end)

-- Infinite Jump
UserInputService.JumpRequest:Connect(function()
    if S.Misc.InfJump and LocalPlayer.Character then
        local h = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

-- Fly BodyVelocity tracker
local flyBV = nil
local function updateFly()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then if flyBV then flyBV:Destroy(); flyBV = nil end; return end

    if S.Misc.Fly then
        if not flyBV or not flyBV.Parent then
            flyBV = Instance.new("BodyVelocity")
            flyBV.MaxForce = Vector3_new(1e5, 1e5, 1e5)
            flyBV.Parent = hrp
        end
        local cam = Camera.CFrame
        local v = Vector3_new()
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then v = v + cam.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then v = v - cam.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then v = v - cam.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then v = v + cam.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then v = v + Vector3_new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then v = v - Vector3_new(0, 1, 0) end
        if v.Magnitude > 0 then v = v.Unit end
        flyBV.Velocity = v * S.Misc.FlySpeed
    else
        if flyBV then flyBV:Destroy(); flyBV = nil end
    end
end

-- ========================== RENDER LOOPS =============================

local LastSAScan = 0
RunService.Heartbeat:Connect(function()
    local now = tickFn()
    if now - LastSAScan < (1/30) then return end
    LastSAScan = now
    pickSilentTarget()
end)

local AIM_BIND = "Cheatware_AimLoop"
local function aimStep()
    if Library.Unloaded then return end

    updateFly()
    if S.Misc.CustomFOVEn then Camera.FieldOfView = S.Misc.CustomFOV end


    local saEnabled = S.SilentAim.Enabled; local saShow = S.SilentAim.ShowFOV
    local saColor = S.SilentAim.FOVColor or Color3_fromRGB(255, 0, 170)
    local mLoc = UserInputService:GetMouseLocation()

    if not S.Aimbot.Enabled then
        if FOVCircle.Visible then FOVCircle.Visible = false end
        if saEnabled and saShow then
            SilentAimCircle.Position = mLoc; SilentAimCircle.Radius = S.SilentAim.FOV; SilentAimCircle.Color = saColor; SilentAimCircle.Visible = true
        elseif SilentAimCircle.Visible then SilentAimCircle.Visible = false end
        return
    end

    FOVCircle.Position = mLoc; FOVCircle.Radius = S.Aimbot.FOV; FOVCircle.Visible = S.Aimbot.ShowFOV
    if saEnabled and saShow then
        SilentAimCircle.Position = mLoc; SilentAimCircle.Radius = S.SilentAim.FOV; SilentAimCircle.Color = saColor; SilentAimCircle.Visible = true
    elseif SilentAimCircle.Visible then SilentAimCircle.Visible = false end

    if Options.AimKey and Options.AimKey:GetState() then aimAt(getClosestPlayer()) end
end
RunService:BindToRenderStep(AIM_BIND, Enum.RenderPriority.Camera.Value + 1, aimStep)

local lastESP = 0
local ESPLoop = RunService.Heartbeat:Connect(function()
    if Library.Unloaded then return end

    triggerCheck()

    local rate = mathMax(1, S.ESP.UpdateRate)
    local now = tickFn()
    if now - lastESP < (1 / rate) then return end
    lastESP = now
    updateESP()
end)

Library:OnUnload(function()
    pcall(function() RunService:UnbindFromRenderStep(AIM_BIND) end)
    if ESPLoop then ESPLoop:Disconnect() end
    pcall(function() FOVCircle:Remove() end)
    pcall(function() SilentAimCircle:Remove() end)
    for plr, _ in pairsFn(ESPCache) do killESP(plr) end
    for plr, entry in pairsFn(PlayerCache) do for _, c in ipairsFn(entry._conns) do c:Disconnect() end end
    PlayerCache = {}; PlayerList = {}; SilentTarget = nil
    if flyBV then flyBV:Destroy() end
    for p, orig in pairsFn(NoclipCache) do if p.Parent then pcall(function() p.CanCollide = orig end) end end
    NoclipCache = {}
    Lighting.Ambient = LightingSnap.Ambient; Lighting.OutdoorAmbient = LightingSnap.OutdoorAmbient
    Lighting.ColorShift_Bottom = LightingSnap.ColorShift_Bottom; Lighting.Brightness = LightingSnap.Brightness
    Lighting.GlobalShadows = LightingSnap.GlobalShadows
    Lighting.FogStart = LightingSnap.FogStart; Lighting.FogEnd = LightingSnap.FogEnd
    for hum, conns in pairsFn(HumOverrideConns) do for _, c in ipairsFn(conns) do c:Disconnect() end end
    HumOverrideConns = {}
    Library.Unloaded = true
    print("[Cheatware] Unloaded")
end)

Library:Notify("Cheatware v18 loaded â€” Right Shift toggles UI", 3)
print("[Cheatware] v18 loaded.")