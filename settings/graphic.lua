local RunService = game:GetService("RunService")

local M = {}
local lowpolyEnabled = false
local addedConnection

-- Whitelist folder (kh�ng xo� texture/mesh b�n trong)
local gameFolder = workspace:FindFirstChild("_game")
local oreFolder = gameFolder and gameFolder:FindFirstChild("Folder")

-- ===== Helper: Ki?m tra c� n?m trong whitelist kh�ng =====
local function isWhitelisted(obj)
    return oreFolder and obj:IsDescendantOf(oreFolder)
end

-- ===== Helper: Simplify Object =====
local function simplifyObject(obj)
    if not obj or not obj.Parent then return end
    if isWhitelisted(obj) then return end

    if obj:IsA("BasePart") then
        for _, child in ipairs(obj:GetChildren()) do
            if child:IsA("Texture") or child:IsA("Decal") or child:IsA("SurfaceAppearance") then
                child:Destroy()
            end
        end
        obj.Material = Enum.Material.SmoothPlastic
        if obj:IsA("MeshPart") then
            obj.TextureID = ""
        end

    elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
        obj.Enabled = false

    elseif obj:IsA("PostEffect") then
        obj.Enabled = false
    end
end

-- ===== Apply Lowpoly (once + future objects) =====
local function applyLowpoly()
    if lowpolyEnabled then return end
    lowpolyEnabled = true

    -- Duy?t qua to�n b? object (theo coroutine d? tr�nh lag)
    task.spawn(function()
        local objs = workspace:GetDescendants()
        for i = 1, #objs do
            simplifyObject(objs[i])
            if i % 100 == 0 then
                task.wait() -- ng?t frame d? kh�ng treo game
            end
        end
    end)

    -- �on gi?n ho� object m?i spawn sau
    addedConnection = workspace.DescendantAdded:Connect(function(obj)
        if lowpolyEnabled then
            task.defer(function()
                simplifyObject(obj)
            end)
        end
    end)
end

-- ===== Restore Graphics =====
local function restoreGraphics()
    lowpolyEnabled = false
    if addedConnection then
        addedConnection:Disconnect()
        addedConnection = nil
    end
    if setfpscap then setfpscap(360) end
end

-- ===== Public API =====
function M.setPotatoMode(state: boolean)
    if state then
        applyLowpoly()
        if setfpscap then setfpscap(30) end
    else
        restoreGraphics()
    end
end

return M
