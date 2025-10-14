-- AutoCollectModule.lua
local module = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- ?? T? d?ng l?y remotes t? DataService
local modules = {
	data_manager = ReplicatedStorage.Modules.DataService,
}
local remotes = {}
do
	local remote_added = getconnections(modules.data_manager.DescendantAdded)[1].Function
	local r_keys = getupvalue(remote_added, 1)
	for remote_key, remote_name in next, getupvalue(getupvalue(remote_added, 2), 1) do
		local short = remote_name:sub(1, 2) == "F_" and remote_name:sub(3) or remote_name
		remotes[short] = r_keys[remote_key]
	end
end

-- ?? L?c danh sách player có plot (b? qua chính mình)
local function getPlayersWithPlot()
	local names = {}
	local localName = Players.LocalPlayer.Name
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Name ~= localName then
			local plot = Workspace.Plots:FindFirstChild("Plot_" .. player.Name)
			if plot then
				table.insert(names, player.Name)
			end
		end
	end
	return names
end

-- ?? Teleport t?i plot c?a player
local function TeleportToPlayerPlot(targetName)
	if not targetName or targetName == "" then
		warn("[TeleportToPlayerPlot] ? Không có tên ngu?i choi du?c nh?p.")
		return false
	end

	local plotName = "Plot_" .. targetName
	local plot = Workspace.Plots:FindFirstChild(plotName)
	if not plot then
		warn("[TeleportToPlayerPlot] ? Không tìm th?y plot c?a " .. targetName)
		return false
	end

	pcall(function()
		remotes.ToPlot:InvokeServer({ Player = targetName })
	end)
	print("[TeleportToPlayerPlot] ? Teleported to " .. targetName .. "'s plot.")
	task.wait(3) -- d?i teleport ?n d?nh
	return true
end

-- ?? Teleport + Interact v?i Trick or Treat Station
local function InteractWithPlayerStation(playerName)
	if not TeleportToPlayerPlot(playerName) then return end

	local plot = Workspace.Plots:FindFirstChild("Plot_" .. playerName)
	if not plot then
		warn("[InteractWithPlayerStation] ? Plot not found for player:", playerName)
		return
	end

	local station = plot:FindFirstChild("House")
		and plot.House:FindFirstChild("FrontObjects")
		and plot.House.FrontObjects:FindFirstChild("ItemHolder")
		and plot.House.FrontObjects.ItemHolder:FindFirstChild("Trick or Treat Station")

	if not station then
		warn("[InteractWithPlayerStation] ? Trick or Treat Station not found for player:", playerName)
		return
	end

	task.wait(0.6)
	pcall(function()
		remotes.Interact:FireServer({
			Target = station,
			Path = "1"
		})
	end)

	print("[InteractWithPlayerStation] ?? Interacted with Trick or Treat Station of", playerName)
end

-- ?? Auto Collect Loop
local running = false
local thread

function module.startAutoCollect()
	if running then
		warn("[AutoCollect] ?? Already running!")
		return
	end
	running = true

	thread = task.spawn(function()
		while running do
			local players = getPlayersWithPlot()
			print("[AutoCollect] ?? Found", #players, "players with plots.")
			for _, name in ipairs(players) do
				if not running then break end
				InteractWithPlayerStation(name)
				task.wait(1.8) -- delay gi?a m?i player
			end
			task.wait(5) -- delay gi?a m?i vòng quét
		end
	end)

	print("[AutoCollect] ? Started auto collect.")
end

function module.stopAutoCollect()
	if not running then
		warn("[AutoCollect] ?? Not running!")
		return
	end
	running = false
	print("[AutoCollect] ?? Stopped auto collect.")
end

return module
