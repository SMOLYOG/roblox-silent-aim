-- init
if not game:IsLoaded() then 
    game.Loaded:Wait()
end

if not syn or not protectgui then
    getgenv().protectgui = function() end
end

if getgenv().UnloadCurrentScript then
    pcall(getgenv().UnloadCurrentScript)
end

local SilentAimSettings = {
    Enabled = false,
    ActivationMode = "Always",
    HoldKeyBind = "LeftAlt",
    
    ClassName = "Universal Silent Aim - Raycast Optimized",
    ToggleKey = "RightAlt",
    
    TeamCheck = false,
    VisibleCheck = false, 
    TargetPart = "HumanoidRootPart",
    SilentAimMethod = "Raycast",
    
    FOVRadius = 600,
    FOVVisible = false,
    ShowSilentAimTarget = false, 
    
    DynamicPrediction = true,
    BulletSpeed = 3000,
    BulletDrop = 0,
    HitChance = 100,
    MagicBullet = false,
    
    -- Nowe dedykowane opcje Raycast
    RaycastIgnoreSelf = true,
    RaycastExtendDistance = 15000,
    FilterWhitelistCheck = true,

    -- Hitbox Expansion
    HitboxEnabled = false,
    HitboxActivationMode = "Always",
    HitboxHoldKeyBind = "RightShift",
    HitboxSize = 5,
    HitboxTeamCheck = false,
    HitboxVisibleCheck = false,
    HitboxPartMode = "Torso & Head",
    HitboxDistanceScale = false,

    -- Hitbox Visualization
    HitboxVisualize = false,
    HitboxVisualMode = "3D Sphere Adornment",
    HitboxVisualTargetOnly = false,
    HitboxVisualColor = Color3.fromRGB(255, 80, 80),
    HitboxVisualTransparency = 0.5,
    HitboxVisualThickness = 2
}

getgenv().SilentAimSettings = SilentAimSettings
local MainFileName = "UniversalSilentAim"
local FileToSave = ""

local Camera = workspace.CurrentCamera
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local WorldToViewportPoint = Camera.WorldToViewportPoint
local GetPartsObscuringTarget = Camera.GetPartsObscuringTarget
local RenderStepped = RunService.RenderStepped
local GetMouseLocation = UserInputService.GetMouseLocation

local ValidTargetParts = {"Head", "HumanoidRootPart"}

-- Pool okręgów wizualizacji hitboxów (2D Drawing): klucz = BasePart, wartość = Drawing.Circle
local HitboxCirclePool = {}

-- Pool sfer 3D (Roblox HandleAdornment - w 100% natywne i zawsze widoczne w 3D): klucz = BasePart
local HitboxAdornmentPool = {}
local AdornmentContainer = nil
pcall(function()
    AdornmentContainer = (gethui and gethui()) or game:GetService("CoreGui")
end)
if not AdornmentContainer then
    pcall(function() AdornmentContainer = workspace.CurrentCamera end)
end

local function getOrCreateHitboxCircle(part)
    if HitboxCirclePool[part] then return HitboxCirclePool[part] end
    local c = Drawing.new("Circle")
    c.Thickness  = SilentAimSettings.HitboxVisualThickness or 2
    c.NumSides   = 32
    c.Filled     = false
    c.Visible    = false
    c.ZIndex     = 998
    c.Transparency = 1
    c.Color      = SilentAimSettings.HitboxVisualColor or Color3.fromRGB(255, 80, 80)
    HitboxCirclePool[part] = c
    return c
end

local function getOrCreateHitboxAdornment(part)
    if HitboxAdornmentPool[part] then return HitboxAdornmentPool[part] end
    local a = Instance.new("SphereHandleAdornment")
    a.Name = "USA_HitboxSphere"
    a.Adornee = part
    a.AlwaysOnTop = true
    a.ZIndex = 5
    a.Transparency = SilentAimSettings.HitboxVisualTransparency or 0.5
    a.Color3 = SilentAimSettings.HitboxVisualColor or Color3.fromRGB(255, 80, 80)
    a.Radius = (SilentAimSettings.HitboxSize or 5)
    a.Visible = false
    pcall(function()
        a.Parent = AdornmentContainer or workspace.CurrentCamera or part
    end)
    HitboxAdornmentPool[part] = a
    return a
end

local function clearHitboxCircles()
    for part, circle in next, HitboxCirclePool do
        pcall(function() circle:Remove() end)
        HitboxCirclePool[part] = nil
    end
end

local function clearHitboxAdornments()
    for part, a in next, HitboxAdornmentPool do
        pcall(function() a:Destroy() end)
        HitboxAdornmentPool[part] = nil
    end
end

local mouse_box = Drawing.new("Square")
mouse_box.Visible = false 
mouse_box.ZIndex = 999 
mouse_box.Color = Color3.fromRGB(54, 57, 241)
mouse_box.Thickness = 2 
mouse_box.Size = Vector2.new(16, 16)
mouse_box.Filled = true 

local fov_circle = Drawing.new("Circle")
fov_circle.Thickness = 1
fov_circle.NumSides = 100
fov_circle.Radius = 600
fov_circle.Filled = false
fov_circle.Visible = false
fov_circle.ZIndex = 999
fov_circle.Transparency = 1
fov_circle.Color = Color3.fromRGB(54, 57, 241)

function CalculateChance(Percentage)
    Percentage = math.floor(Percentage)
    local chance = math.floor(Random.new().NextNumber(Random.new(), 0, 1) * 100) / 100
    return chance <= Percentage / 100
end

-- Obsługa plików konfiguracyjnych
do 
    pcall(function()
        if isfolder and makefolder then
            if not isfolder(MainFileName) then makefolder(MainFileName); end
            if not isfolder(string.format("%s/%s", MainFileName, tostring(game.PlaceId))) then 
                makefolder(string.format("%s/%s", MainFileName, tostring(game.PlaceId)))
            end
        end
    end)
end

local Files = (listfiles and pcall(function() return listfiles(string.format("%s/%s", MainFileName, tostring(game.PlaceId))) end) and listfiles(string.format("%s/%s", MainFileName, tostring(game.PlaceId)))) or {}

local function GetFiles()
    local out = {}
    for i = 1, #Files do
        local file = Files[i]
        if file:sub(-4) == '.lua' then
            local pos = file:find('.lua', 1, true)
            local start = pos
            local char = file:sub(pos, pos)
            while char ~= '/' and char ~= '\\' and char ~= '' do
                pos = pos - 1
                char = file:sub(pos, pos)
            end
            if char == '/' or char == '\\' then
                table.insert(out, file:sub(pos + 1, start - 1))
            end
        end
    end
    return out
end

local function UpdateFile(FileName)
    if not writefile then return end
    writefile(string.format("%s/%s/%s.lua", MainFileName, tostring(game.PlaceId), FileName), HttpService:JSONEncode(SilentAimSettings))
end

local function LoadFile(FileName)
    if not readfile then return end
    local File = string.format("%s/%s/%s.lua", MainFileName, tostring(game.PlaceId), FileName)
    local ConfigData = HttpService:JSONDecode(readfile(File))
    for Index, Value in next, ConfigData do
        SilentAimSettings[Index] = Value
    end
end

local function getPositionOnScreen(Vector)
    local Vec3, OnScreen = WorldToViewportPoint(Camera, Vector)
    return Vector2.new(Vec3.X, Vec3.Y), OnScreen
end

