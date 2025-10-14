local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hrp = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")

local interaction_module = require(player.PlayerScripts.Modules.InteractionHandler)
local controlModule = require(player.PlayerScripts.PlayerModule.ControlModule)
local keyboardController = controlModule.activeController

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local dataManager = ReplicatedStorage.Modules.DataService

local remotes = {}

-- Hook vào DescendantAdded d? l?y remote functions
local remote_added = getconnections(dataManager.DescendantAdded)[1].Function
local r_keys = getupvalue(remote_added, 1)

for remote_key, remote_name in next, getupvalue(getupvalue(remote_added, 2), 1) do
	remotes[remote_name:sub(1, 2) == "F_" and remote_name:sub(3) or remote_name] = r_keys[remote_key]
end

local AutoPizza = {}

-- Config
AutoPizza.speed = 0.1

local turnRate = 0.2
-- State
local moped = nil
local body = nil
local firstTimeUsingMoped = true

local running = false
local deliveryLoopThread = nil

-- Utils
local function updateMopedAndBody()
	local playerFolder = Workspace:FindFirstChild(player.Name)
	if playerFolder then
		local newMoped = playerFolder:FindFirstChild("Vehicle_Delivery Moped")
		if newMoped and newMoped.Parent then
			moped = newMoped
			body = moped:FindFirstChild("Body") or moped.PrimaryPart
		else
			moped = nil
			body = nil
		end
	else
		moped = nil
		body = nil
	end
end

-- Pathfinding to position for humanoid (walking)
local function pathToPositionHumanoid(destination)
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		AgentCanClimb = true,
	})
	local success, err = pcall(function()
		path:ComputeAsync(hrp.Position, destination)
	end)
	if not success or path.Status ~= Enum.PathStatus.Success then
		warn("Pathfinding humanoid failed:", err or path.Status.Name)
		return false
	end
	local waypoints = path:GetWaypoints()
	for _, wp in ipairs(waypoints) do
		if not running then
			return false
		end
		humanoid:MoveTo(wp.Position)
		if not humanoid.MoveToFinished:Wait() then
			warn("Failed to reach waypoint", wp.Position)
			return false
		end
	end
	return true
end

-- Quick interact helper
local function quickInteract(model, actionText, specificPart)
	local part = specificPart
		or model.PrimaryPart
		or model:FindFirstChildOfClass("MeshPart")
		or model:FindFirstChildWhichIsA("BasePart")
	if not part then
		warn("No part to interact with on", model.Name)
		return false
	end
	local oldId = getthreadidentity()
	setthreadidentity(2)
	interaction_module:ShowMenu(model, part.Position, part)
	setthreadidentity(oldId)

	local gui = player:WaitForChild("PlayerGui"):WaitForChild("_interactUI")
	local found = false
	local startTime = tick()

	while tick() - startTime < 3 do
		if not running then
			return false
		end
		for _, frame in ipairs(gui:GetChildren()) do
			local btn = frame:FindFirstChild("Button")
			local txtLbl = btn and btn:FindFirstChild("TextLabel")
			if txtLbl and txtLbl.Text == actionText then
				if typeof(firesignal) == "function" then
					firesignal(btn.Activated)
				elseif btn.Activated and typeof(btn.Activated.Fire) == "function" then
					btn.Activated:Fire()
				end
				found = true
				break
			end
		end
		if found then
			break
		end
		task.wait(0.1)
	end
	return found
end

-- Find player's folder in workspace
local function getPlayerFolder()
	local folder = Workspace:FindFirstChild(player.Name)
	if folder and (folder:IsA("Model") or folder:IsA("Folder")) then
		return folder
	end
	return nil
end

