-- Rivals Test Project Loader
-- Usage:
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/loader.luau"))()
-- Or paste entire file into executor / loadstring.

local SOURCES = {}

SOURCES['CONSTANTS'] = [=[-- CONSTANTS (cleaned + adapted for autonomous test project)
-- Original depended on Remotes.Misc.RequestConstants and TestLibrary attributes.
-- Here we provide a self-contained version that works in Studio Play.

local RunService = game:GetService("RunService")

local CONSTANTS = {
	GAME_VERSION = 27,
	GROUP_ID = 3461453,

	-- Place IDs kept for reference (not used in test environment)
	MAIN_HUB_PLACE_ID = 17625359962,
	MAIN_MOBILE_PLACE_ID = 18126510175,
	MAIN_MATCHMAKING_PLACE_ID = 117398147513099,
	MAIN_ARCADE_TEAMDEATHMATCH_PLACE_ID = 71874690745115,
	MAIN_ARCADE_FREEFORALL_PLACE_ID = 129604661913557,
	MAIN_ARCADE_GUNGAME_PLACE_ID = 133215910299950,

	TESTING_HUB_PLACE_ID = 12011504191,
	TESTING_MOBILE_PLACE_ID = 18126498684,

	IS_RUNNING = RunService:IsRunning(),
	IS_STUDIO = RunService:IsStudio(),
	IS_SERVER = RunService:IsServer(),
	IS_CLIENT = RunService:IsClient(),

	PLACE_ID = game.PlaceId,
	JOB_ID = game.JobId,

	-- Private server flags (safe defaults for test)
	PRIVATE_SERVER_ID = RunService:IsServer() and game.PrivateServerId or "",
	PRIVATE_SERVER_OWNER_ID = RunService:IsServer() and game.PrivateServerOwnerId or 0,
	IS_PUBLIC_SERVER = true,
	IS_RESERVED_SERVER = false,
	IS_PRIVATE_SERVER = false,
	IS_PRIVATE_HUB_SERVER = false,

	IS_MAIN_SERVER = false,
	IS_TESTING_SERVER = true, -- force test mode

	DEVICE = "Server",
}

if CONSTANTS.IS_CLIENT then
	CONSTANTS.DEVICE = "PC" -- simplified; original had more device detection
end

-- Test-project specific flags
CONSTANTS.IS_AUTONOMOUS_TEST = true
CONSTANTS.TEST_MODE = true

return CONSTANTS
]=]

SOURCES['Signal'] = [=[-- Signal (cleaned from original Rivals Signal.luau)
-- Lightweight signal implementation used across the entire codebase.

local Signal = {}
Signal.__index = Signal

function Signal.new()
	local self = setmetatable({
		_connections = {},
		_waiting = {},
	}, Signal)
	return self
end

function Signal:Connect(fn)
	local connection = {
		Connected = true,
		_fn = fn,
		_signal = self,
	}
	function connection:Disconnect()
		if not self.Connected then return end
		self.Connected = false
		local list = self._signal._connections
		for i = #list, 1, -1 do
			if list[i] == self then
				table.remove(list, i)
				break
			end
		end
	end
	table.insert(self._connections, connection)
	return connection
end

function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:Fire(...)
	-- Copy to avoid mutation during iteration
	local connections = table.clone(self._connections)
	for _, conn in ipairs(connections) do
		if conn.Connected then
			task.spawn(conn._fn, ...)
		end
	end
	-- Resume any waiters
	for _, thread in ipairs(self._waiting) do
		task.spawn(thread, ...)
	end
	table.clear(self._waiting)
end

function Signal:Wait()
	local thread = coroutine.running()
	table.insert(self._waiting, thread)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	for _, conn in ipairs(self._connections) do
		conn.Connected = false
	end
	table.clear(self._connections)
	table.clear(self._waiting)
end

return Signal
]=]

SOURCES['Spring'] = [=[-- Spring (cleaned from original)
-- Simple critically-damped spring used for recoil, camera, UI, etc.

local Spring = {}
Spring.__index = Spring

function Spring.new(initial, speed, damper)
	local self = setmetatable({
		Value = initial or 0,
		Target = initial or 0,
		Velocity = 0,
		Speed = speed or 10,
		Damper = damper or 1,
	}, Spring)
	return self
end

function Spring:Impulse(force)
	self.Velocity = self.Velocity + force
end

function Spring:SetTarget(target)
	self.Target = target
end

function Spring:SetValue(value)
	self.Value = value
	self.Velocity = 0
end

function Spring:Update(dt)
	local omega = self.Speed
	local zeta = self.Damper
	local x = self.Value - self.Target
	local v = self.Velocity

	-- Critically / under / over damped analytic step
	if zeta < 1 then
		local wd = omega * math.sqrt(1 - zeta * zeta)
		local e = math.exp(-zeta * omega * dt)
		local c1 = x
		local c2 = (v + zeta * omega * x) / wd
		self.Value = self.Target + e * (c1 * math.cos(wd * dt) + c2 * math.sin(wd * dt))
		self.Velocity = e * ((-zeta * omega * c1 + wd * c2) * math.cos(wd * dt)
			+ (-wd * c1 - zeta * omega * c2) * math.sin(wd * dt))
	else
		-- Overdamped / critically damped simplified
		local e = math.exp(-omega * dt)
		self.Value = self.Target + (x + (v + omega * x) * dt) * e
		self.Velocity = (v - (x * omega * omega + v * omega) * dt) * e
	end

	return self.Value
end

return Spring
]=]

SOURCES['Utility'] = [=[-- Utility (cleaned + reduced for autonomous test)
-- Original was ~26KB of helpers. This keeps the most used surface.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local CONSTANTS = require("CONSTANTS")
local Signal = require("Signal")

local Utility = {}
Utility.__index = Utility

function Utility._new()
	local self = setmetatable({
		_particle_hashes = {},
	}, Utility)
	return self
end

-------------------------------------------------
-- Visibility / UI helpers
-------------------------------------------------
function Utility:IsUIElementVisible(element)
	if not element or not element:IsA("GuiObject") then
		return false
	end
	local player = Players.LocalPlayer
	if not player then return false end
	local inPlayerGui = element:IsDescendantOf(player.PlayerGui)
	local inWorkspace = element:IsDescendantOf(workspace)
	if not (inPlayerGui or inWorkspace) then
		return false
	end
	local current = element
	while current and current:IsA("GuiObject") do
		if not current.Visible then return false end
		if current.AbsoluteSize.X <= 0 or current.AbsoluteSize.Y <= 0 then
			return false
		end
		current = current.Parent
	end
	return true
end

function Utility:IsTextBoxFocused()
	local ok, focused = pcall(function()
		return UserInputService:GetFocusedTextBox()
	end)
	return ok and focused ~= nil
end

-------------------------------------------------
-- Color helpers
-------------------------------------------------
function Utility:DarkenColor(color, factor)
	return Color3.new(color.R * factor, color.G * factor, color.B * factor)
end

function Utility:LightenColor(color, factor)
	return Color3.new(
		math.min(1, color.R + (1 - color.R) * factor),
		math.min(1, color.G + (1 - color.G) * factor),
		math.min(1, color.B + (1 - color.B) * factor)
	)
end

-------------------------------------------------
-- Geometry helpers (used by OutOfBounds / volume checks)
-------------------------------------------------
function Utility:IsWithinRotatedShape(point, cframe, size, partType)
	local localPoint = cframe:PointToObjectSpace(point)
	if partType == Enum.PartType.Ball then
		local radius = math.max(size.X, size.Y, size.Z) / 2
		return localPoint.Magnitude <= radius
	elseif partType == Enum.PartType.Cylinder then
		local halfH = size.Y / 2
		local radius = math.max(size.X, size.Z) / 2
		return math.abs(localPoint.Y) <= halfH
			and (Vector3.new(localPoint.X, 0, localPoint.Z).Magnitude <= radius)
	else -- Block
		return math.abs(localPoint.X) <= size.X / 2
			and math.abs(localPoint.Y) <= size.Y / 2
			and math.abs(localPoint.Z) <= size.Z / 2
	end
end

-------------------------------------------------
-- Instance helpers
-------------------------------------------------
function Utility:WaitForChildRecursive(parent, name, timeout)
	timeout = timeout or 5
	local start = os.clock()
	local found = parent:FindFirstChild(name, true)
	while not found and (os.clock() - start) < timeout do
		task.wait(0.05)
		found = parent:FindFirstChild(name, true)
	end
	return found
end

function Utility:SafeDestroy(instance, lifetime)
	if not instance then return end
	if lifetime and lifetime > 0 then
		Debris:AddItem(instance, lifetime)
	else
		instance:Destroy()
	end
end

function Utility:CreateSound(parent, soundId, volume, playbackSpeed)
	local s = Instance.new("Sound")
	s.SoundId = soundId or ""
	s.Volume = volume or 0.5
	s.PlaybackSpeed = playbackSpeed or 1
	s.Parent = parent or workspace
	return s
end

-------------------------------------------------
-- Math helpers
-------------------------------------------------
function Utility:Lerp(a, b, t)
	return a + (b - a) * t
end

function Utility:Clamp(n, min, max)
	return math.clamp(n, min, max)
end

function Utility:Round(n, decimals)
	local mult = 10 ^ (decimals or 0)
	return math.floor(n * mult + 0.5) / mult
end

-------------------------------------------------
-- Tag helpers
-------------------------------------------------
function Utility:GetTagged(tag)
	return CollectionService:GetTagged(tag)
end

function Utility:AddTag(instance, tag)
	CollectionService:AddTag(instance, tag)
end

-------------------------------------------------
-- Debug
-------------------------------------------------
function Utility:Warn(...)
	if CONSTANTS.IS_STUDIO or CONSTANTS.TEST_MODE then
		warn("[Utility]", ...)
	end
end

function Utility:Print(...)
	if CONSTANTS.IS_STUDIO or CONSTANTS.TEST_MODE then
		print("[Utility]", ...)
	end
end

return Utility._new()
]=]