local function IsCameraRay(Origin, Direction)
    local cam = workspace.CurrentCamera
    if not cam then return false end
    local endPoint = Origin + Direction
    if (endPoint - cam.CFrame.Position).Magnitude < 1.5 and Direction.Magnitude < 35 then
        return true
    end
    return false
end

-- Detekcja stanu przeładowania broni (klawisz R, animacja przeładowania, atrybuty Toola)
local LastReloadKeyTime = 0
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.R then
        LastReloadKeyTime = tick()
    end
end)

local function IsReloading()
    if (tick() - LastReloadKeyTime) < 0.4 then
        return true
    end

    local char = LocalPlayer.Character
    if not char then return false end

    -- Weryfikacja aktywnych animacji przeładowania w silniku postaci
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        local animator = hum:FindFirstChildOfClass("Animator")
        if animator then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                local anim = track.Animation
                local animName = (anim and anim.Name:lower()) or track.Name:lower()
                if animName:find("reload") or animName:find("mag") or animName:find("charge") then
                    return true
                end
            end
        end
    end

    -- Weryfikacja atrybutów lub stanów Toola broni
    local tool = char:FindFirstChildOfClass("Tool")
    if tool then
        if tool:GetAttribute("Reloading") or tool:GetAttribute("IsReloading") then
            return true
        end
        local reloadVal = tool:FindFirstChild("Reloading") or tool:FindFirstChild("IsReloading")
        if reloadVal and (reloadVal:IsA("BoolValue") and reloadVal.Value == true) then
            return true
        end
    end

    return false
end

-- Filtr promieni: odróżnia strzały broni od fizyki poruszania się, podłogi i łusek
local function IsCombatRay(Origin, Direction)
    if IsCameraRay(Origin, Direction) then
        return false
    end

    local mag = Direction.Magnitude
    -- Prawdziwe pociski broni mają daleki zasięg (50-100+ studs).
    -- Promienie < 30 to upuszczanie magazynka, wylot łusek, animacje IK rąk i detekcja przeszkód
    if mag < 30 then
        return false
    end

    -- Promienie rzucane stromo w dół (upadek magazynka / łusek na ziemię)
    if Direction.Y < -0.7 * mag and mag < 80 then
        return false
    end

    -- Ochrona fizyki poruszania się postaci (Ground / Floor Raycasts):
    local char = LocalPlayer.Character
    if char then
        local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
        if root then
            local distFromRoot = (Origin - root.Position).Magnitude
            if distFromRoot < 8 and Direction.Y < -0.5 * mag and mag < 50 then
                return false
            end
        end
    end

    return true
end

local CustomHitboxNames = {
    "Hitbox", "HitBox", "hitbox", "FakeHead", "fakehead",
    "ExpandedHitbox", "HeadBox", "TorsoBox", "TargetHitbox", "HitPart"
}

