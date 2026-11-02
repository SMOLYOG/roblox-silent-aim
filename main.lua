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
    
    ClassName = "Universal Silent Aim - Watermark Fix",
    ToggleKey = "RightAlt",
    
    TeamCheck = false,
    VisibleCheck = false, 
    TargetPart = "HumanoidRootPart",
    SilentAimMethod = "Raycast",
    
    FOVRadius = 600,
    FOVVisible = false,
    ShowSilentAimTarget = false, 
    
    MouseHitPrediction = false,
    MouseHitPredictionAmount = 0.165,
    DynamicPrediction = true,
    BulletSpeed = 3000,
    BulletDrop = 0,
    HitChance = 100,
    MagicBullet = false
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
local GetPlayers = Players.GetPlayers
local WorldToViewportPoint = Camera.WorldToViewportPoint
local GetPartsObscuringTarget = Camera.GetPartsObscuringTarget
local FindFirstChild = game.FindFirstChild
local RenderStepped = RunService.RenderStepped
local GetMouseLocation = UserInputService.GetMouseLocation

local ValidTargetParts = {"Head", "HumanoidRootPart"}
local PredictionAmount = 0.165

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

local ExpectedArguments = {
    FindPartOnRayWithIgnoreList = { ArgCountRequired = 3, Args = { "Instance", "Ray", "table", "boolean", "boolean" } },
    FindPartOnRayWithWhitelist = { ArgCountRequired = 3, Args = { "Instance", "Ray", "table", "boolean" } },
    FindPartOnRay = { ArgCountRequired = 2, Args = { "Instance", "Ray", "Instance", "boolean", "boolean" } },
    Raycast = { ArgCountRequired = 3, Args = { "Instance", "Vector3", "Vector3", "RaycastParams" } }
}

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

local function ValidateArguments(Args, RayMethod)
    local Matches = 0
    if #Args < RayMethod.ArgCountRequired then return false end
    for Pos, Argument in next, Args do
        if typeof(Argument) == RayMethod.Args[Pos] then Matches = Matches + 1 end
    end
    return Matches >= RayMethod.ArgCountRequired
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

local function getAimPosition(Origin, HitPart)
    local targetPos = HitPart.Position
    local distance = (targetPos - Origin).Magnitude
    local vel = HitPart.AssemblyLinearVelocity or HitPart.Velocity or Vector3.new(0, 0, 0)

    local dynPred = Toggles and Toggles.DynamicPred and Toggles.DynamicPred.Value
    if dynPred then
        local speed = (Options and Options.BulletSpeed and Options.BulletSpeed.Value) or SilentAimSettings.BulletSpeed or 3000
        local travelTime = distance / math.max(speed, 1)
        if distance > 150 then vel = vel * 0.75 end
        targetPos = targetPos + (vel * travelTime)
    end

    return targetPos
end

local function getDirection(Origin, Position, OriginalDirection)
    local unit = (Position - Origin).Unit
    local dist = (Position - Origin).Magnitude
    local origMag = OriginalDirection and OriginalDirection.Magnitude or 1000
    local finalLength = math.max(origMag, dist + 200, 15000)
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
    
    local targetName = (Options and Options.TargetPart and Options.TargetPart.Value) or SilentAimSettings.TargetPart
    local PlayerRoot = PlayerCharacter:FindFirstChild(targetName) or PlayerCharacter:FindFirstChild("HumanoidRootPart") or PlayerCharacter:FindFirstChild("Head")
    if not PlayerRoot then return false end 
    
    local CastPoints, IgnoreList = {PlayerRoot.Position, LocalPlayerCharacter, PlayerCharacter}, {LocalPlayerCharacter, PlayerCharacter}
    local ObscuringObjects = #GetPartsObscuringTarget(Camera, CastPoints, IgnoreList)
    
    return ObscuringObjects == 0
end