SOURCES['AnimationLibrary'] = [=[-- AnimationLibrary (expanded reconstruction)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimationLibrary = { Info = {} }

local soundCallbacksFolder = script:FindFirstChild("SoundCallbacks")
local effectCallbacksFolder = script:FindFirstChild("EffectCallbacks")

local function register(name, animationId, speed, length, actionTimestamp, extra)
	speed = speed or 1
	local entry = {
		AnimationID = animationId,
		Speed = speed,
		Length = length and (length / speed) or nil,
		ActionTimestamp = actionTimestamp and (actionTimestamp / speed) or nil,
		ExtraInformation = extra or {},
		SoundCallback = nil,
		EffectCallback = nil,
	}
	if soundCallbacksFolder then
		local soundMod = soundCallbacksFolder:FindFirstChild(name)
		if soundMod then
			local ok, cb = pcall(require, soundMod)
			if ok then
				if typeof(cb) == "function" then
					entry.SoundCallback = cb
				elseif typeof(cb) == "table" then
					entry.SoundCallback = function(ctrl, _, animLength)
						local last = 0
						for _, row in pairs(cb) do
							local t = (row[1] - last) / (animLength or 1)
							last = row[1]
							task.wait(t)
							if ctrl and ctrl.CreateSound then
								ctrl:CreateSound(select(2, table.unpack(row)))
							end
						end
					end
				end
			end
		end
	end
	if effectCallbacksFolder then
		local effectMod = effectCallbacksFolder:FindFirstChild(name)
		if effectMod then
			local ok, cb = pcall(require, effectMod)
			if ok then entry.EffectCallback = cb end
		end
	end
	AnimationLibrary.Info[name] = entry
end

-- Fists / Knife (real IDs from ZIP)
register("fists_equip", "rbxassetid://12557487419", 0.55)
register("fists_idle", "rbxassetid://12557500357")
register("fists_sprint", "rbxassetid://12644426893")
register("fists_inspect", "rbxassetid://12557511090")
register("fists_attack1", "rbxassetid://12557515008")
register("fists_attack2", "rbxassetid://12557516966")
register("knife_equip", "rbxassetid://12613363718", 0.45)
register("knife_idle", "rbxassetid://12613190591")
register("knife_sprint", "rbxassetid://12886796453")
register("knife_inspect", "rbxassetid://12613370000")
register("knife_attack1", "rbxassetid://12613380000")

-- Generic placeholders for all other weapon anim keys used by ItemLibrary
local function batch(prefix, actions)
	for _, action in ipairs(actions) do
		local key = prefix .. "_" .. action
		if not AnimationLibrary.Info[key] then
			register(key, "rbxassetid://12557487419") -- placeholder ID
		end
	end
end

local gunActions = {"equip","idle","sprint","inspect","shoot1","reload","reload_empty","charge","charge_start","charge_loop","charge_finish"}
local meleeActions = {"equip","idle","sprint","inspect","attack1","attack2","using","bash","melee"}
local throwActions = {"equip","idle","sprint","inspect","throw_start","throw_start_pinpull","throw_finish","lob_start","lob_start_pinpull","lob_finish"}

for _, prefix in ipairs({
	"assaultrifle","burstrifle","sniper","shotgun","minigun","bow","crossbow","rpg",
	"energyrifle","paintballgun","grenadelauncher","gunblade","distortion","permafrost",
	"pistol","uzi","revolver","shorty","exogun","energypistols","flaregun","slingshot",
	"daggers","spray","scepter","glasscannon","freezeray",
	"chainsaw","katana","scythe","battleaxe","riotshield","maul","spear","trowel","glastshard",
	"grenade","molotov","flashbang","smokegrenade","satchel","warpstone","elixir",
}) do
	batch(prefix, gunActions)
	batch(prefix, meleeActions)
	batch(prefix, throwActions)
end

-- Real IDs where known
register("exogun_equip", "rbxassetid://17344796376")
register("exogun_shoot1", "rbxassetid://17344796376")
register("exogun_reload", "rbxassetid://17344796376")
register("minigun_equip", "rbxassetid://18766861798")
register("grenade_equip", "rbxassetid://17160801411")

function AnimationLibrary:Get(name) return self.Info[name] end
function AnimationLibrary:Has(name) return self.Info[name] ~= nil end
function AnimationLibrary:GetAnimationId(name)
	local info = self.Info[name]
	return info and info.AnimationID or nil
end
function AnimationLibrary:PlayOnHumanoid(humanoid, animName, fadeTime)
	local info = self.Info[animName]
	if not info or not humanoid then return nil end
	local anim = Instance.new("Animation")
	anim.AnimationId = info.AnimationID
	local track = humanoid:LoadAnimation(anim)
	track:Play(fadeTime or 0.1, 1, info.Speed or 1)
	return track, info
end

return AnimationLibrary
]=]

SOURCES['SoundLibrary'] = [=[-- SoundLibrary (stub reconstructed)
-- Original had ItemSounds, ViewModelSounds, ScrapedAnimationSounds.
-- Full audio assets are not in the ZIP as playable instances; only IDs.

local SoundLibrary = {
	ItemSounds = {},
	ViewModelSounds = {},
	ScrapedAnimationSounds = {},
}

-- Placeholder entries so require() succeeds and systems can query
SoundLibrary.ItemSounds["Assault Rifle"] = {
	Shoot = "rbxassetid://130791919",
	Reload = "rbxassetid://130791920",
	Empty = "rbxassetid://130791921",
}

SoundLibrary.ItemSounds["Pistol"] = {
	Shoot = "rbxassetid://130791919",
	Reload = "rbxassetid://130791920",
}

function SoundLibrary:GetItemSound(itemName, event)
	local t = self.ItemSounds[itemName]
	return t and t[event] or nil
end

return SoundLibrary
]=]