-- Wykrywa zmodyfikowany / powiększony hitbox lub zwraca część podstawową
local function getTargetPart(Character)
    if not Character then return nil, false end

    -- [1] Wykrywanie dedykowanych instancji hitboxów (tworzonych przez inne skrypty)
    for _, name in ipairs(CustomHitboxNames) do
        local customPart = Character:FindFirstChild(name)
        if customPart and customPart:IsA("BasePart") then
            return customPart, true
        end
    end

    -- [2] Wykrywanie zmodyfikowanych fizycznie części ciała (powiększone przez Hitbox Expander)
    local largestModifiedPart = nil
    local maxVolume = 0
    local checkParts = {
        "HumanoidRootPart", "Head", "UpperTorso", "LowerTorso", "Torso",
        "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg"
    }

    for _, partName in ipairs(checkParts) do
        local part = Character:FindFirstChild(partName)
        if part and part:IsA("BasePart") then
            local sz = part.Size
            if sz.X > 3.5 or sz.Y > 3.5 or sz.Z > 3.5 or sz.Magnitude > 4.5 then
                local vol = sz.X * sz.Y * sz.Z
                if vol > maxVolume then
                    maxVolume = vol
                    largestModifiedPart = part
                end
            end
        end
    end

    if largestModifiedPart then
        return largestModifiedPart, true
    end

    -- [3] Brak modyfikacji: zwracamy domyślną część (zgodnie z TargetPart)
    local targetPartOpt = (Options and Options.TargetPart and Options.TargetPart.Value) or SilentAimSettings.TargetPart or "HumanoidRootPart"
    local defaultPart = nil

    if targetPartOpt == "Random" then
        local chosenPartName = ValidTargetParts[math.random(1, #ValidTargetParts)]
        defaultPart = Character:FindFirstChild(chosenPartName)
    else
        defaultPart = Character:FindFirstChild(targetPartOpt)
    end

    defaultPart = defaultPart or Character:FindFirstChild("HumanoidRootPart") or Character:FindFirstChild("Head") or Character:FindFirstChild("UpperTorso") or Character:FindFirstChild("Torso")
    return defaultPart, false
end

local function getAimPosition(Origin, HitPart)
    local targetPos = HitPart.Position
    local sz = HitPart.Size

    -- Jeśli trafiamy w zmodyfikowany (powiększony) hitbox, celujemy w strefę najbliższą strzelcowi
    if sz.Magnitude > 4.5 then
        local localOrigin = HitPart.CFrame:PointToObjectSpace(Origin)
        local half = sz * 0.5
        local clamped = Vector3.new(
            math.clamp(localOrigin.X, -half.X * 0.75, half.X * 0.75),
            math.clamp(localOrigin.Y, -half.Y * 0.75, half.Y * 0.75),
            math.clamp(localOrigin.Z, -half.Z * 0.75, half.Z * 0.75)
        )
        targetPos = HitPart.CFrame:PointToWorldSpace(clamped)
    end

    local distance = (targetPos - Origin).Magnitude
    local vel = HitPart.AssemblyLinearVelocity or HitPart.Velocity or Vector3.new(0, 0, 0)

    local dynPred = (Toggles and Toggles.DynamicPred and Toggles.DynamicPred.Value) or SilentAimSettings.DynamicPrediction
    if dynPred then
        local speed = (Options and Options.BulletSpeed and Options.BulletSpeed.Value) or SilentAimSettings.BulletSpeed or 3000
        local travelTime = distance / math.max(speed, 1)
        if distance > 150 then vel = vel * 0.75 end
        targetPos = targetPos + (vel * travelTime)
    end

    return targetPos
end

-- Hitbox Expansion: odległość punktu P od osi promienia (Origin + t*Dir, t >= 0)
local function getDistanceFromRay(Origin, Direction, Point)
    local dirUnit = Direction.Unit
    local t = (Point - Origin):Dot(dirUnit)
    if t < 0 then
        return (Point - Origin).Magnitude, 0
    end
    local closest = Origin + dirUnit * t
    return (Point - closest).Magnitude, t
end

-- Buduje tablicę części wrogów w zależności od trybu
local HitboxPartsAll = {
    "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso", "Torso",
    "LeftArm", "RightArm", "LeftLeg", "RightLeg",
    "Left Arm", "Right Arm", "Left Leg", "Right Leg"
}
local HitboxPartsTorsoHead = { "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso", "Torso" }
local HitboxPartsHeadOnly = { "Head" }

local function getHitboxPartsList()
    local mode = (Options and Options.HitboxPartMode and Options.HitboxPartMode.Value) or SilentAimSettings.HitboxPartMode or "Torso & Head"
    if mode == "Head Only" then
        return HitboxPartsHeadOnly
    elseif mode == "All Parts" then
        return HitboxPartsAll
    end
    return HitboxPartsTorsoHead
end

local function tryHitboxExpand(Origin, Direction, RayParams)
    local hitboxEnabled = (Toggles and Toggles.HitboxEnabled and Toggles.HitboxEnabled.Value)
        or SilentAimSettings.HitboxEnabled
    if not hitboxEnabled then return nil end

    local baseHitboxSize = (Options and Options.HitboxSize and Options.HitboxSize.Value)
        or SilentAimSettings.HitboxSize or 5
    local doTeamCheck = (Toggles and Toggles.HitboxTeamCheck and Toggles.HitboxTeamCheck.Value)
        or SilentAimSettings.HitboxTeamCheck
    local doVisCheck = (Toggles and Toggles.HitboxVisibleCheck and Toggles.HitboxVisibleCheck.Value)
        or SilentAimSettings.HitboxVisibleCheck
    local distScale = (Toggles and Toggles.HitboxDistanceScale and Toggles.HitboxDistanceScale.Value)
        or SilentAimSettings.HitboxDistanceScale

    local maxRayLen = Direction.Magnitude
    if maxRayLen < 0.001 then return nil end

    local activePartList = getHitboxPartsList()
    local bestDist = math.huge
    local bestT    = math.huge
    local bestPart = nil
    local bestPos  = nil
    local bestNorm = nil

    for _, Player in next, Players:GetPlayers() do
        if Player == LocalPlayer then continue end
        if doTeamCheck and Player.Team ~= nil and Player.Team == LocalPlayer.Team then continue end
        local char = Player.Character
        if not char then continue end

        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end

        if doVisCheck and not IsPlayerVisible(Player) then continue end

        -- Lista części: priorytet dla zmodyfikowanych hitboxów (CustomHitboxNames)
        local candidateParts = table.clone(activePartList)
        for _, customName in ipairs(CustomHitboxNames) do
            if char:FindFirstChild(customName) and not table.find(candidateParts, customName) then
                table.insert(candidateParts, 1, customName)
            end
        end

        for _, partName in ipairs(candidateParts) do
            local part = char:FindFirstChild(partName)
            if not part then continue end
            if LocalPlayer.Character and part:IsDescendantOf(LocalPlayer.Character) then continue end

            local partPos = part.Position
            local d, t = getDistanceFromRay(Origin, Direction, partPos)

            -- Jeśli część ma fizycznie powiększony rozmiar, uwzględniamy jej promień
            local sz = part.Size
            local isExpanded = (sz.X > 3.5 or sz.Y > 3.5 or sz.Z > 3.5 or sz.Magnitude > 4.5)
            local physicalRadius = isExpanded and (sz.Magnitude * 0.5) or 0

            -- Auto-skalowanie na daleki dystans: powyżej 150 jednostek powiększa hitbox proporcjonalnie do błędu predykcji
            local effectiveHitboxSize = math.max(baseHitboxSize, physicalRadius)
            if distScale and t > 150 then
                effectiveHitboxSize = effectiveHitboxSize * math.min(1 + ((t - 150) / 250), 3)
            end

            -- t musi być w zasięgu promienia
            if t < 0 or t > maxRayLen + effectiveHitboxSize then continue end

            -- RaycastParams: sprawdzamy czy część nie jest wykluczona z filtrów
            if RayParams and typeof(RayParams) == "RaycastParams" then
                local filterType = RayParams.FilterType
                local filterList = RayParams.FilterDescendantsInstances
                if filterType == Enum.RaycastFilterType.Include then
                    local found = false
                    for _, inst in ipairs(filterList) do
                        if part:IsDescendantOf(inst) or part == inst then found = true; break end
                    end
                    if not found then continue end
                elseif filterType == Enum.RaycastFilterType.Exclude then
                    local excluded = false
                    for _, inst in ipairs(filterList) do
                        if part:IsDescendantOf(inst) or part == inst then excluded = true; break end
                    end
                    if excluded then continue end
                end
            end

            if d <= effectiveHitboxSize and (d < bestDist or (d < bestDist + 0.001 and t < bestT)) then
                bestDist = d
                bestT    = t
                bestPart = part
                bestPos  = Origin + Direction.Unit * t
                bestNorm = (bestPos - partPos).Unit
            end
        end
    end

    if not bestPart then return nil end

    -- Próba pobrania natywnego RaycastResult silnika (żeby typeof(res) == "RaycastResult")
    local realResult = nil
    pcall(function()
        local microParams = RaycastParams.new()
        microParams.FilterType = Enum.RaycastFilterType.Include
        microParams.FilterDescendantsInstances = { bestPart }
        local microDir = (bestPos - Origin).Unit * 5
        local microOrigin = bestPart.Position - microDir
        realResult = oldNamecall(workspace, microOrigin, microDir * 2, microParams)
    end)
    if realResult and typeof(realResult) == "RaycastResult" and realResult.Instance == bestPart then
        return realResult
    end

    -- Fallback: tabela z polami RaycastResult
    local fakeResult = {
        Instance  = bestPart,
        Position  = bestPos,
        Normal    = bestNorm ~= Vector3.new(0,0,0) and bestNorm or Vector3.new(0, 1, 0),
        Distance  = bestT,
        Material  = Enum.Material.SmoothPlastic,
    }
    return fakeResult
end

local function getRaycastDirection(Origin, Position, OriginalDirection)
    local diff = Position - Origin
    local dist = diff.Magnitude
    if dist < 0.001 then
        return OriginalDirection or Vector3.new(0, -1, 0)
    end
    local unit = diff.Unit
    local origMag = OriginalDirection and OriginalDirection.Magnitude or 1000
    local finalLength = math.max(origMag, dist + 250, SilentAimSettings.RaycastExtendDistance)
    return unit * finalLength
end

local function getMousePosition()
    return GetMouseLocation(UserInputService)
end

local function IsPlayerVisible(Player)
    if SilentAimSettings.MagicBullet then return true end

    local PlayerCharacter = Player.Character
    local LocalPlayerCharacter = LocalPlayer.Character
    if not (PlayerCharacter or LocalPlayerCharacter) then return false end 
    
    local PlayerRoot = getTargetPart(PlayerCharacter) or PlayerCharacter:FindFirstChild("HumanoidRootPart") or PlayerCharacter:FindFirstChild("Head")
    if not PlayerRoot then return false end 
    
    local CastPoints, IgnoreList = {PlayerRoot.Position, LocalPlayerCharacter, PlayerCharacter}, {LocalPlayerCharacter, PlayerCharacter}
    local ObscuringObjects = #GetPartsObscuringTarget(Camera, CastPoints, IgnoreList)
    
    return ObscuringObjects == 0
end

local function getClosestPlayer()
    local Closest = nil
    local DistanceToMouse = 999999

    for _, Player in next, Players:GetPlayers() do
        if Player == LocalPlayer then continue end
        if Toggles and Toggles.TeamCheck and Toggles.TeamCheck.Value and Player.Team ~= nil and Player.Team == LocalPlayer.Team then continue end

        local Character = Player.Character
        if not Character then continue end
        
        local visCheck = Toggles and Toggles.VisibleCheck and Toggles.VisibleCheck.Value
        if visCheck and not IsPlayerVisible(Player) then continue end

        local Humanoid = Character:FindFirstChildOfClass("Humanoid")
        if not Humanoid or Humanoid.Health <= 0 then continue end

        -- Wykrywa zmodyfikowany hitbox (najwyższy priorytet) lub część bazową
        local targetPart, isModified = getTargetPart(Character)
        if not targetPart then continue end

        local ScreenPosition, OnScreen = getPositionOnScreen(targetPart.Position)
        local mousePos = getMousePosition()
        local Distance = (mousePos - ScreenPosition).Magnitude

        -- Jeśli hitbox jest zmodyfikowany (powiększony), uwzględniamy promień obiektu na ekranie
        if isModified then
            local halfSize = targetPart.Size.Magnitude * 0.5
            local edgePos = targetPart.Position + (Camera.CFrame.RightVector * halfSize)
            local edgeScreen, _ = getPositionOnScreen(edgePos)
            local screenRadius = (edgeScreen - ScreenPosition).Magnitude
            Distance = math.max(0, Distance - screenRadius)
        end
        
        local maxRadius = (Options and Options.Radius and Options.Radius.Value) or SilentAimSettings.FOVRadius or 600
        if Distance <= maxRadius and Distance < DistanceToMouse then
            Closest = targetPart
            DistanceToMouse = Distance
        end
    end
    return Closest
end

-- Obsługa klawiszy Hold oraz przycisków myszy (RMB, MMB, MB4, MB5)
local SideMouseState = {
    MB4 = false,
    MB5 = false,
    RMB = false,
    MMB = false
}

local function isMouseButtonDown(btn)
    if btn == "RMB" then
        return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
    elseif btn == "MMB" then
        return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton3)
    elseif btn == "MB4" then
        local success, down = pcall(function()
            if iskeydown then return iskeydown(0x05) end
            if iskeypressed then return iskeypressed(0x05) end
            return false
        end)
        if success and down then return true end
        return SideMouseState.MB4
    elseif btn == "MB5" then
        local success, down = pcall(function()
            if iskeydown then return iskeydown(0x06) end
            if iskeypressed then return iskeypressed(0x06) end
            return false
        end)
        if success and down then return true end
        return SideMouseState.MB5
    end
    return false
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    pcall(function()
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            SideMouseState.RMB = true
        elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
            SideMouseState.MMB = true
        end
        local typeName = tostring(input.UserInputType.Name)
        local keyName = tostring(input.KeyCode.Name)
        if typeName == "MouseButton4" or keyName == "Button4" then
            SideMouseState.MB4 = true
        elseif typeName == "MouseButton5" or keyName == "Button5" then
            SideMouseState.MB5 = true
        end
    end)
end)

