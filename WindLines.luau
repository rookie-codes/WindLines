--[[
    WindLines Module
    ----------------
    Creates animated wind line visual effects in the 3D world using Attachments and Trails.
    Designed for use in open environments to simulate wind gusts, breezes, or magical effects.

    == Features ==
    - Spawns animated wind lines at a configurable rate and direction.
    - Each wind line is a Trail between two Attachments, animated in 3D space.
    - Fully customizable via settings: lifetime, direction, speed, spawn rate, and position.
    - Handles cleanup and efficient memory management.

    == API ==

    module:Init(Settings)
        Initializes the wind line system and starts spawning wind lines.
        - Settings (table):
            - Lifetime (number): How long each wind line lasts (seconds). Default: 3
            - Direction (Vector3): Direction the wind lines move. Default: Vector3.new(1,0,0)
            - Speed (number): How fast wind lines move. Default: 6
            - SpawnRate (number): How many wind lines spawn per second. Default: 25

        Example:
            local WindLines = require(game.ReplicatedStorage.Packages.WindLines)
            WindLines:Init({
                Lifetime = 2.5,
                Direction = Vector3.new(0,1,0),
                Speed = 8,
                SpawnRate = 30,
            })

    module:Cleanup()
        Stops the wind line system and removes all active wind lines.

        Example:
            WindLines:Cleanup()

    module:Create(Settings)
        Spawns a single wind line with optional custom settings.
        - Settings (table, optional):
            - Lifetime (number): Override for this wind line's lifetime.
            - Position (Vector3): World position to spawn the wind line. Default: random in front of camera.
            - Direction (Vector3): Override for this wind line's direction.
            - Speed (number): Override for this wind line's speed.

        Example:
            WindLines:Create({
                Position = Vector3.new(0, 20, 0),
                Direction = Vector3.new(1, 0, 0),
                Speed = 10,
                Lifetime = 2,
            })

    == Usage Notes ==
    - The module automatically parents Attachments and Trails to the Terrain object in Workspace.
    - Call :Cleanup() before re-initializing to avoid duplicate update loops.
    - Designed for use on the server or client, but typically used on the client for visual effects.

    == Example Full Usage ==
        local WindLines = require(game.ReplicatedStorage.Packages.WindLines)
        WindLines:Init({
            Lifetime = 3,
            Direction = Vector3.new(1,0,0),
            Speed = 6,
            SpawnRate = 25,
        })

        -- To spawn a custom wind line at a specific position:
        WindLines:Create({
            Position = Vector3.new(0, 10, 0),
            Direction = Vector3.new(0,1,0),
            Speed = 12,
            Lifetime = 1.5,
        })

        -- To stop all wind lines:
        WindLines:Cleanup()
]]

local RunService = game:GetService("RunService")
local Terrain = workspace:FindFirstChildOfClass("Terrain")

local EMPTY_TABLE = {}
local OFFSET = Vector3.new(0, 0.1, 0)

local module = {}

module.UpdateQueue = table.create(10)

function module:Init(Settings)
	-- Set defaults
	module.Lifetime = Settings.Lifetime or 3
	module.Direction = Settings.Direction or Vector3.new(1, 0, 0)
	module.Speed = Settings.Speed or 6

	-- Clear any old stuff
	if module.UpdateConnection then
		module.UpdateConnection:Disconnect()
		module.UpdateConnection = nil
	end

	for _, WindLine in ipairs(module.UpdateQueue) do
		WindLine.Attachment0:Destroy()
		WindLine.Attachment1:Destroy()
		WindLine.Trail:Destroy()
	end
	table.clear(module.UpdateQueue)

	module.LastSpawned = os.clock()
	local SpawnRate = 1 / (Settings.SpawnRate or 25)

	-- Setup logic loop
	module.UpdateConnection = RunService.Heartbeat:Connect(function()
		local Clock = os.clock()

		-- Spawn handler
		if Clock - module.LastSpawned > SpawnRate then
			module:Create()
			module.LastSpawned = Clock
		end

		-- Update queue handler
		debug.profilebegin("Wind Lines")
		for i, WindLine in ipairs(module.UpdateQueue) do
			local AliveTime = Clock - WindLine.StartClock
			if AliveTime >= WindLine.Lifetime then
				-- Destroy the objects
				WindLine.Attachment0:Destroy()
				WindLine.Attachment1:Destroy()
				WindLine.Trail:Destroy()

				-- unordered remove at this index
				local Length = #module.UpdateQueue
				module.UpdateQueue[i] = module.UpdateQueue[Length]
				module.UpdateQueue[Length] = nil

				continue
			end

			WindLine.Trail.MaxLength = 20 - (20 * (AliveTime / WindLine.Lifetime))

			local SeededClock = (Clock + WindLine.Seed) * (WindLine.Speed * 0.2)
			local StartPos = WindLine.Position
			WindLine.Attachment0.WorldPosition = (CFrame.new(StartPos, StartPos + WindLine.Direction) * CFrame.new(
				0,
				0,
				WindLine.Speed * -AliveTime
			)).Position + Vector3.new(
				math.sin(SeededClock) * 0.5,
				math.sin(SeededClock) * 0.8,
				math.sin(SeededClock) * 0.5
			)

			WindLine.Attachment1.WorldPosition = WindLine.Attachment0.WorldPosition + OFFSET
		end
		debug.profileend()
	end)
end

function module:Cleanup()
	if module.UpdateConnection then
		module.UpdateConnection:Disconnect()
		module.UpdateConnection = nil
	end

	for _, WindLine in ipairs(module.UpdateQueue) do
		WindLine.Attachment0:Destroy()
		WindLine.Attachment1:Destroy()
		WindLine.Trail:Destroy()
	end
	table.clear(module.UpdateQueue)
end

function module:Create(Settings)
	debug.profilebegin("Add Wind Line")

	Settings = Settings or EMPTY_TABLE

	local Lifetime = Settings.Lifetime or module.Lifetime
	local Position = Settings.Position
		or (
				workspace.CurrentCamera.CFrame
				* CFrame.Angles(math.rad(math.random(-30, 70)), math.rad(math.random(-80, 80)), 0)
			)
			* CFrame.new(0, 0, math.random(200, 600) * -0.1).Position
	local Direction = Settings.Direction or module.Direction
	local Speed = Settings.Speed or module.Speed
	if Speed <= 0 then
		return
	end

	local Attachment0 = Instance.new("Attachment")
	local Attachment1 = Instance.new("Attachment")

	local Trail = Instance.new("Trail")
	Trail.Attachment0 = Attachment0
	Trail.Attachment1 = Attachment1
	Trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.2, 1),
		NumberSequenceKeypoint.new(0.8, 1),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	Trail.Transparency = NumberSequence.new(0.7)
	Trail.FaceCamera = true
	Trail.Parent = Attachment0
	Trail.Texture = "rbsassetid://5320412027"

	Attachment0.WorldPosition = Position
	Attachment1.WorldPosition = Position + OFFSET

	local WindLine = {
		Attachment0 = Attachment0,
		Attachment1 = Attachment1,
		Trail = Trail,
		Lifetime = Lifetime + (math.random(-10, 10) * 0.1),
		Position = Position,
		Direction = Direction,
		Speed = Speed + (math.random(-10, 10) * 0.1),
		StartClock = os.clock(),
		Seed = math.random(1, 1000) * 0.1,
	}

	module.UpdateQueue[#module.UpdateQueue + 1] = WindLine

	Attachment0.Parent = Terrain
	Attachment1.Parent = Terrain

	debug.profileend()
end

return module