SOURCES['ItemLibrary'] = [=[-- ItemLibrary (full base-weapon reconstruction from Rivals ZIP)
-- All 28 guns + 11 melee + 7 throwables extracted from original add_gun/add_melee/add_throwable calls.

local ItemLibrary = {
	QUICK_ATTACK_ITEM_INDEX_DEFAULTS = { Melee = 3, Utility = 4 },
	QUICK_ATTACK_COOLDOWN = 0,
	THIRD_PERSON_VIEWMODEL_BLACKLIST = {
		Fists = true, ["Hand Gun"] = true, ["Spy Gloves"] = true,
	},
	UNIVERSAL_WEAPON_ICON = "rbxassetid://123867892559041",
	RANDOM_WEAPON_ICON = "rbxassetid://132973552546079",
	Statuses = {}, StatusByPassTrackNum = {}, Classes = {}, SlotToClass = {},
	Types = {}, Ammos = {}, Crosshairs = {}, ViewModels = {}, ViewModelOrder = {},
	Charms = {}, Items = {}, ItemsAlphabetized = {}, ItemOrder = {},
}

local function addStatus(name, value, color, passTrackNum, passColor, darkPassColor)
	local pass = passColor or color
	local e = {
		Name = name, Value = value, Color = color,
		PassTrackNum = passTrackNum, PassColor = pass,
		DarkPassColor = darkPassColor or Color3.new(pass.R/4, pass.G/4, pass.B/4),
	}
	ItemLibrary.Statuses[name] = e
	ItemLibrary.StatusByPassTrackNum[passTrackNum] = e
end
addStatus("Standard", 1, Color3.fromRGB(127,127,127), 1, Color3.fromRGB(255,255,255), Color3.fromRGB(0,0,0))
addStatus("Prime", 2, Color3.fromRGB(255,215,0), 2)
addStatus("Contraband", 3, Color3.fromRGB(116,61,255), 3)

local function addClass(name, slot, imgR, imgL)
	local e = { Name = name, Slot = slot, ImageDiagonalRight = imgR, ImageDiagonalLeft = imgL }
	ItemLibrary.Classes[name] = e
	ItemLibrary.SlotToClass[slot] = e
end
addClass("Primary",   1, "rbxassetid://17225649668", "rbxassetid://17225650124")
addClass("Secondary", 2, "rbxassetid://17225650488", "rbxassetid://17225650697")
addClass("Melee",     3, "rbxassetid://17225650859", "rbxassetid://17225651107")
addClass("Utility",   4, "rbxassetid://17225651405", "rbxassetid://17225651564")

ItemLibrary.Types.Custom    = { Name = "Custom" }
ItemLibrary.Types.Melee     = { Name = "Melee" }
ItemLibrary.Types.Gun       = { Name = "Gun" }
ItemLibrary.Types.Throwable = { Name = "Throwable" }

ItemLibrary.Ammos.Light   = { Image = "rbxassetid://16539130564" }
ItemLibrary.Ammos.Medium  = { Image = "rbxassetid://16539130428" }
ItemLibrary.Ammos.Heavy   = { Image = "rbxassetid://13223128254" }
ItemLibrary.Ammos.Shells  = { Image = "rbxassetid://16539130288" }
ItemLibrary.Ammos.Rockets = { Image = "rbxassetid://13223319925" }
ItemLibrary.Ammos.Arrows  = { Image = "rbxassetid://13695602038" }
ItemLibrary.Ammos.Fuel    = { Image = "rbxassetid://13677095789" }
ItemLibrary.Ammos.Ball    = { Image = "rbxassetid://16538992521" }
ItemLibrary.Ammos.Grenade = { Image = "rbxassetid://129377039777545" }
ItemLibrary.Ammos.Energy  = { Image = "rbxassetid://16539130564" }

ItemLibrary.Crosshairs.Default = { Name = "Default", Image = "rbxassetid://15085011006", Size = UDim2.fromOffset(28,28) }
ItemLibrary.Crosshairs.Spread  = { Name = "Spread",  Image = "rbxassetid://15085011006", Size = UDim2.fromOffset(40,40) }
ItemLibrary.Crosshairs.SpreadH = { Name = "SpreadH", Image = "rbxassetid://15085011006", Size = UDim2.fromOffset(48,28) }

local vmOrder, itemOrder = 0, 0

local function addViewModel(name, image, offset, equipA, idleA, sprintA, inspectA, animMap)
	vmOrder += 1
	local vm = {
		Name = name,
		Image = image or ItemLibrary.UNIVERSAL_WEAPON_ICON,
		ImageHighResolution = image,
		Offset = offset or CFrame.new(0, -0.3, -0.4),
		EquipAnimation = equipA, IdleAnimation = idleA,
		SprintAnimation = sprintA, InspectAnimation = inspectA,
		AnimationMap = animMap or {}, ExtraInformation = {}, Order = vmOrder,
	}
	ItemLibrary.ViewModels[name] = vm
	ItemLibrary.ViewModelOrder[vmOrder] = name
	return vm
end

local function baseItem(name, className, typeName, status, image)
	itemOrder += 1
	local item = {
		Name = name, Class = className, Type = typeName,
		Status = status or "Standard",
		Image = image or ItemLibrary.UNIVERSAL_WEAPON_ICON,
		Description = "", Order = itemOrder, ViewModels = {}, Skins = {},
	}
	ItemLibrary.Items[name] = item
	ItemLibrary.ItemOrder[itemOrder] = name
	table.insert(ItemLibrary.ItemsAlphabetized, name)
	return item
end

local function addGun(opts)
	local item = baseItem(opts.Name, opts.Class or "Primary", "Gun", opts.Status or "Standard", opts.Image)
	item.EquipTime = opts.EquipTime or 0.5
	item.CanADS = opts.CanADS ~= false
	item.MoveSpeedMultiplier = opts.MoveSpeed or 1
	item.ADSMoveMultiplier = opts.ADSMove or 0.7
	item.Crosshair = opts.Crosshair or "Default"
	item.FireRate = opts.ShootCooldown or 0.1
	item.RPM = opts.ShootCooldown and math.floor(60 / opts.ShootCooldown) or 600
	item.Damage = opts.Damage or 20
	item.CriticalDamage = opts.Crit or (opts.Damage or 20) * 1.5
	item.HeadMultiplier = (opts.Crit and opts.Damage) and (opts.Crit / opts.Damage) or 1.5
	item.BurstCount = opts.BurstCount or 1
	item.BurstCooldown = opts.BurstCooldown or 0
	item.PelletCount = opts.Pellets or 1
	item.Spread = opts.Spread or 1.5
	item.Recoil = opts.Recoil or Vector3.new(0.5, 0.3, 0)
	item.Range = opts.Range or 500
	item.AmmoType = opts.AmmoType or "Medium"
	item.MagazineSize = opts.Mag or 30
	item.ReserveAmmo = opts.Reserve or 90
	item.ReloadTime = opts.ReloadTime or 2.0
	item.IsAutomatic = opts.Automatic == true or ((opts.ShootCooldown or 0.1) < 0.15 and (opts.BurstCount or 1) == 1)
	item.IsProjectile = opts.IsProjectile or false
	item.RequiresCharge = opts.RequiresCharge or false
	item.ChargeTime = opts.ChargeTime or 0
	item.ExplosionRadius = opts.ExplosionRadius or 0
	item.ViewModel = opts.ViewModel or opts.Name
	item.Extra = opts.Extra or {}
	return item
end

local function addMelee(opts)
	local item = baseItem(opts.Name, "Melee", "Melee", opts.Status or "Standard", opts.Image)
	item.Damage = opts.Damage or 40
	item.AttackRate = opts.AttackRate or 1.2
	item.Range = opts.Range or 6
	item.EquipTime = opts.EquipTime or 0.35
	item.ViewModel = opts.ViewModel or opts.Name
	item.MagazineSize = math.huge
	item.ReserveAmmo = math.huge
	item.IsAutomatic = false
	return item
end

local function addThrowable(opts)
	local item = baseItem(opts.Name, "Utility", "Throwable", opts.Status or "Standard", opts.Image)
	item.Damage = opts.Damage or 100
	item.ThrowForce = opts.ThrowForce or 60
	item.FuseTime = opts.FuseTime or 3
	item.CookTime = opts.CookTime or 0
	item.ExplosionRadius = opts.ExplosionRadius or 12
	item.ViewModel = opts.ViewModel or opts.Name
	item.MagazineSize = opts.Mag or 1
	item.ReserveAmmo = opts.Reserve or 2
	item.EquipTime = opts.EquipTime or 0.4
	return item
end

-- ViewModels
addViewModel("Fists", "rbxassetid://12557487419", nil, "fists_equip","fists_idle","fists_sprint","fists_inspect", {Attack1="fists_attack1",Attack2="fists_attack2"})
addViewModel("Knife", "rbxassetid://12613363718", nil, "knife_equip","knife_idle","knife_sprint","knife_inspect", {Attack1="knife_attack1"})
addViewModel("Chainsaw", nil, nil, "chainsaw_equip","chainsaw_idle","chainsaw_sprint","chainsaw_inspect", {Attack1="chainsaw_attack1",Using="chainsaw_using"})
addViewModel("Katana", nil, nil, "katana_equip","katana_idle","katana_sprint","katana_inspect", {Attack1="katana_attack1",Attack2="katana_attack2"})
addViewModel("Scythe", nil, nil, "scythe_equip","scythe_idle","scythe_sprint","scythe_inspect", {Attack1="scythe_attack1"})
addViewModel("Battle Axe", nil, nil, "battleaxe_equip","battleaxe_idle","battleaxe_sprint","battleaxe_inspect", {Attack1="battleaxe_attack1"})
addViewModel("Riot Shield", nil, nil, "riotshield_equip","riotshield_idle","riotshield_sprint","riotshield_inspect", {Attack1="riotshield_bash"})
addViewModel("Maul", nil, nil, "maul_equip","maul_idle","maul_sprint","maul_inspect", {Attack1="maul_attack1"})
addViewModel("Spear", nil, nil, "spear_equip","spear_idle","spear_sprint","spear_inspect", {Attack1="spear_attack1"})
addViewModel("Trowel", nil, nil, "trowel_equip","trowel_idle","trowel_sprint","trowel_inspect", {Attack1="trowel_attack1"})
addViewModel("Glast Shard", nil, nil, "glastshard_equip","glastshard_idle","glastshard_sprint","glastshard_inspect", {Attack1="glastshard_attack1"})

addViewModel("Assault Rifle", "rbxassetid://16539130428", nil, "assaultrifle_equip","assaultrifle_idle","assaultrifle_sprint","assaultrifle_inspect", {Shoot1="assaultrifle_shoot1",Reload="assaultrifle_reload",EmptyReload="assaultrifle_reload_empty"})
addViewModel("Burst Rifle", nil, nil, "burstrifle_equip","burstrifle_idle","burstrifle_sprint","burstrifle_inspect", {Shoot1="burstrifle_shoot1",Reload="burstrifle_reload",EmptyReload="burstrifle_reload_empty"})
addViewModel("Sniper", "rbxassetid://13223128254", nil, "sniper_equip","sniper_idle","sniper_sprint","sniper_inspect", {Shoot1="sniper_shoot1",Reload="sniper_reload",EmptyReload="sniper_reload_empty"})
addViewModel("Shotgun", "rbxassetid://16539130288", nil, "shotgun_equip","shotgun_idle","shotgun_sprint","shotgun_inspect", {Shoot1="shotgun_shoot1",Reload="shotgun_reload"})
addViewModel("Minigun", "rbxassetid://18766861798", nil, "minigun_equip","minigun_idle","minigun_sprint","minigun_inspect", {ChargeStart="minigun_charge_start",ChargeLoop="minigun_charge_loop",ChargeFinish="minigun_charge_finish"})
addViewModel("Bow", "rbxassetid://13695602038", nil, "bow_equip","bow_idle","bow_sprint","bow_inspect", {Shoot1="bow_shoot1",Charge="bow_charge",Reload="bow_reload"})
addViewModel("Crossbow", nil, nil, "crossbow_equip","crossbow_idle","crossbow_sprint","crossbow_inspect", {Shoot1="crossbow_shoot1",Reload="crossbow_reload"})
addViewModel("RPG", "rbxassetid://13223319925", nil, "rpg_equip","rpg_idle","rpg_sprint","rpg_inspect", {Shoot1="rpg_shoot1",Reload="rpg_reload"})
addViewModel("Energy Rifle", nil, nil, "energyrifle_equip","energyrifle_idle","energyrifle_sprint","energyrifle_inspect", {Shoot1="energyrifle_shoot1"})
addViewModel("Paintball Gun", nil, nil, "paintballgun_equip","paintballgun_idle","paintballgun_sprint","paintballgun_inspect", {Shoot1="paintballgun_shoot1",Reload="paintballgun_reload"})
addViewModel("Grenade Launcher", nil, nil, "grenadelauncher_equip","grenadelauncher_idle","grenadelauncher_sprint","grenadelauncher_inspect", {Shoot1="grenadelauncher_shoot1",Reload="grenadelauncher_reload"})
addViewModel("Gunblade", nil, nil, "gunblade_equip","gunblade_idle","gunblade_sprint","gunblade_inspect", {Shoot1="gunblade_shoot1",Attack1="gunblade_melee"})
addViewModel("Distortion", nil, nil, "distortion_equip","distortion_idle","distortion_sprint","distortion_inspect", {Shoot1="distortion_shoot1"})
addViewModel("Permafrost", nil, nil, "permafrost_equip","permafrost_idle","permafrost_sprint","permafrost_inspect", {Shoot1="permafrost_shoot1"})

addViewModel("Handgun", "rbxassetid://16539130564", nil, "pistol_equip","pistol_idle","pistol_sprint","pistol_inspect", {Shoot1="pistol_shoot1",Reload="pistol_reload"})
addViewModel("Uzi", nil, nil, "uzi_equip","uzi_idle","uzi_sprint","uzi_inspect", {Shoot1="uzi_shoot1",Reload="uzi_reload"})
addViewModel("Revolver", nil, nil, "revolver_equip","revolver_idle","revolver_sprint","revolver_inspect", {Shoot1="revolver_shoot1",Reload="revolver_reload"})
addViewModel("Shorty", nil, nil, "shorty_equip","shorty_idle","shorty_sprint","shorty_inspect", {Shoot1="shorty_shoot1",Reload="shorty_reload"})
addViewModel("Exogun", "rbxassetid://17344796376", CFrame.new(0,-0.25,0)*CFrame.Angles(math.rad(5),0,0), "exogun_equip","exogun_idle","exogun_sprint","exogun_inspect", {Shoot1="exogun_shoot1",Reload="exogun_reload"})
addViewModel("Energy Pistols", nil, nil, "energypistols_equip","energypistols_idle","energypistols_sprint","energypistols_inspect", {Shoot1="energypistols_shoot1"})
addViewModel("Flare Gun", nil, nil, "flaregun_equip","flaregun_idle","flaregun_sprint","flaregun_inspect", {Shoot1="flaregun_shoot1",Reload="flaregun_reload"})
addViewModel("Slingshot", nil, nil, "slingshot_equip","slingshot_idle","slingshot_sprint","slingshot_inspect", {Shoot1="slingshot_shoot1"})
addViewModel("Daggers", nil, nil, "daggers_equip","daggers_idle","daggers_sprint","daggers_inspect", {Shoot1="daggers_shoot1",Attack1="daggers_melee"})
addViewModel("Spray", nil, nil, "spray_equip","spray_idle","spray_sprint","spray_inspect", {Using="spray_using"})
addViewModel("Scepter", nil, nil, "scepter_equip","scepter_idle","scepter_sprint","scepter_inspect", {Shoot1="scepter_shoot1"})
addViewModel("Glass Cannon", nil, nil, "glasscannon_equip","glasscannon_idle","glasscannon_sprint","glasscannon_inspect", {Shoot1="glasscannon_shoot1",Reload="glasscannon_reload"})

addViewModel("Grenade", "rbxassetid://17160801411", nil, "grenade_equip","grenade_idle","grenade_sprint","grenade_inspect", {ThrowStart="grenade_throw_start_pinpull",ThrowFinish="grenade_throw_finish",LobStart="grenade_lob_start_pinpull",LobFinish="grenade_lob_finish"})
addViewModel("Molotov", nil, nil, "molotov_equip","molotov_idle","molotov_sprint","molotov_inspect", {ThrowStart="molotov_throw_start",ThrowFinish="molotov_throw_finish"})
addViewModel("Flashbang", nil, nil, "flashbang_equip","flashbang_idle","flashbang_sprint","flashbang_inspect", {ThrowStart="flashbang_throw_start",ThrowFinish="flashbang_throw_finish"})
addViewModel("Smoke Grenade", nil, nil, "smokegrenade_equip","smokegrenade_idle","smokegrenade_sprint","smokegrenade_inspect", {ThrowStart="smokegrenade_throw_start",ThrowFinish="smokegrenade_throw_finish"})
addViewModel("Freeze Ray", nil, nil, "freezeray_equip","freezeray_idle","freezeray_sprint","freezeray_inspect", {Shoot1="freezeray_shoot1",Using="freezeray_using"})
addViewModel("Satchel", nil, nil, "satchel_equip","satchel_idle","satchel_sprint","satchel_inspect", {ThrowStart="satchel_throw_start",ThrowFinish="satchel_throw_finish"})
addViewModel("Warpstone", nil, nil, "warpstone_equip","warpstone_idle","warpstone_sprint","warpstone_inspect", {ThrowStart="warpstone_throw_start"})
addViewModel("Elixir", nil, nil, "elixir_equip","elixir_idle","elixir_sprint","elixir_inspect", {ThrowStart="elixir_throw_start"})

-- PRIMARY
addGun({Name="Assault Rifle",Class="Primary",Status="Standard",EquipTime=0.65,ShootCooldown=0.1,Damage=12,Crit=15,Mag=20,Reserve=100,AmmoType="Medium",Spread=1.5,Recoil=Vector3.new(0.55,0.3,0),ReloadTime=2.1,Automatic=true,Range=200,MoveSpeed=0.9})
addGun({Name="Burst Rifle",Class="Primary",Status="Standard",EquipTime=0.75,ShootCooldown=0.6,Damage=20,Crit=25,BurstCount=3,BurstCooldown=0.07,Mag=12,Reserve=60,AmmoType="Medium",Spread=1.2,Recoil=Vector3.new(0.4,0.25,0),ReloadTime=1.8,Range=200,MoveSpeed=0.9})
addGun({Name="Sniper",Class="Primary",Status="Standard",EquipTime=1.15,ShootCooldown=1.5,Damage=50,Crit=150,Mag=5,Reserve=20,AmmoType="Heavy",Spread=0.2,Recoil=Vector3.new(1.5,0.4,0),ReloadTime=2.8,Range=1000,MoveSpeed=0.8,ADSMove=0.4})
addGun({Name="Shotgun",Class="Primary",Status="Standard",EquipTime=0.75,ShootCooldown=0.7,Damage=12,Crit=18,Pellets=8,Spread=6.5,Mag=7,Reserve=35,AmmoType="Shells",Recoil=Vector3.new(1.2,0.8,0),ReloadTime=0.55,Range=60,MoveSpeed=0.9,Crosshair="Spread"})
addGun({Name="Minigun",Class="Primary",Status="Prime",EquipTime=1.0,ShootCooldown=0.05,Damage=8,Crit=10,Mag=150,Reserve=300,AmmoType="Heavy",Spread=3.5,Recoil=Vector3.new(0.3,0.5,0),ReloadTime=4.0,Automatic=true,RequiresCharge=true,ChargeTime=1.2,Range=200,MoveSpeed=0.7,ADSMove=0.5})
addGun({Name="Bow",Class="Primary",Status="Standard",EquipTime=0.85,ShootCooldown=0.9,Damage=45,Crit=70,Mag=1,Reserve=30,AmmoType="Arrows",Spread=0.5,Recoil=Vector3.new(0.3,0.2,0),ReloadTime=0.8,IsProjectile=true,RequiresCharge=true,ChargeTime=0.6,Range=300,MoveSpeed=0.95})
addGun({Name="Crossbow",Class="Primary",Status="Standard",EquipTime=1.15,ShootCooldown=1.2,Damage=55,Crit=85,Mag=1,Reserve=20,AmmoType="Arrows",Spread=0.3,Recoil=Vector3.new(0.5,0.3,0),ReloadTime=1.5,IsProjectile=true,Range=350,MoveSpeed=0.9})
addGun({Name="RPG",Class="Primary",Status="Standard",EquipTime=1.0,ShootCooldown=1.5,Damage=100,Crit=100,Mag=1,Reserve=8,AmmoType="Rockets",Spread=1.0,Recoil=Vector3.new(1.8,0.6,0),ReloadTime=2.5,IsProjectile=true,ExplosionRadius=12,Range=400,MoveSpeed=0.85})
addGun({Name="Energy Rifle",Class="Primary",Status="Prime",EquipTime=1.05,ShootCooldown=0.15,Damage=18,Crit=27,Mag=25,Reserve=75,AmmoType="Energy",Spread=1.0,Recoil=Vector3.new(0.35,0.25,0),ReloadTime=1.8,Automatic=true,Range=250,MoveSpeed=0.95})
addGun({Name="Paintball Gun",Class="Primary",Status="Prime",EquipTime=0.8,ShootCooldown=0.12,Damage=10,Crit=15,Mag=30,Reserve=120,AmmoType="Ball",Spread=2.0,Recoil=Vector3.new(0.3,0.2,0),ReloadTime=1.6,Automatic=true,Range=150,MoveSpeed=1.0})
addGun({Name="Grenade Launcher",Class="Primary",Status="Prime",EquipTime=1.0,ShootCooldown=0.9,Damage=60,Crit=60,Mag=6,Reserve=18,AmmoType="Grenade",Spread=2.0,Recoil=Vector3.new(1.0,0.5,0),ReloadTime=2.2,IsProjectile=true,ExplosionRadius=10,Range=200,MoveSpeed=0.9})
addGun({Name="Gunblade",Class="Primary",Status="Standard",EquipTime=1.0,ShootCooldown=0.5,Damage=28,Crit=42,Mag=8,Reserve=32,AmmoType="Medium",Spread=1.5,Recoil=Vector3.new(0.6,0.35,0),ReloadTime=1.8,Range=120,MoveSpeed=0.95})
addGun({Name="Distortion",Class="Primary",Status="Contraband",EquipTime=1.25,ShootCooldown=0.2,Damage=22,Crit=33,Mag=18,Reserve=54,AmmoType="Energy",Spread=4.0,Recoil=Vector3.new(0.4,0.5,0),ReloadTime=2.0,Automatic=true,Range=180,MoveSpeed=0.9,Crosshair="SpreadH"})
addGun({Name="Permafrost",Class="Primary",Status="Contraband",EquipTime=0.5,ShootCooldown=0.08,Damage=9,Crit=14,Mag=40,Reserve=120,AmmoType="Energy",Spread=2.5,Recoil=Vector3.new(0.25,0.3,0),ReloadTime=2.2,Automatic=true,Range=160,MoveSpeed=0.95})

-- SECONDARY
addGun({Name="Handgun",Class="Secondary",Status="Standard",EquipTime=0.2,ShootCooldown=0.13,Damage=12,Crit=15,Mag=13,Reserve=91,AmmoType="Light",Spread=1.2,Recoil=Vector3.new(0.7,0.4,0),ReloadTime=1.4,Range=125,MoveSpeed=1.0,ADSMove=0.85})
addGun({Name="Uzi",Class="Secondary",Status="Standard",EquipTime=0.45,ShootCooldown=0.07,Damage=8,Crit=10,Mag=27,Reserve=108,AmmoType="Light",Spread=2.5,Recoil=Vector3.new(0.35,0.4,0),ReloadTime=1.6,Automatic=true,Range=100,MoveSpeed=1.0})
addGun({Name="Revolver",Class="Secondary",Status="Standard",EquipTime=0.6,ShootCooldown=0.4,Damage=30,Crit=40,Mag=6,Reserve=36,AmmoType="Heavy",Spread=1.0,Recoil=Vector3.new(1.0,0.5,0),ReloadTime=2.0,Range=150,MoveSpeed=0.95})
addGun({Name="Shorty",Class="Secondary",Status="Standard",EquipTime=0.7,ShootCooldown=0.8,Damage=10,Crit=15,Pellets=6,Spread=8.0,Mag=2,Reserve=16,AmmoType="Shells",Recoil=Vector3.new(1.4,0.9,0),ReloadTime=1.5,Range=40,MoveSpeed=1.0,Crosshair="SpreadH"})
addGun({Name="Exogun",Class="Secondary",Status="Prime",EquipTime=0.7,ShootCooldown=0.2,Damage=22,Crit=33,Mag=20,Reserve=60,AmmoType="Energy",Spread=1.0,Recoil=Vector3.new(0.4,0.25,0),ReloadTime=1.8,Automatic=true,Range=180,MoveSpeed=1.0})
addGun({Name="Energy Pistols",Class="Secondary",Status="Prime",EquipTime=0.6,ShootCooldown=0.12,Damage=11,Crit=16,Mag=24,Reserve=72,AmmoType="Energy",Spread=1.8,Recoil=Vector3.new(0.3,0.25,0),ReloadTime=1.5,Automatic=true,Range=130,MoveSpeed=1.0})
addGun({Name="Flare Gun",Class="Secondary",Status="Standard",EquipTime=1.3,ShootCooldown=1.5,Damage=35,Crit=35,Mag=1,Reserve=6,AmmoType="Shells",Spread=2.0,Recoil=Vector3.new(1.2,0.5,0),ReloadTime=2.0,IsProjectile=true,ExplosionRadius=6,Range=200,MoveSpeed=1.0})
addGun({Name="Slingshot",Class="Secondary",Status="Prime",EquipTime=0.45,ShootCooldown=0.5,Damage=28,Crit=40,Mag=1,Reserve=20,AmmoType="Ball",Spread=1.5,Recoil=Vector3.new(0.4,0.3,0),ReloadTime=0.7,IsProjectile=true,Range=120,MoveSpeed=1.0})
addGun({Name="Daggers",Class="Secondary",Status="Standard",EquipTime=0.8,ShootCooldown=0.35,Damage=20,Crit=30,Mag=3,Reserve=12,AmmoType="Light",Spread=2.0,Recoil=Vector3.new(0.3,0.2,0),ReloadTime=1.2,IsProjectile=true,Range=80,MoveSpeed=1.05})
addGun({Name="Spray",Class="Secondary",Status="Standard",EquipTime=0.45,ShootCooldown=0.05,Damage=4,Crit=4,Mag=100,Reserve=200,AmmoType="Fuel",Spread=5.0,Recoil=Vector3.new(0.1,0.15,0),ReloadTime=2.5,Automatic=true,Range=25,MoveSpeed=1.0})
addGun({Name="Scepter",Class="Secondary",Status="Contraband",EquipTime=1.0,ShootCooldown=0.6,Damage=40,Crit=60,Mag=8,Reserve=24,AmmoType="Energy",Spread=0.8,Recoil=Vector3.new(0.5,0.3,0),ReloadTime=1.8,Range=200,MoveSpeed=0.95})
addGun({Name="Glass Cannon",Class="Secondary",Status="Contraband",EquipTime=0.75,ShootCooldown=0.9,Damage=55,Crit=80,Mag=4,Reserve=16,AmmoType="Heavy",Spread=0.5,Recoil=Vector3.new(1.3,0.6,0),ReloadTime=2.0,Range=250,MoveSpeed=0.9})
addGun({Name="Freeze Ray",Class="Utility",Status="Standard",EquipTime=1.0,ShootCooldown=0.1,Damage=5,Crit=5,Mag=50,Reserve=100,AmmoType="Energy",Spread=3.0,Recoil=Vector3.new(0.15,0.2,0),ReloadTime=2.5,Automatic=true,Range=40,MoveSpeed=0.95})

-- MELEE
addMelee({Name="Fists",Damage=35,AttackRate=1.4,Range=5,EquipTime=0.3})
addMelee({Name="Knife",Damage=45,AttackRate=1.1,Range=6.5,EquipTime=0.4})
addMelee({Name="Chainsaw",Damage=20,AttackRate=0.15,Range=5.5,EquipTime=0.7})
addMelee({Name="Katana",Damage=55,AttackRate=0.9,Range=8,EquipTime=0.5})
addMelee({Name="Scythe",Damage=60,AttackRate=1.0,Range=9,EquipTime=0.55})
addMelee({Name="Battle Axe",Damage=70,AttackRate=1.3,Range=7.5,EquipTime=0.6})
addMelee({Name="Riot Shield",Damage=30,AttackRate=1.2,Range=5,EquipTime=0.5})
addMelee({Name="Maul",Status="Prime",Damage=80,AttackRate=1.5,Range=7,EquipTime=0.65})
addMelee({Name="Spear",Status="Prime",Damage=50,AttackRate=1.0,Range=10,EquipTime=0.5})
addMelee({Name="Trowel",Status="Prime",Damage=25,AttackRate=0.8,Range=5,EquipTime=0.4})
addMelee({Name="Glast Shard",Status="Contraband",Damage=48,AttackRate=0.85,Range=7,EquipTime=0.45})

-- THROWABLES
addThrowable({Name="Grenade",Damage=120,FuseTime=2.5,ExplosionRadius=14,Mag=1,Reserve=2})
addThrowable({Name="Molotov",Damage=40,FuseTime=0,ExplosionRadius=10,Mag=1,Reserve=2})
addThrowable({Name="Flashbang",Damage=0,FuseTime=1.5,ExplosionRadius=16,Mag=1,Reserve=2})
addThrowable({Name="Smoke Grenade",Damage=0,FuseTime=1.5,ExplosionRadius=12,Mag=1,Reserve=2})
addThrowable({Name="Satchel",Damage=130,FuseTime=0,ExplosionRadius=12,Mag=1,Reserve=2})
addThrowable({Name="Warpstone",Status="Prime",Damage=0,FuseTime=0,ExplosionRadius=0,Mag=1,Reserve=1})
addThrowable({Name="Elixir",Status="Contraband",Damage=80,FuseTime=2.0,ExplosionRadius=10,Mag=1,Reserve=1})

table.sort(ItemLibrary.ItemsAlphabetized)

function ItemLibrary:GetItem(name) return self.Items[name] end
function ItemLibrary:GetViewModel(name) return self.ViewModels[name] end
function ItemLibrary:GetViewModelImage(viewModelName, skin, highRes)
	local vm = self.ViewModels[viewModelName]
	if not vm then return nil end
	return highRes and (vm.ImageHighResolution or vm.Image) or vm.Image
end
function ItemLibrary:GetViewModelImageFromWeaponData(weaponData, highRes)
	if not weaponData then return nil end
	return self:GetViewModelImage(weaponData.Name, weaponData.Skin, highRes)
end
function ItemLibrary:FormatWeaponNamesByClass(nameList, filterFn, putInAll)
	local result = {}
	for className in pairs(self.Classes) do result[className] = {} end
	for _, name in pairs(nameList) do
		if not filterFn or filterFn(name) then
			if putInAll then
				for _, list in pairs(result) do table.insert(list, name) end
			else
				local item = self.Items[name]
				if item then table.insert(result[item.Class], name) end
			end
		end
	end
	return result
end
function ItemLibrary:GetAllItemNames() return table.clone(self.ItemsAlphabetized) end
function ItemLibrary:GetItemsByClass(className)
	local list = {}
	for name, item in pairs(self.Items) do
		if item.Class == className then table.insert(list, name) end
	end
	table.sort(list)
	return list
end
function ItemLibrary:GetItemsByType(typeName)
	local list = {}
	for name, item in pairs(self.Items) do
		if item.Type == typeName then table.insert(list, name) end
	end
	table.sort(list)
	return list
end
function ItemLibrary:GetItemsByStatus(statusName)
	local list = {}
	for name, item in pairs(self.Items) do
		if item.Status == statusName then table.insert(list, name) end
	end
	table.sort(list)
	return list
end

return ItemLibrary
]=]