UserInputService.InputEnded:Connect(function(input)
    pcall(function()
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            SideMouseState.RMB = false
        elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
            SideMouseState.MMB = false
        end
        local typeName = tostring(input.UserInputType.Name)
        local keyName = tostring(input.KeyCode.Name)
        if typeName == "MouseButton4" or keyName == "Button4" then
            SideMouseState.MB4 = false
        elseif typeName == "MouseButton5" or keyName == "Button5" then
            SideMouseState.MB5 = false
        end
    end)
end)

local function IsSilentAimActive()
    local enabled = Toggles and Toggles.aim_Enabled and Toggles.aim_Enabled.Value
    if not enabled then return false end

    local mode = (Options and Options.ActivationMode and Options.ActivationMode.Value) or SilentAimSettings.ActivationMode or "Always"
    if mode == "Always" then
        return true
    elseif mode == "Hold Key" then
        return (Options and Options.HoldKeyBind and Options.HoldKeyBind:GetState()) or false
    elseif mode == "Hold Right Click (RMB)" then
        return isMouseButtonDown("RMB")
    elseif mode == "Hold Middle Click (MMB)" then
        return isMouseButtonDown("MMB")
    elseif mode == "Hold Mouse 4 (Side Back)" then
        return isMouseButtonDown("MB4")
    elseif mode == "Hold Mouse 5 (Side Forward)" then
        return isMouseButtonDown("MB5")
    end
    return true
end

local function IsHitboxActive()
    local enabled = (Toggles and Toggles.HitboxEnabled and Toggles.HitboxEnabled.Value) or SilentAimSettings.HitboxEnabled
    if not enabled then return false end

    local mode = (Options and Options.HitboxActivationMode and Options.HitboxActivationMode.Value) or SilentAimSettings.HitboxActivationMode or "Always"
    if mode == "Always" then
        return true
    elseif mode == "Hold Key" then
        return (Options and Options.HitboxHoldKeyBind and Options.HitboxHoldKeyBind:GetState()) or false
    elseif mode == "Hold Right Click (RMB)" then
        return isMouseButtonDown("RMB")
    elseif mode == "Hold Middle Click (MMB)" then
        return isMouseButtonDown("MMB")
    elseif mode == "Hold Mouse 4 (Side Back)" then
        return isMouseButtonDown("MB4")
    elseif mode == "Hold Mouse 5 (Side Forward)" then
        return isMouseButtonDown("MB5")
    end
    return true
end

-- UI Creating & Handling
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/Library.lua"))()

local Window = Library:CreateWindow({Title = 'Universal Silent Aim [Raycast Focus]', Center = true, AutoShow = true, TabPadding = 8, MenuFadeTime = 0.2})
local GeneralTab = Window:AddTab("General")
local RaycastTab = Window:AddTab("Raycast")
local ConfigsTab = Window:AddTab("Configs")
local SettingsTab = Window:AddTab("Settings")

local MainBOX = GeneralTab:AddLeftTabbox("Main") do
    local Main = MainBOX:AddTab("Main")
    
    Main:AddToggle("aim_Enabled", {Text = "Enabled", Default = SilentAimSettings.Enabled}):AddKeyPicker("aim_Enabled_KeyPicker", {Default = "RightAlt", SyncToggleState = true, Mode = "Toggle", Text = "Enabled", NoUI = false})
    Toggles.aim_Enabled:OnChanged(function()
        SilentAimSettings.Enabled = Toggles.aim_Enabled.Value
        mouse_box.Visible = SilentAimSettings.Enabled and SilentAimSettings.ShowSilentAimTarget
    end)
    
    Main:AddToggle("TeamCheck", {Text = "Team Check", Default = SilentAimSettings.TeamCheck}):OnChanged(function() SilentAimSettings.TeamCheck = Toggles.TeamCheck.Value end)
    Main:AddToggle("VisibleCheck", {Text = "Visible Check", Default = SilentAimSettings.VisibleCheck}):OnChanged(function() SilentAimSettings.VisibleCheck = Toggles.VisibleCheck.Value end)
    Main:AddToggle("MagicBullet", {Text = "Magic Bullet (Bypass Obstacles)", Default = SilentAimSettings.MagicBullet}):OnChanged(function() SilentAimSettings.MagicBullet = Toggles.MagicBullet.Value end)
    
    Main:AddDropdown("TargetPart", {AllowNull = false, Text = "Target Part", Default = SilentAimSettings.TargetPart, Values = {"Head", "HumanoidRootPart", "Random"}}):OnChanged(function()
        if Options and Options.TargetPart then
            SilentAimSettings.TargetPart = Options.TargetPart.Value
        end
    end)
    
    Main:AddSlider('HitChance', {Text = 'Hit chance', Default = 100, Min = 0, Max = 100, Rounding = 1, Compact = false}):OnChanged(function() SilentAimSettings.HitChance = Options.HitChance.Value end)
    
    Main:AddDropdown("ActivationMode", {
        AllowNull = false, 
        Text = "Silent Aim Activation", 
        Default = SilentAimSettings.ActivationMode or "Always", 
        Values = {"Always", "Hold Key", "Hold Right Click (RMB)", "Hold Middle Click (MMB)", "Hold Mouse 4 (Side Back)", "Hold Mouse 5 (Side Forward)"}
    }):OnChanged(function()
        SilentAimSettings.ActivationMode = Options.ActivationMode.Value
    end)
    
    Main:AddLabel("Keybind (for Hold Key mode):"):AddKeyPicker("HoldKeyBind", {
        Default = SilentAimSettings.HoldKeyBind or "LeftAlt",
        SyncToggleState = false,
        Mode = "Hold",
        Text = "Silent Aim Hold Key",
        NoUI = false,
    })
    Options.HoldKeyBind:OnChanged(function()
        SilentAimSettings.HoldKeyBind = Options.HoldKeyBind.Value
    end)