local function getClosestPlayer()
    local targetPartOpt = (Options and Options.TargetPart and Options.TargetPart.Value) or SilentAimSettings.TargetPart
    if not targetPartOpt then return nil end
    local Closest
    local DistanceToMouse = 999999

    for _, Player in next, Players:GetPlayers() do
        if Player == LocalPlayer then continue end
        if Toggles and Toggles.TeamCheck and Toggles.TeamCheck.Value and Player.Team == LocalPlayer.Team then continue end

        local Character = Player.Character
        if not Character then continue end
        
        local visCheck = Toggles and Toggles.VisibleCheck and Toggles.VisibleCheck.Value
        if visCheck and not IsPlayerVisible(Player) then continue end

        local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart") or Character:FindFirstChild("Head") or Character:FindFirstChild("UpperTorso")
        local Humanoid = Character:FindFirstChildOfClass("Humanoid")
        if not HumanoidRootPart or not Humanoid or Humanoid.Health <= 0 then continue end

        local ScreenPosition, OnScreen = getPositionOnScreen(HumanoidRootPart.Position)
        local mousePos = getMousePosition()
        local Distance = (mousePos - ScreenPosition).Magnitude
        
        local maxRadius = (Options and Options.Radius and Options.Radius.Value) or SilentAimSettings.FOVRadius or 600
        if Distance <= maxRadius then
            if targetPartOpt == "Random" then
                local chosenPartName = ValidTargetParts[math.random(1, #ValidTargetParts)]
                Closest = Character:FindFirstChild(chosenPartName) or HumanoidRootPart
            else
                Closest = Character:FindFirstChild(targetPartOpt) or Character:FindFirstChild("HumanoidRootPart") or Character:FindFirstChild("Head")
            end
            if Closest then
                DistanceToMouse = Distance
            end
        end
    end
    return Closest
end

-- UI Creating & Handling (Bez Watermarka powodującego błąd)
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/Library.lua"))()

local Window = Library:CreateWindow({Title = 'Universal Silent Aim', Center = true, AutoShow = true, TabPadding = 8, MenuFadeTime = 0.2})
local GeneralTab = Window:AddTab("General")
local ConfigsTab = Window:AddTab("Configs")
local SettingsTab = Window:AddTab("Settings")

local MainBOX = GeneralTab:AddLeftTabbox("Main") do
    local Main = MainBOX:AddTab("Main")
    
    Main:AddToggle("aim_Enabled", {Text = "Enabled"}):AddKeyPicker("aim_Enabled_KeyPicker", {Default = "RightAlt", SyncToggleState = true, Mode = "Toggle", Text = "Enabled", NoUI = false});
    Options.aim_Enabled_KeyPicker:OnClick(function()
        SilentAimSettings.Enabled = not SilentAimSettings.Enabled
        Toggles.aim_Enabled.Value = SilentAimSettings.Enabled
        Toggles.aim_Enabled:SetValue(SilentAimSettings.Enabled)
        mouse_box.Visible = SilentAimSettings.Enabled
    end)
    
    Main:AddToggle("TeamCheck", {Text = "Team Check", Default = SilentAimSettings.TeamCheck}):OnChanged(function() SilentAimSettings.TeamCheck = Toggles.TeamCheck.Value end)
    Main:AddToggle("VisibleCheck", {Text = "Visible Check", Default = SilentAimSettings.VisibleCheck}):OnChanged(function() SilentAimSettings.VisibleCheck = Toggles.VisibleCheck.Value end)
    Main:AddToggle("MagicBullet", {Text = "Magic Bullet (Przez ściany)", Default = SilentAimSettings.MagicBullet}):OnChanged(function() SilentAimSettings.MagicBullet = Toggles.MagicBullet.Value end)
    Main:AddDropdown("TargetPart", {AllowNull = false, Text = "Target Part", Default = SilentAimSettings.TargetPart, Values = {"Head", "HumanoidRootPart", "Random"}}):OnChanged(function()
        if Options and Options.TargetPart then
            SilentAimSettings.TargetPart = Options.TargetPart.Value
        end
    end)
    Main:AddDropdown("Method", {AllowNull = false, Text = "Silent Aim Method", Default = SilentAimSettings.SilentAimMethod, Values = {"Raycast","FindPartOnRay","FindPartOnRayWithWhitelist","FindPartOnRayWithIgnoreList","Mouse.Hit/Target"}}):OnChanged(function()
        if Options and Options.Method then
            SilentAimSettings.SilentAimMethod = Options.Method.Value
        end
    end)
    Main:AddSlider('HitChance', {Text = 'Hit chance', Default = 100, Min = 0, Max = 100, Rounding = 1, Compact = false}):OnChanged(function() SilentAimSettings.HitChance = Options.HitChance.Value end)
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
    
    local PredictionTab = FieldOfViewBOX:AddTab("Prediction")
    PredictionTab:AddToggle("DynamicPred", {Text = "Dynamic Distance Prediction", Default = true}):OnChanged(function() SilentAimSettings.DynamicPrediction = Toggles.DynamicPred.Value end)
    PredictionTab:AddSlider("BulletSpeed", {Text = "Bullet Speed (studs/s)", Min = 500, Max = 20000, Default = 3000, Rounding = 0}):OnChanged(function() SilentAimSettings.BulletSpeed = Options.BulletSpeed.Value end)
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
            if Options.LoadConfigurationDropdown then Options.LoadConfigurationDropdown:SetValues(GetFiles()) end
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
            if Toggles.TeamCheck then Toggles.TeamCheck:SetValue(SilentAimSettings.TeamCheck) end
            if Toggles.VisibleCheck then Toggles.VisibleCheck:SetValue(SilentAimSettings.VisibleCheck) end
            if Toggles.MagicBullet then Toggles.MagicBullet:SetValue(SilentAimSettings.MagicBullet) end
            if Options.TargetPart then Options.TargetPart:SetValue(SilentAimSettings.TargetPart) end
            if Options.Method then Options.Method:SetValue(SilentAimSettings.SilentAimMethod) end
            if Toggles.Visible then Toggles.Visible:SetValue(SilentAimSettings.FOVVisible) end
            if Options.Radius then Options.Radius:SetValue(SilentAimSettings.FOVRadius) end
            if Toggles.MousePosition then Toggles.MousePosition:SetValue(SilentAimSettings.ShowSilentAimTarget) end
            if Options.HitChance then Options.HitChance:SetValue(SilentAimSettings.HitChance) end
        end
    end)
end

-- Zakładka Settings (Eject)
local UnloadConnection
local function UnloadScript()
    pcall(function()
        if UnloadConnection then UnloadConnection:Disconnect() end
        if mouse_box then mouse_box:Remove() end
        if fov_circle then fov_circle:Remove() end
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
    local aimEnabled = Toggles and Toggles.aim_Enabled and Toggles.aim_Enabled.Value
    if aimEnabled then
        CachedTarget = getClosestPlayer()
    else
        CachedTarget = nil
    end

    local showTarget = Toggles and Toggles.MousePosition and Toggles.MousePosition.Value
    if showTarget and aimEnabled then
        if CachedTarget and CachedTarget.Parent then 
            local Root = CachedTarget.Parent.PrimaryPart or CachedTarget
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
end)

local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(...)
    local Method = getnamecallmethod()
    local Arguments = {...}
    local self = Arguments[1]
    local chance = CalculateChance(SilentAimSettings.HitChance)
    
    local aimEnabled = Toggles and Toggles.aim_Enabled and Toggles.aim_Enabled.Value
    local currentMethod = (Options and Options.Method and Options.Method.Value) or SilentAimSettings.SilentAimMethod
    
    if aimEnabled and self == workspace and not checkcaller() and chance == true then
        if Method == "FindPartOnRayWithIgnoreList" and currentMethod == Method then
            if ValidateArguments(Arguments, ExpectedArguments.FindPartOnRayWithIgnoreList) then
                local A_Ray = Arguments[2]
                if not IsCameraRay(A_Ray.Origin, A_Ray.Direction) then
                    local HitPart = CachedTarget
                    if HitPart and HitPart.Parent then
                        local Origin = A_Ray.Origin
                        local Direction = getDirection(Origin, getAimPosition(Origin, HitPart), A_Ray.Direction)
                        Arguments[2] = Ray.new(Origin, Direction)
                        return oldNamecall(unpack(Arguments))
                    end
                end
            end
        elseif Method == "FindPartOnRayWithWhitelist" and currentMethod == Method then
            if ValidateArguments(Arguments, ExpectedArguments.FindPartOnRayWithWhitelist) then
                local A_Ray = Arguments[2]
                if not IsCameraRay(A_Ray.Origin, A_Ray.Direction) then
                    local HitPart = CachedTarget
                    if HitPart and HitPart.Parent then
                        local Origin = A_Ray.Origin
                        local Direction = getDirection(Origin, getAimPosition(Origin, HitPart), A_Ray.Direction)
                        Arguments[2] = Ray.new(Origin, Direction)
                        return oldNamecall(unpack(Arguments))
                    end
                end
            end
        elseif (Method == "FindPartOnRay" or Method == "findPartOnRay") and currentMethod:lower() == Method:lower() then
            if ValidateArguments(Arguments, ExpectedArguments.FindPartOnRay) then
                local A_Ray = Arguments[2]
                if not IsCameraRay(A_Ray.Origin, A_Ray.Direction) then
                    local HitPart = CachedTarget
                    if HitPart and HitPart.Parent then
                        local Origin = A_Ray.Origin
                        local Direction = getDirection(Origin, getAimPosition(Origin, HitPart), A_Ray.Direction)
                        Arguments[2] = Ray.new(Origin, Direction)
                        return oldNamecall(unpack(Arguments))
                    end
                end
            end
        elseif Method == "Raycast" and currentMethod == Method then
            if ValidateArguments(Arguments, ExpectedArguments.Raycast) then
                local A_Origin = Arguments[2]
                local A_Direction = Arguments[3]
                if not IsCameraRay(A_Origin, A_Direction) then
                    local HitPart = CachedTarget
                    if HitPart and HitPart.Parent then
                        Arguments[3] = getDirection(A_Origin, getAimPosition(A_Origin, HitPart), A_Direction)
                        return oldNamecall(unpack(Arguments))
                    end
                end
            end
        end
    end
    return oldNamecall(...)
end))