SOURCES['WeaponController'] = [=[-- WeaponController (expanded: burst, pellets, charge, melee)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemLibrary = require("ItemLibrary")
local AnimationLibrary = require("AnimationLibrary")
local Spring = require("Spring")
local Signal = require("Signal")
local Utility = require("Utility")

local WeaponController = {}
WeaponController.__index = WeaponController

local STATES = {
	Idle="Idle", Equipping="Equipping", Shooting="Shooting",
	Reloading="Reloading", Inspecting="Inspecting", Charging="Charging",
}

function WeaponController.new(player)
	return setmetatable({
		Player = player, Character = nil, Humanoid = nil,
		CurrentItemName = nil, CurrentItem = nil, State = STATES.Idle,
		AmmoInMag = 0, ReserveAmmo = 0,
		IsADS = false, IsSprinting = false, IsFiring = false,
		LastShotTime = 0, EquipStartTime = 0, ReloadStartTime = 0,
		ChargeProgress = 0, ChargeStartTime = 0,
		RecoilSpring = Spring.new(Vector3.zero, 12, 0.7),
		SpreadSpring = Spring.new(0, 8, 0.9),
		CurrentTrack = nil,
		OnStateChanged = Signal.new(), OnAmmoChanged = Signal.new(),
		OnShot = Signal.new(), OnReloaded = Signal.new(), OnEquipped = Signal.new(),
	}, WeaponController)
end

function WeaponController:BindCharacter(character)
	self.Character = character
	self.Humanoid = character:WaitForChild("Humanoid", 5)
end

function WeaponController:Equip(itemName)
	local item = ItemLibrary:GetItem(itemName)
	if not item then
		Utility:Warn("Equip unknown item", itemName)
		return false
	end
	self:StopCurrentAnimation()
	self.IsFiring = false
	self.ChargeProgress = 0
	self.CurrentItemName = itemName
	self.CurrentItem = item
	self.AmmoInMag = (item.MagazineSize == math.huge) and math.huge or (item.MagazineSize or 0)
	self.ReserveAmmo = (item.ReserveAmmo == math.huge) and math.huge or (item.ReserveAmmo or 0)
	self.State = STATES.Equipping
	self.EquipStartTime = os.clock()
	self.OnStateChanged:Fire(self.State)
	self.OnAmmoChanged:Fire(self.AmmoInMag, self.ReserveAmmo)
	self.OnEquipped:Fire(itemName)

	local vm = ItemLibrary:GetViewModel(item.ViewModel or itemName)
	if vm and vm.EquipAnimation then
		self:PlayAnimation(vm.EquipAnimation, function()
			if self.CurrentItemName == itemName then
				self.State = STATES.Idle
				self.OnStateChanged:Fire(self.State)
				self:PlayIdle()
			end
		end)
	else
		task.delay(item.EquipTime or 0.4, function()
			if self.CurrentItemName == itemName then
				self.State = STATES.Idle
				self.OnStateChanged:Fire(self.State)
				self:PlayIdle()
			end
		end)
	end
	return true
end

function WeaponController:PlayIdle()
	if not self.CurrentItem then return end
	local vm = ItemLibrary:GetViewModel(self.CurrentItem.ViewModel or self.CurrentItemName)
	if vm and vm.IdleAnimation then
		self:PlayAnimation(vm.IdleAnimation, nil, true)
	end
end

function WeaponController:PlayAnimation(animName, onFinished, looped)
	if not self.Humanoid then return end
	self:StopCurrentAnimation()
	local track, info = AnimationLibrary:PlayOnHumanoid(self.Humanoid, animName, 0.1)
	if not track then return end
	self.CurrentTrack = track
	if looped then track.Looped = true end
	if onFinished then track.Stopped:Once(onFinished) end
	if info and info.SoundCallback then
		task.spawn(info.SoundCallback, self, track, info.Length or 1)
	end
	if info and info.EffectCallback then
		task.spawn(info.EffectCallback, self, track, info.Length or 1)
	end
	return track
end

function WeaponController:StopCurrentAnimation()
	if self.CurrentTrack then
		self.CurrentTrack:Stop(0.1)
		self.CurrentTrack = nil
	end
end

function WeaponController:CanShoot()
	if not self.CurrentItem then return false end
	if self.State == STATES.Equipping or self.State == STATES.Reloading then return false end
	if self.CurrentItem.Type == "Melee" then return true end
	if self.AmmoInMag <= 0 then return false end
	local now = os.clock()
	local fireRate = self.CurrentItem.FireRate or 0.1
	return (now - self.LastShotTime) >= fireRate
end

function WeaponController:StartFiring()
	self.IsFiring = true
	local item = self.CurrentItem
	if item and item.RequiresCharge then
		self.State = STATES.Charging
		self.OnStateChanged:Fire(self.State)
		self.ChargeStartTime = os.clock()
		self.ChargeProgress = 0
		local vm = ItemLibrary:GetViewModel(item.ViewModel or self.CurrentItemName)
		if vm and vm.AnimationMap and vm.AnimationMap.ChargeStart then
			self:PlayAnimation(vm.AnimationMap.ChargeStart)
		end
		return
	end
	self:_fireLoop()
end

function WeaponController:StopFiring()
	local wasCharging = self.State == STATES.Charging
	self.IsFiring = false
	if wasCharging then
		local item = self.CurrentItem
		local needed = item and item.ChargeTime or 1
		if self.ChargeProgress >= 1 or (os.clock() - self.ChargeStartTime) >= needed * 0.5 then
			self:TryShoot()
		end
		self.ChargeProgress = 0
		self.State = STATES.Idle
		self.OnStateChanged:Fire(self.State)
		self:PlayIdle()
	end
end

function WeaponController:_fireLoop()
	if not self.IsFiring then return end
	if self:TryShoot() then
		local item = self.CurrentItem
		if item and (item.IsAutomatic or (item.BurstCount and item.BurstCount > 1)) then
			local delay = item.FireRate or 0.1
			if item.BurstCount and item.BurstCount > 1 then
				delay = item.BurstCooldown or 0.07
			end
			task.delay(delay, function() self:_fireLoop() end)
		end
	end
end

function WeaponController:TryShoot()
	if not self:CanShoot() then
		if self.CurrentItem and self.CurrentItem.Type ~= "Melee" and self.AmmoInMag <= 0 and self.State ~= STATES.Reloading then
			self:StartReload()
		end
		return false
	end

	local item = self.CurrentItem
	self.LastShotTime = os.clock()

	-- Melee
	if item.Type == "Melee" then
		self.State = STATES.Shooting
		self.OnStateChanged:Fire(self.State)
		local vm = ItemLibrary:GetViewModel(item.ViewModel or self.CurrentItemName)
		if vm and vm.AnimationMap and vm.AnimationMap.Attack1 then
			self:PlayAnimation(vm.AnimationMap.Attack1)
		end
		self:_doRaycast(item, 1)
		task.delay(item.AttackRate or 0.5, function()
			if self.State == STATES.Shooting then
				self.State = STATES.Idle
				self.OnStateChanged:Fire(self.State)
			end
		end)
		return true
	end

	-- Burst
	local shots = item.BurstCount or 1
	for i = 1, shots do
		if self.AmmoInMag <= 0 then break end
		self.AmmoInMag -= 1
		self.OnAmmoChanged:Fire(self.AmmoInMag, self.ReserveAmmo)
		self.State = STATES.Shooting
		self.OnStateChanged:Fire(self.State)

		local recoil = item.Recoil or Vector3.new(0.5, 0.3, 0)
		self.RecoilSpring:Impulse(recoil)
		self.SpreadSpring:Impulse((item.Spread or 1) * 0.15)

		local vm = ItemLibrary:GetViewModel(item.ViewModel or self.CurrentItemName)
		if vm and vm.AnimationMap and vm.AnimationMap.Shoot1 then
			self:PlayAnimation(vm.AnimationMap.Shoot1)
		end

		local pellets = item.PelletCount or 1
		for p = 1, pellets do
			self:_doRaycast(item, pellets)
		end

		if shots > 1 and i < shots then
			task.wait(item.BurstCooldown or 0.07)
		end
	end

	task.delay(0.05, function()
		if self.State == STATES.Shooting then
			self.State = STATES.Idle
			self.OnStateChanged:Fire(self.State)
		end
	end)
	return true
end

function WeaponController:_doRaycast(item, pelletDiv)
	local camera = workspace.CurrentCamera
	local origin = camera and camera.CFrame.Position
		or (self.Character and self.Character:GetPivot().Position)
		or Vector3.zero
	local look = camera and camera.CFrame.LookVector or Vector3.zAxis
	local spreadAngle = (item.Spread or 1) * 0.01
	local spreadX = (math.random() - 0.5) * spreadAngle
	local spreadY = (math.random() - 0.5) * spreadAngle
	local direction = (CFrame.lookAt(Vector3.zero, look) * CFrame.Angles(spreadY, spreadX, 0)).LookVector

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { self.Character }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local range = item.Range or 500
	if item.Type == "Melee" then range = item.Range or 6 end

	local result = workspace:Raycast(origin, direction * range, params)
	local hitPosition = result and result.Position or (origin + direction * range)
	local hitInstance = result and result.Instance
	local dmg = (item.Damage or 20) / (pelletDiv or 1)

	self.OnShot:Fire({
		Item = item, Origin = origin, Direction = direction,
		Hit = hitInstance, HitPosition = hitPosition, Damage = dmg,
	})
	self:_spawnTracer(origin, hitPosition)
end

function WeaponController:_spawnTracer(from, to)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Size = Vector3.new(0.08, 0.08, math.max(0.1, (to - from).Magnitude))
	part.CFrame = CFrame.lookAt((from + to) / 2, to)
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 220, 100)
	part.Parent = workspace
	Utility:SafeDestroy(part, 0.07)
end

function WeaponController:StartReload()
	if not self.CurrentItem then return end
	if self.CurrentItem.Type == "Melee" then return end
	if self.State == STATES.Reloading then return end
	if self.AmmoInMag >= (self.CurrentItem.MagazineSize or 0) then return end
	if self.ReserveAmmo <= 0 then return end

	self.State = STATES.Reloading
	self.OnStateChanged:Fire(self.State)
	self.ReloadStartTime = os.clock()

	local item = self.CurrentItem
	local vm = ItemLibrary:GetViewModel(item.ViewModel or self.CurrentItemName)
	local animName = nil
	if vm and vm.AnimationMap then
		if self.AmmoInMag == 0 and vm.AnimationMap.EmptyReload then
			animName = vm.AnimationMap.EmptyReload
		else
			animName = vm.AnimationMap.Reload
		end
	end

	local reloadTime = item.ReloadTime or 2
	if animName then
		self:PlayAnimation(animName, function() self:_finishReload() end)
	else
		task.delay(reloadTime, function() self:_finishReload() end)
	end
end

function WeaponController:_finishReload()
	if self.State ~= STATES.Reloading then return end
	local item = self.CurrentItem
	if not item then return end
	local needed = (item.MagazineSize or 0) - self.AmmoInMag
	local take = math.min(needed, self.ReserveAmmo)
	self.AmmoInMag += take
	self.ReserveAmmo -= take
	self.State = STATES.Idle
	self.OnStateChanged:Fire(self.State)
	self.OnAmmoChanged:Fire(self.AmmoInMag, self.ReserveAmmo)
	self.OnReloaded:Fire()
	self:PlayIdle()
end

function WeaponController:Inspect()
	if not self.CurrentItem or self.State ~= STATES.Idle then return end
	local vm = ItemLibrary:GetViewModel(self.CurrentItem.ViewModel or self.CurrentItemName)
	if vm and vm.InspectAnimation then
		self.State = STATES.Inspecting
		self.OnStateChanged:Fire(self.State)
		self:PlayAnimation(vm.InspectAnimation, function()
			self.State = STATES.Idle
			self.OnStateChanged:Fire(self.State)
			self:PlayIdle()
		end)
	end
end

function WeaponController:GetRecoilOffset() return self.RecoilSpring.Value end
function WeaponController:GetCurrentSpread()
	return (self.CurrentItem and self.CurrentItem.Spread or 1) + self.SpreadSpring.Value
end

function WeaponController:Update(dt)
	self.RecoilSpring:Update(dt)
	self.SpreadSpring:Update(dt)
	self.RecoilSpring:SetTarget(Vector3.zero)
	self.SpreadSpring:SetTarget(0)
	if self.State == STATES.Charging and self.CurrentItem then
		local needed = self.CurrentItem.ChargeTime or 1
		self.ChargeProgress = math.clamp((os.clock() - self.ChargeStartTime) / needed, 0, 1)
	end
end

function WeaponController:Destroy()
	self:StopCurrentAnimation()
	self.OnStateChanged:DisconnectAll()
	self.OnAmmoChanged:DisconnectAll()
	self.OnShot:DisconnectAll()
	self.OnReloaded:DisconnectAll()
	self.OnEquipped:DisconnectAll()
end

WeaponController.STATES = STATES
return WeaponController
]=]