end

local FieldOfViewBOX = GeneralTab:AddRightTabbox("Field Of View & Range") do
    local Main = FieldOfViewBOX:AddTab("Visuals")
    
    Main:AddToggle("Visible", {Text = "Show FOV Circle"}):AddColorPicker("Color", {Default = Color3.fromRGB(54, 57, 241)}):OnChanged(function()
        fov_circle.Visible = Toggles.Visible.Value
        SilentAimSettings.FOVVisible = Toggles.Visible.Value
    end)
    Main:AddSlider("Radius", {Text = "FOV Circle Radius", Min = 0, Max = 2000, Default = 600, Rounding = 0}):OnChanged(function()
        fov_circle.Radius = Options.Radius.Value
        SilentAimSettings.FOVRadius = Options.Radius.Value
    end)
    Main:AddToggle("MousePosition", {Text = "Show Silent Aim Target"}):AddColorPicker("MouseVisualizeColor", {Default = Color3.fromRGB(54, 57, 241)}):OnChanged(function()
        mouse_box.Visible = Toggles.MousePosition.Value 
        SilentAimSettings.ShowSilentAimTarget = Toggles.MousePosition.Value 
    end)
end

local RaycastSettingsBOX = RaycastTab:AddLeftTabbox("Raycast Optimization") do
    local Main = RaycastSettingsBOX:AddTab("Parameters")
    
    Main:AddToggle("RaycastIgnoreSelf", {Text = "Sanitize Raycast Filter (Ignore Local)", Default = true}):OnChanged(function()
        SilentAimSettings.RaycastIgnoreSelf = Toggles.RaycastIgnoreSelf.Value
    end)
    
    Main:AddSlider("RaycastDistance", {Text = "Ray Max Distance", Min = 1000, Max = 50000, Default = 15000, Rounding = 0}):OnChanged(function()
        SilentAimSettings.RaycastExtendDistance = Options.RaycastDistance.Value
    end)

    Main:AddToggle("DynamicPred", {Text = "Velocity Prediction", Default = true}):OnChanged(function()
        SilentAimSettings.DynamicPrediction = Toggles.DynamicPred.Value
    end)
    Main:AddSlider("BulletSpeed", {Text = "Bullet Speed (studs/s)", Min = 500, Max = 20000, Default = 3000, Rounding = 0}):OnChanged(function()
        SilentAimSettings.BulletSpeed = Options.BulletSpeed.Value
    end)

    -- Zakładka Hitbox Expansion
    local HitboxTab = RaycastSettingsBOX:AddTab("Hitbox")

    HitboxTab:AddToggle("HitboxEnabled", {Text = "Hitbox Expansion", Default = SilentAimSettings.HitboxEnabled}):OnChanged(function()
        SilentAimSettings.HitboxEnabled = Toggles.HitboxEnabled.Value
    end)
    
    HitboxTab:AddDropdown("HitboxActivationMode", {
        AllowNull = false,
        Text = "Hitbox Activation",
        Default = SilentAimSettings.HitboxActivationMode or "Always",
        Values = {"Always", "Hold Key", "Hold Right Click (RMB)", "Hold Middle Click (MMB)", "Hold Mouse 4 (Side Back)", "Hold Mouse 5 (Side Forward)"}
    }):OnChanged(function()
        SilentAimSettings.HitboxActivationMode = Options.HitboxActivationMode.Value
    end)
    
    HitboxTab:AddLabel("Keybind (for Hold Key mode):"):AddKeyPicker("HitboxHoldKeyBind", {
        Default = SilentAimSettings.HitboxHoldKeyBind or "RightShift",
        SyncToggleState = false,
        Mode = "Hold",
        Text = "Hitbox Hold Key",
        NoUI = false,
    })
    Options.HitboxHoldKeyBind:OnChanged(function()
        SilentAimSettings.HitboxHoldKeyBind = Options.HitboxHoldKeyBind.Value
    end)
    
    HitboxTab:AddSlider("HitboxSize", {Text = "Hitbox Radius (studs)", Min = 0.5, Max = 30, Default = SilentAimSettings.HitboxSize, Rounding = 1}):OnChanged(function()
        SilentAimSettings.HitboxSize = Options.HitboxSize.Value
    end)
    HitboxTab:AddDropdown("HitboxPartMode", {AllowNull = false, Text = "Hitbox Target Parts", Default = SilentAimSettings.HitboxPartMode or "Torso & Head", Values = {"Torso & Head", "Head Only", "All Parts"}}):OnChanged(function()
        if Options and Options.HitboxPartMode then
            SilentAimSettings.HitboxPartMode = Options.HitboxPartMode.Value
        end
    end)
    HitboxTab:AddToggle("HitboxDistanceScale", {Text = "Distance Auto-Scale (Long Range)", Default = SilentAimSettings.HitboxDistanceScale}):OnChanged(function()
        SilentAimSettings.HitboxDistanceScale = Toggles.HitboxDistanceScale.Value
    end)
    HitboxTab:AddToggle("HitboxTeamCheck", {Text = "Team Check (Hitbox)", Default = SilentAimSettings.HitboxTeamCheck}):OnChanged(function()
        SilentAimSettings.HitboxTeamCheck = Toggles.HitboxTeamCheck.Value
    end)
    HitboxTab:AddToggle("HitboxVisibleCheck", {Text = "Visible Check (Hitbox)", Default = SilentAimSettings.HitboxVisibleCheck}):OnChanged(function()
        SilentAimSettings.HitboxVisibleCheck = Toggles.HitboxVisibleCheck.Value
    end)

    HitboxTab:AddDivider()

    local VisToggle = HitboxTab:AddToggle("HitboxVisualize", {Text = "Show Hitbox Visuals", Default = false})
    VisToggle:OnChanged(function()
        SilentAimSettings.HitboxVisualize = Toggles.HitboxVisualize.Value
        if not Toggles.HitboxVisualize.Value then
            for _, circle in next, HitboxCirclePool do
                circle.Visible = false
            end
            for _, a in next, HitboxAdornmentPool do
                a.Visible = false
            end
        end
    end)
    VisToggle:AddColorPicker("HitboxVisualColorPicker", {Default = Color3.fromRGB(255, 80, 80), Title = "Hitbox Color"}):OnChanged(function()
        if Options and Options.HitboxVisualColorPicker then
            SilentAimSettings.HitboxVisualColor = Options.HitboxVisualColorPicker.Value
            for _, circle in next, HitboxCirclePool do
                circle.Color = SilentAimSettings.HitboxVisualColor
            end
            for _, a in next, HitboxAdornmentPool do
                a.Color3 = SilentAimSettings.HitboxVisualColor
            end
        end
    end)

    HitboxTab:AddDropdown("HitboxVisualMode", {AllowNull = false, Text = "Visual Style", Default = "3D Sphere Adornment", Values = {"3D Sphere Adornment", "2D Drawing Circle", "Both"}}):OnChanged(function()
        if Options and Options.HitboxVisualMode then
            SilentAimSettings.HitboxVisualMode = Options.HitboxVisualMode.Value
            if SilentAimSettings.HitboxVisualMode == "3D Sphere Adornment" then
                for _, circle in next, HitboxCirclePool do circle.Visible = false end
            elseif SilentAimSettings.HitboxVisualMode == "2D Drawing Circle" then
                for _, a in next, HitboxAdornmentPool do a.Visible = false end
            end
        end
    end)

    HitboxTab:AddSlider("HitboxVisualTransparency", {Text = "3D Sphere Transparency", Min = 0, Max = 1, Default = 0.5, Rounding = 2}):OnChanged(function()
        if Options and Options.HitboxVisualTransparency then
            SilentAimSettings.HitboxVisualTransparency = Options.HitboxVisualTransparency.Value
            for _, a in next, HitboxAdornmentPool do
                a.Transparency = SilentAimSettings.HitboxVisualTransparency
            end
        end
    end)

    HitboxTab:AddToggle("HitboxVisualTargetOnly", {Text = "Visualize Target Only (High FPS)", Default = false}):OnChanged(function()
        SilentAimSettings.HitboxVisualTargetOnly = Toggles.HitboxVisualTargetOnly.Value
    end)
