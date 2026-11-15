--[[
	DogVape - key system
	--------------------
	Validates a key against keys.json in the DogVape repo, caches the accepted
	key in DogVape/profiles/key.txt, and prompts the user when there is none.

	This runs entirely client-side, so anyone able to read this file can bypass
	it. Treat it as a speed bump for casual reuse, not real security.
]]

local Keysystem = {}

local KEY_URL  = "https://raw.githubusercontent.com/0lyzll/DogVape/main/keys.json"
local KEY_FILE = "DogVape/profiles/key.txt"

local T = {
	bg          = Color3.fromRGB(17, 19, 24),
	panel       = Color3.fromRGB(32, 38, 48),
	border      = Color3.fromRGB(45, 52, 64),
	accent      = Color3.fromRGB(139, 124, 255),
	accentHover = Color3.fromRGB(160, 148, 255),
	text        = Color3.fromRGB(245, 245, 247),
	dim         = Color3.fromRGB(150, 157, 170),
	error       = Color3.fromRGB(255, 93, 108),
	ok          = Color3.fromRGB(57, 217, 138),
}

local Players          = game:GetService("Players")
local HttpService      = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")

-- Keys are compared case-insensitively, ignoring spaces, dashes and underscores.
local function normalize(raw)
	if type(raw) ~= "string" then return nil end
	local k = raw:gsub("[%s%-_]+", ""):upper()
	if k == "" or k == "KEY" or k == "KEYHERE" then return nil end
	return k
end

local function ensureFolder(path)
	local ok = pcall(isfolder, path)
	if ok and isfolder(path) then return end
	pcall(makefolder, path)
end

local function save(key)
	pcall(ensureFolder, "DogVape")
	pcall(ensureFolder, "DogVape/profiles")
	pcall(writefile, KEY_FILE, key)
end

function Keysystem.saved()
	local ok, res = pcall(readfile, KEY_FILE)
	if not ok or type(res) ~= "string" then return nil end
	return normalize(res)
end

local function fetchList()
	local ok, body = pcall(function()
		return game:HttpGet(KEY_URL .. "?t=" .. tostring(os.time()), true)
	end)
	if not ok or type(body) ~= "string" or body == "" then
		return nil, "Could not reach the key server."
	end
	if body:find("404", 1, true) and #body < 64 then
		return nil, "keys.json is missing from the repo."
	end

	local decoded, data = pcall(HttpService.JSONDecode, HttpService, body)
	if not decoded or type(data) ~= "table" then
		return nil, "keys.json is not valid JSON."
	end

	local raw = data.keys or data
	local map = {}
	for k, v in pairs(raw) do
		if type(k) == "number" and type(v) == "string" then
			local nk = normalize(v)
			if nk then map[nk] = { role = "user" } end
		elseif type(k) == "string" then
			local nk = normalize(k)
			if nk then
				local role, name = "user", nil
				if type(v) == "string" then
					role = v
				elseif type(v) == "table" then
					if type(v.role) == "string" then role = v.role end
					if type(v.name) == "string" then name = v.name end
				end
				map[nk] = { role = role, name = name }
			end
		end
	end
	return map
end

-- Returns normalizedKey, entry on success, or nil, reason on failure.
function Keysystem.validate(key)
	local nk = normalize(key)
	if not nk then return nil, "Enter a key." end

	local map, err = fetchList()
	if not map then return nil, err end

	local entry = map[nk]
	if not entry then return nil, "Invalid key." end
	return nk, entry
end

local function apply(key, entry)
	getgenv()._DogVaperole = (entry and entry.role) or "user"
	getgenv()._DogVapename = entry and entry.name or nil
	save(key)
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------

local function getParent()
	if gethui then
		local ok, h = pcall(gethui)
		if ok and h then return h end
	end
	local ok, cg = pcall(function() return game:GetService("CoreGui") end)
	if ok and cg then return cg end
	local ok2, pg = pcall(function()
		return Players.LocalPlayer:WaitForChild("PlayerGui", 10)
	end)
	if ok2 then return pg end
	return nil
end

