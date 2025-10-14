local AutoCollect = {}
local running = false
local currentTarget = nil
local thread

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")

-- ?? Init
local function init()
	local player = Players.LocalPlayer
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")
	local root = character:WaitForChild("HumanoidRootPart")

	local gameFolder = workspace:WaitForChild("_game")
	local spawnedItems = gameFolder:WaitForChild("SpawnedItems")

	local function getItemFolder()
		local folder = spawnedItems:FindFirstChild("itemDrop")
		while not folder do
			task.wait(1)
			folder = spawnedItems:FindFirstChild("itemDrop")
		end
		return folder
	end

	return {
		player = player,
		character = character,
		humanoid = humanoid,
		root = root,
		getItemFolder = getItemFolder
	}
end

-- ?? Nearest item
local function getNearestBlock(root, itemFolder)
	local nearest, minDist = nil, math.huge
	for _, item in pairs(itemFolder:GetChildren()) do
		if item:IsA("BasePart") then
			local dist = (item.Position - root.Position).Magnitude
			if dist < minDist then
				minDist = dist
				nearest = item
			end
		end
	end
	return nearest
end

-- ?? MoveTo with timeout
local function goTo(humanoid, root, block)
	if not block or not block:IsA("BasePart") then return false end

	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = false,
		CostMultiplier = 1,
	})

	path:ComputeAsync(root.Position, block.Position)
	if path.Status ~= Enum.PathStatus.Success then
		return false
	end

	for _, wp in ipairs(path:GetWaypoints()) do
		humanoid:MoveTo(wp.Position)

		-- timeout 5s tránh k?t
		local reached = humanoid.MoveToFinished:Wait(5)
		if not reached or not block.Parent then
			return false
		end
	end
	return true
end

-- ?? Auto loop
local function main(env)
	local humanoid = env.humanoid
	local root = env.root
	local getItemFolder = env.getItemFolder
	local itemFolder = getItemFolder()

	while running do
		-- Folder respawn ? l?y l?i
		if not itemFolder or not itemFolder.Parent then
			itemFolder = getItemFolder()
			task.wait(0.5)
		end

		local target = getNearestBlock(root, itemFolder)
		if target then
			currentTarget = target
			local ok = goTo(humanoid, root, target)
			if not ok then
				task.wait(0.2)
			end
		else
			task.wait(1) -- không có item ? ch?
		end
	end
end

-- ?? Start auto collect
function AutoCollect.startAutoFarm()
	if running then return end
	running = true
	print("?? AutoCollect started")
	local env = init()

	thread = task.spawn(function()
		while running do
			local ok, err = pcall(main, env)
			if not ok then
				warn("[AutoCollect] Error:", err)
				task.wait(1)
			end
		end
	end)
end

-- ?? Stop
function AutoCollect.stopAutoFarm()
	running = false
	if thread then
		task.cancel(thread)
		thread = nil
	end
	print("?? AutoCollect stopped")
end

return AutoCollect