end

-- Zakładka Configs
local CreateConfigurationBOX = ConfigsTab:AddLeftTabbox("Create Configuration") do 
    local Main = CreateConfigurationBOX:AddTab("Create Configuration")
    Main:AddInput("CreateConfigTextBox", {Default = "", Numeric = false, Finished = false, Text = "Config Name", Placeholder = "Nazwa pliku"}):OnChanged(function()
        if Options and Options.CreateConfigTextBox and Options.CreateConfigTextBox.Value and string.len(Options.CreateConfigTextBox.Value) ~= "" then 
            FileToSave = Options.CreateConfigTextBox.Value 
        end
    end)
    Main:AddButton("Create Configuration File", function()
        if FileToSave ~= "" and FileToSave ~= nil then 
            UpdateFile(FileToSave)
            if Options.SaveConfigurationDropdown then Options.SaveConfigurationDropdown:SetValues(GetFiles()) end
        end
    end)
end

local SaveConfigurationBOX = ConfigsTab:AddRightTabbox("Save / Load Configuration") do 
    local Main = SaveConfigurationBOX:AddTab("Configurations")
    Main:AddDropdown("SaveConfigurationDropdown", {AllowNull = true, Values = GetFiles(), Text = "Select Config"})
    Main:AddButton("Save Configuration", function()
        if Options and Options.SaveConfigurationDropdown and Options.SaveConfigurationDropdown.Value then 
            UpdateFile(Options.SaveConfigurationDropdown.Value) 
        end
    end)
    Main:AddButton("Load Configuration", function()
        if Options and Options.SaveConfigurationDropdown and table.find(GetFiles(), Options.SaveConfigurationDropdown.Value) then
            LoadFile(Options.SaveConfigurationDropdown.Value)
            if Toggles.aim_Enabled then Toggles.aim_Enabled:SetValue(SilentAimSettings.Enabled) end
            if Toggles.TeamCheck then Toggles.TeamCheck:SetValue(SilentAimSettings.TeamCheck) end
            if Toggles.VisibleCheck then Toggles.VisibleCheck:SetValue(SilentAimSettings.VisibleCheck) end
            if Toggles.MagicBullet then Toggles.MagicBullet:SetValue(SilentAimSettings.MagicBullet) end
            if Options.TargetPart then Options.TargetPart:SetValue(SilentAimSettings.TargetPart) end
            if Toggles.Visible then Toggles.Visible:SetValue(SilentAimSettings.FOVVisible) end
            if Options.Radius then Options.Radius:SetValue(SilentAimSettings.FOVRadius) end
            if Toggles.MousePosition then Toggles.MousePosition:SetValue(SilentAimSettings.ShowSilentAimTarget) end
            if Options.HitChance then Options.HitChance:SetValue(SilentAimSettings.HitChance) end
            if Options.ActivationMode and SilentAimSettings.ActivationMode then Options.ActivationMode:SetValue(SilentAimSettings.ActivationMode) end
            if Options.HoldKeyBind and SilentAimSettings.HoldKeyBind then Options.HoldKeyBind:SetValue(SilentAimSettings.HoldKeyBind) end
            if Toggles.RaycastIgnoreSelf and SilentAimSettings.RaycastIgnoreSelf ~= nil then Toggles.RaycastIgnoreSelf:SetValue(SilentAimSettings.RaycastIgnoreSelf) end
            if Options.RaycastDistance and SilentAimSettings.RaycastExtendDistance then Options.RaycastDistance:SetValue(SilentAimSettings.RaycastExtendDistance) end
            if Toggles.DynamicPred and SilentAimSettings.DynamicPrediction ~= nil then Toggles.DynamicPred:SetValue(SilentAimSettings.DynamicPrediction) end
            if Options.BulletSpeed and SilentAimSettings.BulletSpeed then Options.BulletSpeed:SetValue(SilentAimSettings.BulletSpeed) end
            if Toggles.HitboxEnabled and SilentAimSettings.HitboxEnabled ~= nil then Toggles.HitboxEnabled:SetValue(SilentAimSettings.HitboxEnabled) end
            if Options.HitboxActivationMode and SilentAimSettings.HitboxActivationMode then Options.HitboxActivationMode:SetValue(SilentAimSettings.HitboxActivationMode) end
            if Options.HitboxHoldKeyBind and SilentAimSettings.HitboxHoldKeyBind then Options.HitboxHoldKeyBind:SetValue(SilentAimSettings.HitboxHoldKeyBind) end
            if Options.HitboxSize and SilentAimSettings.HitboxSize then Options.HitboxSize:SetValue(SilentAimSettings.HitboxSize) end
            if Options.HitboxPartMode and SilentAimSettings.HitboxPartMode then Options.HitboxPartMode:SetValue(SilentAimSettings.HitboxPartMode) end
            if Toggles.HitboxDistanceScale and SilentAimSettings.HitboxDistanceScale ~= nil then Toggles.HitboxDistanceScale:SetValue(SilentAimSettings.HitboxDistanceScale) end
            if Toggles.HitboxTeamCheck and SilentAimSettings.HitboxTeamCheck ~= nil then Toggles.HitboxTeamCheck:SetValue(SilentAimSettings.HitboxTeamCheck) end
            if Toggles.HitboxVisibleCheck and SilentAimSettings.HitboxVisibleCheck ~= nil then Toggles.HitboxVisibleCheck:SetValue(SilentAimSettings.HitboxVisibleCheck) end
            if Toggles.HitboxVisualize and SilentAimSettings.HitboxVisualize ~= nil then Toggles.HitboxVisualize:SetValue(SilentAimSettings.HitboxVisualize) end
            if Options.HitboxVisualMode and SilentAimSettings.HitboxVisualMode then Options.HitboxVisualMode:SetValue(SilentAimSettings.HitboxVisualMode) end
            if Toggles.HitboxVisualTargetOnly and SilentAimSettings.HitboxVisualTargetOnly ~= nil then Toggles.HitboxVisualTargetOnly:SetValue(SilentAimSettings.HitboxVisualTargetOnly) end
        end
    end)