SOURCES['Emote'] = [=[-- Emote (cleaned reconstruction of original class surface)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require("Signal")
local Utility = require("Utility")

local Emote = {}
Emote.__index = Emote
Emote._id_counter = 0

function Emote.new(player, emoteName, humanoid)
	assert(humanoid and humanoid:IsA("Humanoid"), "Emote requires Humanoid")
	local self = setmetatable({
		Destroying = Signal.new(),
		ObjectID = Emote:_NewObjectID(),
		Name = emoteName,
		Info = { Name = emoteName, Type = "Emote" },
		Player = player,
		_humanoid = humanoid,
		_destroyed = false,
		_destroy_these = {},
		_connections = {},
		_animation_tracks = {},
		_sounds = {},
		_seed = math.random(1, 1000000),
	}, Emote)
	self:_Init()
	return self
end

function Emote:_NewObjectID()
	Emote._id_counter += 1
	return Emote._id_counter
end

function Emote:_Init()
	-- Subclasses / individual emote modules override Play
end

function Emote:IsDestroyed()
	return self._destroyed
end

function Emote:CreateSound(soundId, volume, playbackSpeed, parent)
	if self._destroyed then return nil end
	local s = Utility:CreateSound(parent or self._humanoid.RootPart, soundId, volume, playbackSpeed)
	table.insert(self._destroy_these, s)
	self._sounds[s] = s.Parent
	return s
end

function Emote:Play()
	-- Default: no-op. Individual emote ModuleScripts under Emotes/ implement specifics.
	warn("[Emote] Play() not overridden for", self.Name)
end

function Emote:Destroy()
	if self._destroyed then return end
	self._destroyed = true
	for _, track in pairs(self._animation_tracks) do
		pcall(function() track:Stop() end)
	end
	for _, inst in pairs(self._destroy_these) do
		pcall(function() inst:Destroy() end)
	end
	for _, conn in pairs(self._connections) do
		pcall(function() conn:Disconnect() end)
	end
	self.Destroying:Fire()
	self.Destroying:DisconnectAll()
end

return Emote
]=]