-- Get or spawn moped
local function getOrSpawnMoped()
	updateMopedAndBody()
	if moped and moped.Parent then
		return moped
	end

	-- Ði b? ra ch? spawn moped
	local spawnPos = Vector3.new(-57.44, 4.45, -26.28)
	local spawnModel = Workspace.Environment.Locations.City.PizzaPlanet.Geometry.DeliveryMoped

	if not pathToPositionHumanoid(spawnPos) then
		warn("Failed to path to moped spawn")
		return nil
	end

	if not quickInteract(spawnModel, "Use") then
		warn("Failed to interact with moped spawn")
		return nil
	end

	-- Ð?i moped xu?t hi?n
	local startWait = tick()
	while tick() - startWait < 10 do
		if not running then
			return nil
		end
		task.wait(0.2)
		updateMopedAndBody()
		if moped and moped.Parent then
			return moped
		end
	end

	warn("Timeout waiting for moped spawn")
	return nil
end

-- Rotate body towards a position
local function turnBodyTo(pos)
	if not body then
		return
	end
	local currentLook = body.CFrame.LookVector
	local targetDir = (Vector3.new(pos.X, body.Position.Y, pos.Z) - body.Position).Unit
	local angle = math.acos(currentLook:Dot(targetDir))

	-- If already facing ~correct direction, skip turning
	if angle < math.rad(10) then
		return
	end

	-- Adaptive turn rate based on angle
	local adaptiveRate = math.clamp(angle / math.pi, 0.05, turnRate)
	local targetCFrame = CFrame.lookAt(body.Position, body.Position + targetDir)
	body.CFrame = body.CFrame:Lerp(targetCFrame, adaptiveRate)
end

local function moveBodyForward(destination)
    if not body then
        return
    end

    local moveVec = Vector3.new(0, 0, -1)
    if destination then
        local dist = (body.Position - destination).Magnitude
        if dist < 15 then
            moveVec = Vector3.zero
        elseif dist < 30 then
            moveVec = Vector3.new(0, 0, -0.3)
        end
    end

    keyboardController.moveVector = moveVec
end



-- Move body forward for a distance (blocking)
local function moveForwardDistance(distance)
	if not body then
		return
	end
	local startPos = body.Position
	while (body.Position - startPos).Magnitude < distance do
		if not running then
			break
		end
		moveBodyForward()
		RunService.Heartbeat:Wait()
	end
end