end

-- Zakładka Settings (Eject)
local ScriptActive = true
local UnloadConnection
local oldNamecall
local originalRaycast

local function UnloadScript()
    pcall(function()
        ScriptActive = false
        if UnloadConnection then UnloadConnection:Disconnect() end
        if mouse_box then mouse_box:Remove() end
        if fov_circle then fov_circle:Remove() end
        clearHitboxCircles()
        clearHitboxAdornments()
        if originalRaycast and hookfunction and workspace and workspace.Raycast then
            pcall(hookfunction, workspace.Raycast, originalRaycast)
        end
        Library:Unload()
        getgenv().UnloadCurrentScript = nil
    end)
end
getgenv().UnloadCurrentScript = UnloadScript

local UnloadBOX = SettingsTab:AddLeftTabbox("Unload") do
    local Main = UnloadBOX:AddTab("Eject")
    Main:AddButton("Eject / Unload Skryptu", function() UnloadScript() end)
end

local CachedTarget = nil
UnloadConnection = RenderStepped:Connect(function()
    Camera = workspace.CurrentCamera
    local aimEnabled = IsSilentAimActive()
    if aimEnabled then
        CachedTarget = getClosestPlayer()
    else
        CachedTarget = nil
    end

    local showTarget = Toggles and Toggles.MousePosition and Toggles.MousePosition.Value
    if showTarget and aimEnabled then
        if CachedTarget and CachedTarget.Parent then 
            local Root = CachedTarget
            local RootToViewportPoint, IsOnScreen = WorldToViewportPoint(Camera, Root.Position);
            mouse_box.Visible = IsOnScreen
            mouse_box.Position = Vector2.new(RootToViewportPoint.X, RootToViewportPoint.Y)
        else 
            mouse_box.Visible = false 
            mouse_box.Position = Vector2.new()
        end
    else
        mouse_box.Visible = false
    end
    
    local fovVisible = Toggles and Toggles.Visible and Toggles.Visible.Value
    if fovVisible then 
        fov_circle.Visible = fovVisible
        if Options and Options.Color then
            fov_circle.Color = Options.Color.Value
        end
        fov_circle.Position = getMousePosition()
    else
        fov_circle.Visible = false
    end

    -- Wizualizacja hitboxów (3D SphereHandleAdornment oraz opcjonalnie 2D Drawing.Circle)
    local hitboxActive = IsHitboxActive()
    local showHitboxes = ((Toggles and Toggles.HitboxVisualize and Toggles.HitboxVisualize.Value) or SilentAimSettings.HitboxVisualize) and hitboxActive
    local baseHitboxSize = (Options and Options.HitboxSize and Options.HitboxSize.Value) or SilentAimSettings.HitboxSize or 5
    local hitboxColor  = (Options and Options.HitboxVisualColorPicker and Options.HitboxVisualColorPicker.Value) or SilentAimSettings.HitboxVisualColor or Color3.fromRGB(255, 80, 80)
    local doTeamCheckVis = (Toggles and Toggles.HitboxTeamCheck and Toggles.HitboxTeamCheck.Value)
    if doTeamCheckVis == nil then doTeamCheckVis = SilentAimSettings.HitboxTeamCheck end
    local targetOnly = (Toggles and Toggles.HitboxVisualTargetOnly and Toggles.HitboxVisualTargetOnly.Value) or SilentAimSettings.HitboxVisualTargetOnly
    local distScale = (Toggles and Toggles.HitboxDistanceScale and Toggles.HitboxDistanceScale.Value) or SilentAimSettings.HitboxDistanceScale
    local visualStyle = (Options and Options.HitboxVisualMode and Options.HitboxVisualMode.Value) or SilentAimSettings.HitboxVisualMode or "3D Sphere Adornment"

    -- Zbieramy aktualnie widoczne części żeby zidentyfikować przestarzałe obiekty w poolach
    local activeParts = {}

    if showHitboxes then
        local camCF = Camera.CFrame
        local rightVec = camCF.RightVector
        local camPos = camCF.Position
        local activePartList = getHitboxPartsList()

        for _, Player in next, Players:GetPlayers() do
            if Player == LocalPlayer then continue end
            if doTeamCheckVis and Player.Team ~= nil and Player.Team == LocalPlayer.Team then continue end
            local char = Player.Character
            if not char then continue end

            -- Opcja Target Only: pomijaj graczy innych niż namierzony cel
            if targetOnly and (not CachedTarget or CachedTarget.Parent ~= char) then
                continue
            end

            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then continue end

            local candidateParts = table.clone(activePartList)
            for _, customName in ipairs(CustomHitboxNames) do
                if char:FindFirstChild(customName) and not table.find(candidateParts, customName) then
                    table.insert(candidateParts, 1, customName)
                end
            end

            for _, partName in ipairs(candidateParts) do
                local part = char:FindFirstChild(partName)
                if not part then continue end

                local sz = part.Size
                local isExpanded = (sz.X > 3.5 or sz.Y > 3.5 or sz.Z > 3.5 or sz.Magnitude > 4.5)
                local physicalRadius = isExpanded and (sz.Magnitude * 0.5) or 0
                local currentHitboxSize = math.max(baseHitboxSize, physicalRadius)

                if distScale then
                    local distToCam = (part.Position - camPos).Magnitude
                    if distToCam > 150 then
                        currentHitboxSize = currentHitboxSize * math.min(1 + ((distToCam - 150) / 250), 3)
                    end
                end

                activeParts[part] = true

                -- 1. Tryb 3D Sphere HandleAdornment (100% natywna grafika Roblox, widoczna z każdej odległości)
                if visualStyle == "3D Sphere Adornment" or visualStyle == "Both" then
                    local adorn = getOrCreateHitboxAdornment(part)
                    adorn.Adornee = part
                    adorn.Radius = currentHitboxSize
                    adorn.Color3 = hitboxColor
                    adorn.Transparency = SilentAimSettings.HitboxVisualTransparency or 0.5
                    adorn.Visible = true
                else
                    local existingAdorn = HitboxAdornmentPool[part]
                    if existingAdorn then existingAdorn.Visible = false end
                end

                -- 2. Tryb 2D Drawing.Circle
                if visualStyle == "2D Drawing Circle" or visualStyle == "Both" then
                    local centerVec, onScreen = Camera:WorldToViewportPoint(part.Position)
                    if onScreen then
                        local edgeVec = Camera:WorldToViewportPoint(part.Position + rightVec * currentHitboxSize)
                        local pixelRadius = math.max(2, (Vector2.new(edgeVec.X, edgeVec.Y) - Vector2.new(centerVec.X, centerVec.Y)).Magnitude)

                        local circle = getOrCreateHitboxCircle(part)
                        circle.Visible   = true
                        circle.Position  = Vector2.new(centerVec.X, centerVec.Y)
                        circle.Radius    = pixelRadius
                        circle.Color     = hitboxColor
                    else
                        local existing = HitboxCirclePool[part]
                        if existing then existing.Visible = false end
                    end
                else
                    local existingCircle = HitboxCirclePool[part]
                    if existingCircle then existingCircle.Visible = false end
                end
            end
        end

        -- Ukryj elementy, które nie należą do żadnego aktywnego celu w tej klatce
        for part, circle in next, HitboxCirclePool do
            if not activeParts[part] then
                circle.Visible = false
            end
        end
        for part, adorn in next, HitboxAdornmentPool do
            if not activeParts[part] then
                adorn.Visible = false
            end
        end
    else
        -- Wizualizacja wyłączona — ukryj wszystko
        for _, circle in next, HitboxCirclePool do
            circle.Visible = false
        end
        for _, adorn in next, HitboxAdornmentPool do
            adorn.Visible = false
        end
    end
end)