local oldIndex = nil 
oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, Index)
    local aimEnabled = Toggles and Toggles.aim_Enabled and Toggles.aim_Enabled.Value
    local currentMethod = (Options and Options.Method and Options.Method.Value) or SilentAimSettings.SilentAimMethod
    
    if self == Mouse and not checkcaller() and aimEnabled and currentMethod == "Mouse.Hit/Target" and CachedTarget then
        local HitPart = CachedTarget
        if HitPart and HitPart.Parent then
            local originPos = (Camera and Camera.CFrame.Position) or HitPart.Position
            local aimPos = getAimPosition(originPos, HitPart)
             
            if Index == "Target" or Index == "target" then 
                return HitPart
            elseif Index == "Hit" or Index == "hit" then 
                local vel = HitPart.AssemblyLinearVelocity or HitPart.Velocity or Vector3.new(0, 0, 0)
                local predActive = Toggles and Toggles.Prediction and Toggles.Prediction.Value
                return ((predActive and (HitPart.CFrame + (vel * PredictionAmount))) or (not predActive and HitPart.CFrame))
            elseif Index == "X" or Index == "x" then 
                return oldIndex(self, Index)
            elseif Index == "Y" or Index == "y" then 
                return oldIndex(self, Index)
            elseif Index == "UnitRay" then 
                local origin = oldIndex(self, "Origin").Position
                return Ray.new(origin, (aimPos - origin).Unit)
            end
        end
    end

    return oldIndex(self, Index)
end))