local function corner(obj, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = obj
	return c
end

local function stroke(obj, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or T.border
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = obj
	return s
end

local function showPrompt(onDone)
	local parent = getParent()
	if not parent then
		onDone(nil, "No GUI parent available.")
		return
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "DogVapeKeySystem"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 1000
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = parent

	local shade = Instance.new("Frame")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.45
	shade.BorderSizePixel = 0
	shade.Parent = screen

	local card = Instance.new("Frame")
	card.Size = UDim2.fromOffset(400, 248)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.BackgroundColor3 = T.bg
	card.BorderSizePixel = 0
	card.Parent = screen
	corner(card, 14)
	stroke(card, T.border, 1)

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 52)
	header.BackgroundTransparency = 1
	header.Parent = card

	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(9, 9)
	dot.Position = UDim2.fromOffset(20, 22)
	dot.BackgroundColor3 = T.accent
	dot.BorderSizePixel = 0
	dot.Parent = header
	corner(dot, 5)

	local title = Instance.new("TextLabel")
	title.Text = "DogVape"
	title.Font = Enum.Font.GothamBold
	title.TextSize = 17
	title.TextColor3 = T.text
	title.BackgroundTransparency = 1
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Size = UDim2.fromOffset(200, 20)
	title.Position = UDim2.fromOffset(40, 16)
	title.Parent = header

	local close = Instance.new("TextButton")
	close.Text = "x"
	close.Font = Enum.Font.GothamMedium
	close.TextSize = 16
	close.TextColor3 = T.dim
	close.BackgroundTransparency = 1
	close.Size = UDim2.fromOffset(28, 28)
	close.Position = UDim2.new(1, -42, 0, 12)
	close.AutoButtonColor = false
	close.Parent = header

	local hint = Instance.new("TextLabel")
	hint.Text = "Enter your key to continue"
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 13
	hint.TextColor3 = T.dim
	hint.BackgroundTransparency = 1
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Size = UDim2.new(1, -40, 0, 16)
	hint.Position = UDim2.fromOffset(20, 62)
	hint.Parent = card

	local box = Instance.new("Frame")
	box.Size = UDim2.new(1, -40, 0, 40)
	box.Position = UDim2.fromOffset(20, 86)
	box.BackgroundColor3 = T.panel
	box.BorderSizePixel = 0
	box.Parent = card
	corner(box, 9)
	stroke(box, T.border, 1)

	local input = Instance.new("TextBox")
	input.Size = UDim2.new(1, -24, 1, 0)
	input.Position = UDim2.fromOffset(12, 0)
	input.BackgroundTransparency = 1
	input.Text = ""
	input.PlaceholderText = "DOGVAPE-XXXX-XXXX"
	input.PlaceholderColor3 = Color3.fromRGB(90, 97, 110)
	input.Font = Enum.Font.Gotham
	input.TextSize = 14
	input.TextColor3 = T.text
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.ClearTextOnFocus = false
	input.Parent = box

	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, -40, 0, 40)
	button.Position = UDim2.fromOffset(20, 136)
	button.BackgroundColor3 = T.accent
	button.Text = "Continue"
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.TextColor3 = Color3.new(1, 1, 1)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Parent = card
	corner(button, 9)

	local status = Instance.new("TextLabel")
	status.Text = ""
	status.Font = Enum.Font.Gotham
	status.TextSize = 12
	status.TextColor3 = T.error
	status.BackgroundTransparency = 1
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Size = UDim2.new(1, -40, 0, 16)
	status.Position = UDim2.fromOffset(20, 190)
	status.Parent = card

	local connections = {}
	local function track(conn)
		table.insert(connections, conn)
		return conn
	end

	local finished = false
	local function finish(value)
		if finished then return end
		finished = true
		for _, c in ipairs(connections) do
			pcall(function() c:Disconnect() end)
		end
		pcall(function() screen:Destroy() end)
		onDone(value)
	end

	local function setStatus(msg, color)
		status.Text = msg or ""
		status.TextColor3 = color or T.error
	end

	local busy = false
	local function submit()
		if busy then return end
		if not normalize(input.Text) then
			setStatus("Enter a key.", T.error)
			return
		end

		busy = true
		button.Text = "Checking..."
		setStatus("Validating...", T.dim)

		local key, entry = Keysystem.validate(input.Text)
		if key then
			setStatus("Key accepted.", T.ok)
			button.Text = "Continue"
			apply(key, entry)
			task.wait(0.4)
			finish({ key = key, entry = entry })
		else
			busy = false
			button.Text = "Continue"
			setStatus(entry or "Invalid key.", T.error)
		end
	end

	track(button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = T.accentHover }):Play()
	end))
	track(button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = T.accent }):Play()
	end))
	track(button.MouseButton1Click:Connect(submit))
	track(input.FocusLost:Connect(function(enterPressed)
		if enterPressed then submit() end
	end))
	track(close.MouseButton1Click:Connect(function()
		finish(false)
	end))

	-- drag
	local dragging, dragStart, startPos
	track(header.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1
			or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = i.Position
			if card.AnchorPoint.X ~= 0 then
				startPos = card.AbsolutePosition
				card.AnchorPoint = Vector2.new(0, 0)
				card.Position = UDim2.fromOffset(startPos.X, startPos.Y)
			else
				startPos = Vector2.new(card.AbsolutePosition.X, card.AbsolutePosition.Y)
			end
		end
	end))
	track(header.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1
			or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))
	track(UserInputService.InputChanged:Connect(function(i)
		if not dragging then return end
		if i.UserInputType ~= Enum.UserInputType.MouseMovement
			and i.UserInputType ~= Enum.UserInputType.Touch then return end
		local delta = i.Position - dragStart
		card.Position = UDim2.fromOffset(startPos.X + delta.X, startPos.Y + delta.Y)
	end))

	pcall(function() input:CaptureFocus() end)
	setStatus("", T.error)
end

local function promptSync()
	local result, done = nil, false
	showPrompt(function(value)
		result = value
		done = true
	end)
	while not done do
		task.wait()
	end
	return result
end

---------------------------------------------------------------------------
-- Entry point
---------------------------------------------------------------------------

-- Returns the accepted key, or nil if the user cancelled / had no valid key.
function Keysystem.run(passedKey)
	local candidates = {}

	local passNorm = normalize(passedKey)
	if passNorm then table.insert(candidates, passNorm) end

	local savedKey = Keysystem.saved()
	if savedKey and savedKey ~= passNorm then table.insert(candidates, savedKey) end

	for _, candidate in ipairs(candidates) do
		local okKey, entry = Keysystem.validate(candidate)
		if okKey then
			apply(okKey, entry)
			return okKey
		end
	end

	local out = promptSync()
	if type(out) == "table" and out.key then
		return out.key
	end
	return nil
end

return Keysystem