-- Metoda Raycast: Zoptymalizowany hook namecall (zero zbędnych alokacji GC dla innych metod)
oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    if not ScriptActive then
        return oldNamecall(self, ...)
    end

    local Method = getnamecallmethod()
    if self == workspace and (Method == "Raycast" or Method == "raycast") and not checkcaller() then
        local Origin, Direction, RayParams = ...

        if typeof(Origin) == "Vector3" and typeof(Direction) == "Vector3" then
            -- Ochrona ruchu i serwera: ignorujemy promienie podłogi, wspinaczki i fizyki gracza
            if IsCombatRay(Origin, Direction) then
                local aimEnabled = IsSilentAimActive()
                local hitboxEnabled = IsHitboxActive()

                -- [1] Hitbox Expansion: tylko gdy opcja hitboxów jest faktycznie włączona w menu
                if hitboxEnabled then
                    local hitboxResult = tryHitboxExpand(Origin, Direction, RayParams)
                    if hitboxResult then
                        return hitboxResult
                    end
                end

                -- [2] Silent Aim redirect
                if aimEnabled and CalculateChance(SilentAimSettings.HitChance) then
                    local HitPart = CachedTarget
                    if HitPart and HitPart.Parent and (not LocalPlayer.Character or not HitPart:IsDescendantOf(LocalPlayer.Character)) then
                        local hum = HitPart.Parent:FindFirstChildOfClass("Humanoid")
                        if not hum or hum.Health > 0 then
                            local targetPos = getAimPosition(Origin, HitPart)

                            -- Magic Bullet: przesuń Origin tuż przed cel
                            local finalOrigin = Origin
                            if SilentAimSettings.MagicBullet then
                                local toTarget = (targetPos - Origin)
                                if toTarget.Magnitude > 2 then
                                    finalOrigin = targetPos - (toTarget.Unit * 1.5)
                                end
                            end

                            local newDirection = getRaycastDirection(finalOrigin, targetPos, Direction)

                            -- [3] Hitbox check dla przekierowanego promienia na duży dystans
                            if hitboxEnabled then
                                local redirectedHitbox = tryHitboxExpand(finalOrigin, newDirection, RayParams)
                                if redirectedHitbox then
                                    return redirectedHitbox
                                end
                            end

                            -- Bezpieczne klonowanie RaycastParams: nigdy nie mutujemy oryginalnego obiektu gry!
                            local finalRayParams = RayParams
                            if RayParams and typeof(RayParams) == "RaycastParams" and SilentAimSettings.RaycastIgnoreSelf then
                                if LocalPlayer.Character and RayParams.FilterType == Enum.RaycastFilterType.Exclude then
                                    local filter = RayParams.FilterDescendantsInstances
                                    if not table.find(filter, LocalPlayer.Character) then
                                        local clonedParams = RaycastParams.new()
                                        clonedParams.FilterType = RayParams.FilterType
                                        clonedParams.IgnoreWater = RayParams.IgnoreWater
                                        clonedParams.CollisionGroup = RayParams.CollisionGroup
                                        local newFilter = table.clone(filter)
                                        table.insert(newFilter, LocalPlayer.Character)
                                        clonedParams.FilterDescendantsInstances = newFilter
                                        finalRayParams = clonedParams
                                    end
                                end
                            end

                            return oldNamecall(self, finalOrigin, newDirection, finalRayParams)
                        end
                    end
                end
            end
        end
    end
    
    return oldNamecall(self, ...)
end))

-- Hook na bezpośrednie wywołania workspace.Raycast (omijające __namecall)
pcall(function()
    if workspace and typeof(workspace.Raycast) == "function" and hookfunction then
        originalRaycast = hookfunction(workspace.Raycast, newcclosure(function(self, Origin, Direction, RayParams, ...)
            if not ScriptActive then
                return originalRaycast(self, Origin, Direction, RayParams, ...)
            end

            if self == workspace and not checkcaller() then
                if typeof(Origin) == "Vector3" and typeof(Direction) == "Vector3" then
                    -- Ochrona ruchu i serwera: ignorujemy promienie podłogi, wspinaczki i fizyki gracza
                    if IsCombatRay(Origin, Direction) then
                        local aimEnabled = IsSilentAimActive()
                        local hitboxEnabled = IsHitboxActive()

                        -- [1] Hitbox Expansion
                        if hitboxEnabled then
                            local hitboxResult = tryHitboxExpand(Origin, Direction, RayParams)
                            if hitboxResult then
                                return hitboxResult
                            end
                        end

                        -- [2] Silent Aim redirect
                        if aimEnabled and CalculateChance(SilentAimSettings.HitChance) then
                            local HitPart = CachedTarget
                            if HitPart and HitPart.Parent and (not LocalPlayer.Character or not HitPart:IsDescendantOf(LocalPlayer.Character)) then
                                local hum = HitPart.Parent:FindFirstChildOfClass("Humanoid")
                                if not hum or hum.Health > 0 then
                                    local targetPos = getAimPosition(Origin, HitPart)
                                    local finalOrigin = Origin
                                    if SilentAimSettings.MagicBullet then
                                        local toTarget = (targetPos - Origin)
                                        if toTarget.Magnitude > 2 then
                                            finalOrigin = targetPos - (toTarget.Unit * 1.5)
                                        end
                                    end
                                    local newDirection = getRaycastDirection(finalOrigin, targetPos, Direction)
                                    
                                    if hitboxEnabled then
                                        local redirectedHitbox = tryHitboxExpand(finalOrigin, newDirection, RayParams)
                                        if redirectedHitbox then
                                            return redirectedHitbox
                                        end
                                    end

                                    local finalRayParams = RayParams
                                    if RayParams and typeof(RayParams) == "RaycastParams" and SilentAimSettings.RaycastIgnoreSelf then
                                        if LocalPlayer.Character and RayParams.FilterType == Enum.RaycastFilterType.Exclude then
                                            local filter = RayParams.FilterDescendantsInstances
                                            if not table.find(filter, LocalPlayer.Character) then
                                                local clonedParams = RaycastParams.new()
                                                clonedParams.FilterType = RayParams.FilterType
                                                clonedParams.IgnoreWater = RayParams.IgnoreWater
                                                clonedParams.CollisionGroup = RayParams.CollisionGroup
                                                local newFilter = table.clone(filter)
                                                table.insert(newFilter, LocalPlayer.Character)
                                                clonedParams.FilterDescendantsInstances = newFilter
                                                finalRayParams = clonedParams
                                            end
                                        end
                                    end

                                    return originalRaycast(self, finalOrigin, newDirection, finalRayParams, ...)
                                end
                            end
                        end
                    end
                end
            end
            return originalRaycast(self, Origin, Direction, RayParams, ...)
        end))
    end
end)