local function pathfindMopedTo(destination)
	if not body then
		warn("No moped body for pathfinding")
		return false
	end

	local function computePath(startPos, endPos)
		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			WaypointSpacing = 1,
			AgentCanJump = false,
			AgentCanClimb = false,
		})

		local success, err = pcall(function()
			path:ComputeAsync(startPos, endPos)
		end)

		if not success or path.Status ~= Enum.PathStatus.Success then
			warn("Path computation failed:", err or path.Status.Name)
			return nil
		end

		local rawWaypoints = path:GetWaypoints()
		local filteredWaypoints = {}

		local lastY = startPos.Y
		for _, wp in ipairs(rawWaypoints) do
			if math.abs(wp.Position.Y - lastY) < 10 and wp.Position.Y < 100 then
				table.insert(filteredWaypoints, wp)
				lastY = wp.Position.Y
			else
				warn("?? B? qua waypoint cao/th?p quá:", wp.Position)
			end
		end

		if #filteredWaypoints < 2 then
			warn("? Không tìm du?c waypoint h?p l? sau khi l?c")
			return nil
		end

		return filteredWaypoints
	end

	local function recalculatePath()
		local newWaypoints = computePath(body.Position, destination)
		if newWaypoints then
			warn("?? Recalculated path successfully")
			return newWaypoints
		else
			warn("? Failed to recalculate path")
			return nil
		end
	end

	local waypoints = computePath(body.Position, destination)

	if not waypoints then
		warn("? Initial pathfinding failed, trying to move forward slightly and retry...")

		local function tryStepForwardAndRecompute(maxAttempts, stepDistance)
			for i = 1, maxAttempts do
				if not running then return nil end

				local startPos = body.Position
				while (body.Position - startPos).Magnitude < stepDistance do
					moveBodyForward()
					RunService.Heartbeat:Wait()
				end

				local newPath = computePath(body.Position, destination)
				if newPath then
					warn("? Pathfinding succeeded after step forward (attempt " .. i .. ")")
					return newPath
				else
					warn("?? Still failed (attempt " .. i .. ")")
				end
			end
			return nil
		end

		waypoints = tryStepForwardAndRecompute(2, 5)
	end

	if not waypoints then
		warn("? Pathfinding failed after step-forward retries")
		return false
	end

	local stuckTimer = 0
	local lastPos = body.Position
	local stuckCount = 0
	local currentIndex = 1
	local frameCounter = 0 -- Gi? l?i frameCounter

	while currentIndex <= #waypoints do
		if not running then return false end -- Luôn ki?m tra running ? d?u

		local wp = waypoints[currentIndex]
		local shouldReset = false

		-- Vòng l?p chính d? di chuy?n t?i 1 waypoint
		while (body.Position - wp.Position).Magnitude > 12 do
			if not running then return false end

			-- Logic phanh khi g?n d?n dích cu?i cùng (gi? nguyên, dã t?t)
			if destination and (body.Position - destination).Magnitude < 15 then
				print("?? G?n d?n customer, gi? phanh d?n khi d?ng h?n.")
				keyboardController.moveVector = Vector3.new(0, 0, 0.3)
				local startBrake = tick()
				while running and (body.Velocity.Magnitude > 1) and tick() - startBrake < 2 do
					task.wait() -- Dùng task.wait() cho g?n
				end
				keyboardController.moveVector = Vector3.zero
				return true
			end

			-- Ði?u khi?n xe
			turnBodyTo(wp.Position)
			moveBodyForward()

			-- Ch? 1 frame và l?y deltaTime (th?i gian gi?a 2 frame)
			local deltaTime = RunService.Heartbeat:Wait()

			frameCounter += 1
			-- CH? KI?M TRA K?T XE M?I 5 FRAME d? gi?m t?i
			if frameCounter >= 5 then
				frameCounter = 0 -- Reset b? d?m
				local moveDelta = (body.Position - lastPos).Magnitude

				if moveDelta < 0.2 then -- Tang ngu?ng lên m?t chút
					stuckTimer += deltaTime * 5 -- C?ng d?n th?i gian dã trôi qua (5 frame)
					
					if stuckTimer > 0.5 then -- Tang th?i gian ch? lên m?t chút
						stuckCount += 1
						stuckTimer = 0
						warn("?? Moped seems stuck. Attempt:", stuckCount)

						-- LOGIC X? LÝ K?T XE ÐON GI?N HON VÀ HI?U QU? HON
						if stuckCount >= 2 then
							warn("?? Reversing to unstuck...")
							-- Di chuy?n lùi l?i 1.5 giây
							local startT = tick()
							while tick() - startT < 1.5 do
								if not running then return false end
								keyboardController.moveVector = Vector3.new(0, 0, 1)
								task.wait()
							end
							keyboardController.moveVector = Vector3.zero

							-- Sau khi lùi, tính toán l?i du?ng di
							task.wait(0.2) -- Ð?i m?t chút d? xe ?n d?nh
							local newWaypoints = recalculatePath()
							if newWaypoints then
								warn("? Path recalculated after reversing!")
								waypoints = newWaypoints
								currentIndex = 1
								stuckCount = 0
								shouldReset = true
								break -- Thoát vòng l?p di chuy?n t?i waypoint này
							else
								warn("? Failed pathfinding after reversing. Skipping delivery.")
								return false -- B? cu?c
							end
						end
					end
				else
					-- N?u di chuy?n du?c thì reset h?t
					stuckTimer = 0
					stuckCount = 0
					lastPos = body.Position
				end
			end
		end

		local nextWP = waypoints[currentIndex + 1]
		if running and body and body.Velocity.Magnitude > 15 and nextWP then
			local distToNext = (body.Position - nextWP.Position).Magnitude
			if distToNext > 15 then -- Ch? phanh n?u s?p di do?n dài
				print("?? Gi? phanh nh? sau waypoint...")
				local brakeStart = tick()
				while tick() - brakeStart < 0.3 and body.Velocity.Magnitude > 2 do
					keyboardController.moveVector = Vector3.new(0, 0, 3)
					RunService.Heartbeat:Wait()
				end
				keyboardController.moveVector = Vector3.zero
			end
		end


		if not shouldReset then
			currentIndex += 1
		end
	end

	return true