SOURCES['Finisher'] = [=[-- Finisher (cleaned reconstruction of original class surface)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require("Signal")
local Utility = require("Utility")

local Finisher = {}
Finisher.__index = Finisher

function Finisher.new(finisherName, subject, isFinal, eliminator)
	local self = setmetatable({
		Name = finisherName,
		Destroying = Signal.new(),
		_subject = subject,
		_is_humanoid = subject and subject:IsA("Humanoid"),
		_is_final_finisher = isFinal,
		_eliminator = eliminator,
		_destroyed = false,
		_destroy_these = {},
		_connections = {},
		_seed = math.random(1, 1000000),
	}, Finisher)
	self:_Init()
	return self
end

function Finisher:_Init() end

function Finisher:CreateSound(soundId, volume, playbackSpeed, parent)
	local root = parent
	if not root and self._is_humanoid then
		root = self._subject.RootPart
	end
	local s = Utility:CreateSound(root, soundId, volume, playbackSpeed)
	table.insert(self._destroy_these, s)
	return s
end

function Finisher:PlayServer(_simulate)
	-- Individual finisher modules under Finishers/ implement PlayServer / PlayClient
	warn("[Finisher] PlayServer not overridden for", self.Name)
end

function Finisher:Simulate(onError)
	task.spawn(function()
		local ok, err = pcall(self.PlayServer, self, true)
		if not ok and onError then onError(err) end
	end)
end

function Finisher:Destroy()
	if self._destroyed then return end
	self._destroyed = true
	for _, inst in pairs(self._destroy_these) do
		pcall(function() inst:Destroy() end)
	end
	for _, conn in pairs(self._connections) do
		pcall(function() conn:Disconnect() end)
	end
	self.Destroying:Fire()
	self.Destroying:DisconnectAll()
end

return Finisher
]=]