end



-- Check if moped body is on ground (raycast)
local function isBodyOnGround()
	if not body then
		return false
	end
	local origin = body.Position
	local ray = workspace:Raycast(origin, Vector3.new(0, -5, 0))
	return ray ~= nil
end

-- Find closest pizza box to reference part
local function findClosestPizzaBox(referencePart)
	local conveyor = Workspace.Environment.Locations.City.PizzaPlanet.Interior.Conveyor.MovingBoxes
	local closestBox = nil
	local closestDist = math.huge
	for _, obj in ipairs(conveyor:GetChildren()) do
		if obj.Name:match("^PizzaBox") then
			local part = obj:IsA("BasePart") and obj or obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
			if part then
				local dist = (part.Position - referencePart.Position).Magnitude
				if dist < closestDist then
					closestDist = dist
					closestBox = part
				end
			end
		end
	end
	return closestBox
end

-- Prepare moped before moving
local function prepareMopedAndDrive(destination)
	if not moped or not body then
		warn("Missing moped or body")
		return false
	end

	local startWait = tick()
	while not isBodyOnGround() do
		if not running then
			return false
		end
		if tick() - startWait > 5 then
			break
		end
		task.wait(0.2)
	end

	if firstTimeUsingMoped then
		moveForwardDistance(1)
		firstTimeUsingMoped = false
		task.wait(1)
	end

	return pathfindMopedTo(destination)
end

local function waitForCustomer(timeout)
	local folder = Workspace._game.SpawnedCharacters
	local name = "PizzaPlanetDeliveryCustomer"

	for _, c in ipairs(folder:GetChildren()) do
		if c.Name == name and c:FindFirstChild("HumanoidRootPart") then
			return c
		end
	end

	local found = nil
	local start = tick()
	local conn
	conn = folder.ChildAdded:Connect(function(c)
		if c.Name == name then
			local hrp = c:WaitForChild("HumanoidRootPart", 2)
			if hrp then
				found = c
			end
		end
	end)

	while not found and tick() - start < (timeout or 8) do
		if not running then
			break
		end
		task.wait(0.1)
	end

	if conn then
		conn:Disconnect()
	end
	return found
end

local function findSpawnedCustomer()
	local folder = Workspace._game:FindFirstChild("SpawnedCharacters")
	if not folder then
		return nil
	end

	for _, c in ipairs(folder:GetChildren()) do
		if c.Name == "PizzaPlanetDeliveryCustomer" and c:FindFirstChild("HumanoidRootPart") then
			return c
		end
	end

	return nil
end

local function grabPizzaBox()
	-- print("?? Grabbing pizza box...")
	repeat
		local boxes = workspace.Environment.Locations.City.PizzaPlanet.Interior.Conveyor.MovingBoxes:GetChildren()
		if #boxes > 0 then
			for _, box in ipairs(boxes) do
				local _, customerId = remotes.TakePizzaBox:InvokeServer({ Box = box })
				if customerId then
					return customerId
				end
				task.wait(0.5)
			end
		else
			task.wait(0.5)
		end
	until player.Character:FindFirstChild("Pizza Box")
end

-- ?? Get customer model
local function getCustomerModel(customerId)
	local model = nil
	repeat
		model = nil
		for _, m in ipairs(workspace._game.SpawnedCharacters:GetChildren()) do
			if m.Name == "PizzaPlanetDeliveryCustomer" and m:GetAttribute("_customerPosition") == customerId then
				model = m
				break
			end
		end
		if not model then
			task.wait(0.1)
		end
	until model ~= nil
	return model
end

local function getValidCustomerModel()
	local customerId, model

	repeat
		customerId = grabPizzaBox()
		model = getCustomerModel(customerId)

		if not model or not model.PrimaryPart then
			warn("Invalid customer model, retrying grab...")
			task.wait(1)
		end
	until model and model.PrimaryPart

	return customerId, model
end

-- Main loop to run auto delivery
local function deliveryLoop()
    local pickupPos = Vector3.new(-53.24, 4.75, -43.27)
    local noPathFails = 0

    while running do
        updateMopedAndBody()
        if not moped or not moped.Parent then
            print("No moped found, trying to get one...")
            moped = getOrSpawnMoped()
            if not moped then
                warn("Failed to get moped, retrying in 5s")
                task.wait(5)
                continue
            end
            body = moped:FindFirstChild("Body") or moped.PrimaryPart
            if not body then
                warn("Moped has no body, retry in 5s")
                task.wait(5)
                continue
            end
        end

        -- Ði d?n ch? l?y pizza
        if not prepareMopedAndDrive(pickupPos) then
            warn("Failed to drive to pizza pickup, retry 5s")
            task.wait(5)
            continue
        end

		-- L?y pizza box
		local customer, customerModel = getValidCustomerModel()

		keyboardController.moveVector = Vector3.new(0, 0, 1) -- lùi 2s
		task.wait(2)
		keyboardController.moveVector = Vector3.zero

		if customerModel then
			local customerPos = customerModel.PrimaryPart and customerModel.PrimaryPart.Position
			if customerPos then
				local distanceToCustomer = (body.Position - customerPos).Magnitude
				print("?? Found customer. Distance:", math.floor(distanceToCustomer))
			end
		end

        local customerCF = customerModel.PrimaryPart and customerModel.PrimaryPart.CFrame
            or customerModel:GetModelCFrame()

        if not customerCF or not customerCF.Position then
            warn("Invalid customer position, skipping")
            task.wait(1)
            continue
        end

		if not prepareMopedAndDrive(customerCF.Position) then
			warn("? Failed to reach customer, skipping this delivery")
			noPathFails += 1
			if noPathFails >= 3 then
				warn("Too many failed attempts to reach customer. Skipping...")
				noPathFails = 0
				task.wait(1)
				continue
			end
			task.wait(5)
			continue
		end



        noPathFails = 0 -- Reset l?i n?u di du?c

        task.wait(1) -- Ð?i ?n d?nh tru?c khi tuong tác
        remotes.DeliverPizza:FireServer({ Customer = customerModel })
        print("? Delivered to:", customerModel)

        -- Quay v? ch? l?y pizza
        if not prepareMopedAndDrive(pickupPos) then
            warn("Failed to return to pickup, retry 5s")
            task.wait(5)
            continue
        end

        print("Delivery cycle complete, restarting soon...")
        task.wait(2)
    end
end

function AutoPizza.startAutoFarm()
	if running then
		print("AutoPizza already running, stopping previous loop...")
		AutoPizza.stopAutoFarm()
		task.wait(0.5) -- d?i loop cu thoát h?n
	end

	running = true
	firstTimeUsingMoped = true
	updateMopedAndBody()

	deliveryLoopThread = task.spawn(deliveryLoop)
	print("AutoPizza started")
end

function AutoPizza.stopAutoFarm()
	if not running then
		print("AutoPizza is not running")
		return
	end
	running = false
	if deliveryLoopThread then
		-- deliveryLoop s? t? thoát khi running = false
		deliveryLoopThread = nil
	end
	keyboardController.moveVector = Vector3.zero
	print("AutoPizza stopped")
end

return AutoPizza