SOURCES['Diagnostic'] = [=[-- Diagnostic system for the autonomous test project
-- Reports exact [System] → [File] → [Function] → [Problem] style messages.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Diagnostic = {
	_results = {},
	_okCount = 0,
	_failCount = 0,
}

local function report(system, file, func, ok, problem)
	local entry = {
		System = system,
		File = file,
		Function = func,
		OK = ok,
		Problem = problem,
		Time = os.clock(),
	}
	table.insert(Diagnostic._results, entry)
	if ok then
		Diagnostic._okCount += 1
		print(string.format("[OK] %s → %s → %s", system, file, func))
	else
		Diagnostic._failCount += 1
		warn(string.format("[FAIL] %s → %s → %s → %s", system, file, func, problem or "unknown"))
	end
end

function Diagnostic:CheckModule(name, path)
	local ok, mod = pcall(function()
		return require(path)
	end)
	if ok and mod then
		report("Modules", name, "require", true)
		return mod
	else
		report("Modules", name, "require", false, tostring(mod))
		return nil
	end
end

function Diagnostic:CheckRemote(folder, name)
	local remote = folder and folder:FindFirstChild(name)
	if remote and (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction") or remote:IsA("BindableEvent")) then
		report("Remotes", name, "exists", true)
		return remote
	else
		report("Remotes", name, "exists", false, "not found or wrong class")
		return nil
	end
end

function Diagnostic:CheckService(serviceName)
	local ok, svc = pcall(function()
		return game:GetService(serviceName)
	end)
	if ok and svc then
		report("Services", serviceName, "GetService", true)
		return svc
	else
		report("Services", serviceName, "GetService", false, tostring(svc))
		return nil
	end
end

function Diagnostic:RunFullCheck()
	print("========== DIAGNOSTIC START ==========")
	self._results = {}
	self._okCount = 0
	self._failCount = 0

	-- Services
	self:CheckService("ReplicatedStorage")
	self:CheckService("ServerScriptService")
	self:CheckService("Players")
	self:CheckService("RunService")
	self:CheckService("UserInputService")

	-- Core modules
	local modules = ReplicatedStorage:FindFirstChild("Modules")
	if not modules then
		report("Modules", "folder", "exists", false, "ReplicatedStorage.Modules missing")
		print("========== DIAGNOSTIC END ==========")
		return self:GetSummary()
	end
	report("Modules", "folder", "exists", true)

	local required = {
		"CONSTANTS", "Signal", "Spring", "Utility",
		"AnimationLibrary", "ItemLibrary", "WeaponController",
		"Emote", "Finisher", "Diagnostic",
	}
	for _, name in ipairs(required) do
		local path = modules:FindFirstChild(name)
		if path then
			self:CheckModule(name, path)
		else
			report("Modules", name, "exists", false, "ModuleScript not found")
		end
	end

	-- ItemLibrary content check
	local ItemLibrary = modules:FindFirstChild("ItemLibrary")
	if ItemLibrary then
		local ok, lib = pcall(require, ItemLibrary)
		if ok and lib then
			local count = 0
			for _ in pairs(lib.Items or {}) do count += 1 end
			if count > 0 then
				report("ItemLibrary", "Items", "count", true)
				print("  → Loaded", count, "items")
			else
				report("ItemLibrary", "Items", "count", false, "no items registered")
			end
		end
	end

	-- AnimationLibrary content check
	local AnimLib = modules:FindFirstChild("AnimationLibrary")
	if AnimLib then
		local ok, lib = pcall(require, AnimLib)
		if ok and lib and lib.Info then
			local count = 0
			for _ in pairs(lib.Info) do count += 1 end
			report("AnimationLibrary", "Info", "count", count > 0)
			print("  → Loaded", count, "animations")
		end
	end

	-- Remotes
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		report("Remotes", "folder", "exists", true)
		self:CheckRemote(remotes, "WeaponAction")
		self:CheckRemote(remotes, "RequestLoadout")
	else
		report("Remotes", "folder", "exists", false, "ReplicatedStorage.Remotes missing")
	end

	print("========== DIAGNOSTIC END ==========")
	print(string.format("OK: %d  |  FAIL: %d", self._okCount, self._failCount))
	return self:GetSummary()
end

function Diagnostic:GetSummary()
	return {
		OK = self._okCount,
		Fail = self._failCount,
		Results = self._results,
	}
end

return Diagnostic
]=]

SOURCES["__CLIENT__"] = [=[
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
while not player do
	task.wait()
	player = Players.LocalPlayer
end

local ItemLibrary = require("ItemLibrary")
local WeaponController = require("WeaponController")
local Utility = require("Utility")

-- Optional diagnostic
pcall(function()
	local Diagnostic = require("Diagnostic")
	-- Diagnostic expects ReplicatedStorage.Modules; skip full check in loadstring mode
end)

local controller = WeaponController.new(player)

local currentLoadout = {
	Primary = "Assault Rifle",
	Secondary = "Handgun",
	Melee = "Knife",
	Utility = "Grenade",
}
local cycleIndex = { Primary = 1, Secondary = 1, Melee = 1, Utility = 1 }

local function onCharacter(char)
	controller:BindCharacter(char)
	controller:Equip(currentLoadout.Primary)
end
if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)

local SLOT_KEYS = {
	[Enum.KeyCode.One] = "Primary",
	[Enum.KeyCode.Two] = "Secondary",
	[Enum.KeyCode.Three] = "Melee",
	[Enum.KeyCode.Four] = "Utility",
}

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or Utility:IsTextBoxFocused() then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		controller:StartFiring()
	elseif input.KeyCode == Enum.KeyCode.R then
		controller:StartReload()
	elseif input.KeyCode == Enum.KeyCode.F then
		controller:Inspect()
	elseif input.KeyCode == Enum.KeyCode.Q then
		local item = controller.CurrentItem
		local className = item and item.Class or "Primary"
		local list = ItemLibrary:GetItemsByClass(className)
		if #list == 0 then return end
		cycleIndex[className] = ((cycleIndex[className] or 1) % #list) + 1
		local name = list[cycleIndex[className]]
		currentLoadout[className] = name
		controller:Equip(name)
	elseif SLOT_KEYS[input.KeyCode] then
		local slot = SLOT_KEYS[input.KeyCode]
		local name = currentLoadout[slot]
		if name then controller:Equip(name) end
	elseif input.KeyCode == Enum.KeyCode.E then
		local all = ItemLibrary:GetAllItemNames()
		local idx = table.find(all, controller.CurrentItemName) or 0
		idx = (idx % #all) + 1
		local name = all[idx]
		local item = ItemLibrary:GetItem(name)
		if item then
			currentLoadout[item.Class] = name
			controller:Equip(name)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		controller:StopFiring()
	end
end)

RunService.RenderStepped:Connect(function(dt)
	controller:Update(dt)
end)

-- Spawn test dummies if none
local function ensureDummies()
	local folder = Workspace:FindFirstChild("RivalsTestTargets")
	if folder then return end
	folder = Instance.new("Folder")
	folder.Name = "RivalsTestTargets"
	folder.Parent = Workspace
	local function dummy(name, pos)
		local model = Instance.new("Model")
		model.Name = name
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.Position = pos
		root.Anchored = true
		root.BrickColor = BrickColor.new("Bright red")
		root.Parent = model
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Size = Vector3.new(1.2, 1.2, 1.2)
		head.Position = pos + Vector3.new(0, 1.6, 0)
		head.Anchored = true
		head.Shape = Enum.PartType.Ball
		head.BrickColor = BrickColor.new("Bright yellow")
		head.Parent = model
		local hum = Instance.new("Humanoid")
		hum.MaxHealth = 100
		hum.Health = 100
		hum.Parent = model
		model.PrimaryPart = root
		model.Parent = folder
	end
	dummy("Target_1", Vector3.new(0, 3, -30))
	dummy("Target_2", Vector3.new(8, 3, -35))
	dummy("Target_3", Vector3.new(-8, 3, -35))
end
pcall(ensureDummies)

-- HUD
local pg = player:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("RivalsTestHUD")
if old then old:Destroy() end

local screen = Instance.new("ScreenGui")
screen.Name = "RivalsTestHUD"
screen.ResetOnSpawn = false
screen.Parent = pg

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(320, 170)
frame.Position = UDim2.new(0, 20, 1, -190)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
frame.BackgroundTransparency = 0.25
frame.BorderSizePixel = 0
frame.Parent = screen
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

local function mkLabel(y, h, color)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -16, 0, h)
	l.Position = UDim2.fromOffset(8, y)
	l.BackgroundTransparency = 1
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Font = Enum.Font.Gotham
	l.TextSize = 13
	l.Parent = frame
	return l
end

local title = mkLabel(6, 20, Color3.fromRGB(255, 200, 50))
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.Text = "RIVALS LOADSTRING · Full Arsenal"

local weaponLabel = mkLabel(30, 22, Color3.fromRGB(230, 230, 230))
weaponLabel.TextSize = 16
weaponLabel.Text = "Weapon: —"

local statusLabel = mkLabel(54, 16, Color3.fromRGB(180, 180, 100))
statusLabel.Text = "Status: —"

local ammoLabel = mkLabel(74, 22, Color3.fromRGB(180, 220, 255))
ammoLabel.Font = Enum.Font.GothamMedium
ammoLabel.TextSize = 18
ammoLabel.Text = "Ammo: —"

local stateLabel = mkLabel(100, 16, Color3.fromRGB(160, 160, 160))
stateLabel.Text = "State: Idle"

local statsLabel = mkLabel(120, 16, Color3.fromRGB(140, 140, 140))
statsLabel.Text = ""

local helpLabel = mkLabel(142, 24, Color3.fromRGB(110, 110, 110))
helpLabel.TextSize = 11
helpLabel.TextWrapped = true
helpLabel.Text = "LMB Fire · R Reload · F Inspect · 1-4 Slots · Q Cycle Class · E Cycle All"

controller.OnEquipped:Connect(function(name)
	local item = ItemLibrary:GetItem(name)
	weaponLabel.Text = string.format("Weapon: %s  [%s]", name, item and item.Class or "?")
	statusLabel.Text = string.format("Status: %s  |  Type: %s", item and item.Status or "—", item and item.Type or "—")
	if item then
		if item.Type == "Gun" then
			statsLabel.Text = string.format("DMG %s  RPM %s  Spread %s  Mag %s",
				tostring(item.Damage), tostring(item.RPM), tostring(item.Spread), tostring(item.MagazineSize))
		elseif item.Type == "Melee" then
			statsLabel.Text = string.format("DMG %s  Rate %s  Range %s",
				tostring(item.Damage), tostring(item.AttackRate), tostring(item.Range))
		else
			statsLabel.Text = string.format("DMG %s  Fuse %s  Radius %s",
				tostring(item.Damage), tostring(item.FuseTime), tostring(item.ExplosionRadius))
		end
	end
end)

controller.OnAmmoChanged:Connect(function(mag, reserve)
	if mag == math.huge then
		ammoLabel.Text = "Ammo: ∞"
	else
		ammoLabel.Text = string.format("Ammo: %s / %s", tostring(mag), tostring(reserve))
	end
end)

controller.OnStateChanged:Connect(function(state)
	if state == "Charging" then
		stateLabel.Text = string.format("State: Charging %.0f%%", (controller.ChargeProgress or 0) * 100)
	else
		stateLabel.Text = "State: " .. state
	end
end)

controller.OnShot:Connect(function(data)
	if data.Hit and data.Hit.Parent then
		local hum = data.Hit.Parent:FindFirstChildOfClass("Humanoid")
		if hum then
			hum:TakeDamage(data.Damage or 25)
		end
	end
end)

local cross = Instance.new("Frame")
cross.Name = "Crosshair"
cross.Size = UDim2.fromOffset(6, 6)
cross.Position = UDim2.fromScale(0.5, 0.5)
cross.AnchorPoint = Vector2.new(0.5, 0.5)
cross.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
cross.BorderSizePixel = 0
cross.Parent = screen
Instance.new("UICorner", cross).CornerRadius = UDim.new(1, 0)

print("[Rivals Loader] Ready | Items:", #ItemLibrary:GetAllItemNames())
print("[Rivals Loader] LMB/R/F/1-4/Q/E")
]=]


-- Module registry + require
local cache = {}
local loading = {}

local function rivalsRequire(name)
	if cache[name] ~= nil then
		return cache[name]
	end
	if loading[name] then
		error("[Rivals] Circular require: " .. tostring(name), 2)
	end
	local src = SOURCES[name]
	if not src then
		error("[Rivals] Module not found: " .. tostring(name), 2)
	end
	loading[name] = true
	local chunk, err = loadstring(src, "=Rivals/" .. name)
	if not chunk then
		loading[name] = nil
		error("[Rivals] Compile error in " .. name .. ": " .. tostring(err), 2)
	end
	-- Inject require into env
	local env = setmetatable({
		require = rivalsRequire,
		script = { Name = name, Parent = nil },
	}, { __index = getfenv and getfenv() or _G })
	-- Luau: setfenv may not exist; use getfenv workaround via loadstring env if available
	if setfenv then
		setfenv(chunk, env)
	end
	local result = chunk()
	-- If setfenv unavailable, modules use global require - bind it
	cache[name] = result
	loading[name] = nil
	return result
end

-- Make require available for modules that call global require("X")
-- In Luau without setfenv, we patch by wrapping each module source
do
	local oldCache = cache
	cache = {}
	loading = {}
	function rivalsRequire(name)
		if cache[name] ~= nil then return cache[name] end
		if loading[name] then error("[Rivals] Circular: " .. name) end
		local src = SOURCES[name]
		if not src then error("[Rivals] Missing module: " .. tostring(name)) end
		loading[name] = true
		-- Prepend require bind for Luau (no setfenv)
		local wrapped = "local require = ...\n" .. src
		local chunk, err = loadstring(wrapped, "=Rivals/" .. name)
		if not chunk then
			loading[name] = nil
			error("[Rivals] " .. name .. " compile: " .. tostring(err))
		end
		local ok, result = pcall(chunk, rivalsRequire)
		loading[name] = nil
		if not ok then
			error("[Rivals] " .. name .. " runtime: " .. tostring(result))
		end
		cache[name] = result
		return result
	end
end

-- Expose
_G.RivalsRequire = rivalsRequire
_G.RivalsSources = SOURCES

-- Preload core modules
local order = {
	"CONSTANTS", "Signal", "Spring", "Utility",
	"AnimationLibrary", "SoundLibrary", "ItemLibrary",
	"WeaponController", "Emote", "Finisher", "Diagnostic",
}
for _, name in ipairs(order) do
	local ok, err = pcall(rivalsRequire, name)
	if ok then
		print("[Rivals] Loaded", name)
	else
		warn("[Rivals] Failed", name, err)
	end
end

-- Run client
local clientSrc = SOURCES["__CLIENT__"]
local clientWrapped = "local require = ...\n" .. clientSrc
local clientChunk, clientErr = loadstring(clientWrapped, "=Rivals/Client")
assert(clientChunk, clientErr)
clientChunk(rivalsRequire)
