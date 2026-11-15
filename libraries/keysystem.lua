--[[
	DogVape - key system
	--------------------
	Two modes:

	1. API mode  - set API_BASE to your deployed Cloudflare Worker (see /keys).
		           Keys come from Linkvertise redemptions and expire after 24h.
	2. Static mode - leave API_BASE empty and keys are read from keys.json.

	Accepted keys are cached in DogVape/profiles/key.txt so the prompt only
	appears once per install.

	This runs client-side, so anyone able to read this file can bypass it.
	Treat it as a speed bump for casual reuse, not real security.
]]

local Keysystem = {}

-- == config ================================================================
-- e.g. "https://dogvape-keys.your-name.workers.dev"
local API_BASE     = ""
-- Must match: wrangler secret put REDEEM_TOKEN
local REDEEM_TOKEN = ""
-- e.g. "https://linkvertise.com/123456/dogvape"
local LINKVERTISE  = "https://direct-link.net/5342438/m0PWvU2VWU3g"

local KEY_URL  = "https://raw.githubusercontent.com/0lyzll/DogVape/main/keys.json"
local KEY_FILE = "DogVape/profiles/key.txt"
local HWID_FILE = "DogVape/profiles/hwid.txt"
-- =========================================================================

-- == DogVape UI palette (matches guis/new.lua) =============================
local uipallet = {
	Main = Color3.fromRGB(9, 8, 7),
	Text = Color3.fromRGB(200, 200, 200),
	Font = Font.fromEnum(Enum.Font.Arial),
	FontSemiBold = Font.fromEnum(Enum.Font.Arial, Enum.FontWeight.SemiBold),
	Tween = TweenInfo.new(0.16, Enum.EasingStyle.Linear)
}

local function colorDark(col, num)
	local h, s, v = col:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(select(3, uipallet.Main:ToHSV()) > 0.5 and v + num or v - num, 0, 1))
end

local function colorLight(col, num)
	local h, s, v = col:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(select(3, uipallet.Main:ToHSV()) > 0.5 and v - num or v + num, 0, 1))
end

local statusColors = {
	error = Color3.fromRGB(255, 93, 108),
	ok = Color3.fromRGB(57, 217, 138),
	dim = Color3.fromRGB(150, 157, 170),
	accent = Color3.fromHSV((uipallet.Main:ToHSV()))
}

-- Asset mapping (matches new.lua)
local getcustomassets = {
	['DogVape/assets/new/close.png'] = 'rbxassetid://14368309446',
	['DogVape/assets/new/blur.png'] = 'rbxassetid://14898786664',
}

local function getcustomasset(path)
	if isfile and isfile(path) then
		return getcustomasset(path)
	end
	return getcustomassets[path] or ''
end

-- == services ==============================================================
local Players          = game:GetService("Players")
local HttpService      = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local GuiService       = game:GetService("GuiService")

-- == utilities =============================================================
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

-- == hardware id ===========================================================
local cachedHwid
local function getHwid()
	if cachedHwid then return cachedHwid end

	local getters = {
		rawget(_G, "gethwid"),
		rawget(_G, "get_hwid"),
		type(syn) == "table" and syn.get_hwid or nil,
		type(exploit) == "table" and exploit.get_hwid or nil,
	}
	for _, fn in ipairs(getters) do
		if type(fn) == "function" then
			local ok, res = pcall(fn)
			if ok and type(res) == "string" and #res >= 6 then
				cachedHwid = res
				return res
			end
		end
	end

	local okId, id = pcall(function()
		return game:GetService("RbxAnalyticsService"):GetClientId()
	end)
	if okId and type(id) == "string" and #id >= 6 then
		cachedHwid = id
		return id
	end

	local okFile, stored = pcall(readfile, HWID_FILE)
	if okFile and type(stored) == "string" and #stored >= 6 then
		cachedHwid = (stored:gsub("%s+", ""))
		return cachedHwid
	end

	local generated = tostring(math.random(100000000, 999999999)) .. tostring(os.time())
	pcall(function()
		if not isfolder("DogVape/profiles") then makefolder("DogVape/profiles") end
		writefile(HWID_FILE, generated)
	end)
	cachedHwid = generated
	return generated
end

function Keysystem.hwid()
	return getHwid()
end

-- == validation ============================================================
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

local function apiCheck(nk)
	local ok, body = pcall(function()
		return game:HttpGet(
			API_BASE .. "/check?key=" .. HttpService:UrlEncode(nk) ..
			"&hwid=" .. HttpService:UrlEncode(getHwid()),
			true
		)
	end)
	if not ok or type(body) ~= "string" or body == "" then
		return nil, "Could not reach the key server."
	end

	local decoded, data = pcall(HttpService.JSONDecode, HttpService, body)
	if not decoded or type(data) ~= "table" then
		return nil, "Key server sent an unreadable response."
	end
	if not data.valid then
		return nil, type(data.reason) == "string" and data.reason or "Invalid key."
	end
	return {
		role = type(data.role) == "string" and data.role or "user",
		expiresAt = tonumber(data.expiresAt),
	}
end

function Keysystem.validate(key)
	local nk = normalize(key)
	if not nk then return nil, "Enter a key." end

	if API_BASE ~= "" then
		local entry, err = apiCheck(nk)
		if not entry then return nil, err end
		return nk, entry
	end

	local map, err = fetchList()
	if not map then return nil, err end

	local found = map[nk]
	if not found then return nil, "Invalid key." end
	return nk, found
end

local function apply(key, entry)
	getgenv()._DogVaperole = (entry and entry.role) or "user"
	getgenv()._DogVapename = entry and entry.name or nil
	getgenv()._DogVapeexpiry = entry and entry.expiresAt or nil
	save(key)
end

-- == ui helpers (match new.lua) ============================================
local function addBlur(parent)
	local blur = Instance.new("ImageLabel")
	blur.Name = "Blur"
	blur.Size = UDim2.new(1, 89, 1, 52)
	blur.Position = UDim2.fromOffset(-48, -31)
	blur.BackgroundTransparency = 1
	blur.Image = getcustomasset("DogVape/assets/new/blur.png")
	blur.ScaleType = Enum.ScaleType.Slice
	blur.SliceCenter = Rect.new(52, 31, 261, 502)
	blur.ZIndex = 0
	blur.Parent = parent
	return blur
end

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0, 5)
	corner.Parent = parent
	return corner
end

local function addCloseButton(parent, offset)
	local close = Instance.new("ImageButton")
	close.Name = "Close"
	close.Size = UDim2.fromOffset(24, 24)
	close.Position = UDim2.new(1, -35, 0, offset or 9)
	close.BackgroundColor3 = Color3.new(1, 1, 1)
	close.BackgroundTransparency = 1
	close.AutoButtonColor = false
	close.Image = getcustomasset("DogVape/assets/new/close.png")
	close.ImageColor3 = colorLight(uipallet.Text, 0.2)
	close.ImageTransparency = 0.5
	close.Parent = parent
	addCorner(close, UDim.new(1, 0))

	close.MouseEnter:Connect(function()
		close.ImageTransparency = 0.3
		TweenService:Create(close, uipallet.Tween, {
			BackgroundTransparency = 0.6
		}):Play()
	end)
	close.MouseLeave:Connect(function()
		close.ImageTransparency = 0.5
		TweenService:Create(close, uipallet.Tween, {
			BackgroundTransparency = 1
		}):Play()
	end)

	return close
end

local function tween(obj, goal)
	if obj.Parent and obj.Visible then
		local tw = TweenService:Create(obj, uipallet.Tween, goal)
		tw:Play()
		return tw
	else
		for i, v in goal do obj[i] = v end
	end
end

-- == ui ====================================================================
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

local hasLink = LINKVERTISE ~= ""
local cardHeight = hasLink and 300 or 248

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

	-- Full-screen shade
	local shade = Instance.new("Frame")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.45
	shade.BorderSizePixel = 0
	shade.Parent = screen

	-- Card with blur background
	local card = Instance.new("Frame")
	card.Size = UDim2.fromOffset(400, cardHeight)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.BackgroundColor3 = uipallet.Main
	card.BorderSizePixel = 0
	card.Parent = screen
	addCorner(card, 5)
	addBlur(card)

	-- Header bar
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 52)
	header.BackgroundTransparency = 1
	header.Parent = card

	-- DogVape logo dot
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(9, 9)
	dot.Position = UDim2.fromOffset(20, 22)
	dot.BackgroundColor3 = Color3.fromHSV((uipallet.Main:ToHSV()))
	dot.BorderSizePixel = 0
	dot.Parent = header
	addCorner(dot, 5)

	local title = Instance.new("TextLabel")
	title.Text = "DogVape"
	title.FontFace = uipallet.FontSemiBold
	title.TextSize = 17
	title.TextColor3 = uipallet.Text
	title.BackgroundTransparency = 1
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Size = UDim2.fromOffset(200, 20)
	title.Position = UDim2.fromOffset(40, 16)
	title.Parent = header

	-- Close button (image-based like new.lua)
	local close = addCloseButton(header, 9)
	close.Parent = header

	-- Hint text
	local hint = Instance.new("TextLabel")
	hint.Text = "Enter your key to continue"
	hint.FontFace = uipallet.Font
	hint.TextSize = 13
	hint.TextColor3 = colorDark(uipallet.Text, 0.16)
	hint.BackgroundTransparency = 1
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Size = UDim2.new(1, -40, 0, 16)
	hint.Position = UDim2.fromOffset(20, 62)
	hint.Parent = card

	-- Input box background
	local box = Instance.new("Frame")
	box.Size = UDim2.new(1, -40, 0, 40)
	box.Position = UDim2.fromOffset(20, 86)
	box.BackgroundColor3 = colorLight(uipallet.Main, 0.05)
	box.BorderSizePixel = 0
	box.Parent = card
	addCorner(box, 5)

	local input = Instance.new("TextBox")
	input.Size = UDim2.new(1, -24, 1, 0)
	input.Position = UDim2.fromOffset(12, 0)
	input.BackgroundTransparency = 1
	input.Text = ""
	input.PlaceholderText = "DOGVAPE-XXXX-XXXX"
	input.PlaceholderColor3 = Color3.fromRGB(90, 97, 110)
	input.FontFace = uipallet.Font
	input.TextSize = 14
	input.TextColor3 = uipallet.Text
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.ClearTextOnFocus = false
	input.Parent = box

	-- Continue button (styled like new.lua buttons)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, -40, 0, 40)
	button.Position = UDim2.fromOffset(20, 136)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.Parent = card

	local buttonBkg = Instance.new("Frame")
	buttonBkg.Size = UDim2.fromOffset(200, 36)
	buttonBkg.Position = UDim2.fromOffset(100, 2)
	buttonBkg.BackgroundColor3 = colorLight(uipallet.Main, 0.05)
	buttonBkg.Parent = button
	addCorner(buttonBkg, 4)

	local buttonLabel = Instance.new("TextLabel")
	buttonLabel.Size = UDim2.new(1, -4, 1, -4)
	buttonLabel.Position = UDim2.fromOffset(2, 2)
	buttonLabel.BackgroundColor3 = uipallet.Main
	buttonLabel.Text = "Continue"
	buttonLabel.TextColor3 = colorDark(uipallet.Text, 0.16)
	buttonLabel.TextSize = 14
	buttonLabel.FontFace = uipallet.Font
	buttonLabel.Parent = buttonBkg
	addCorner(buttonLabel, UDim.new(0, 4))

	-- Status label
	local status = Instance.new("TextLabel")
	status.Text = ""
	status.FontFace = uipallet.Font
	status.TextSize = 12
	status.TextColor3 = statusColors.error
	status.BackgroundTransparency = 1
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Size = UDim2.new(1, -40, 0, 16)
	status.Position = UDim2.fromOffset(20, 190)
	status.Parent = card

	-- Get Key button (if Linkvertise configured)
	local getKey, hwidLabel
	if hasLink then
		getKey = Instance.new("TextButton")
		getKey.Size = UDim2.new(1, -40, 0, 34)
		getKey.Position = UDim2.fromOffset(20, 212)
		getKey.BackgroundTransparency = 1
		getKey.Text = ""
		getKey.AutoButtonColor = false
		getKey.Parent = card

		local getKeyBkg = Instance.new("Frame")
		getKeyBkg.Size = UDim2.fromOffset(200, 30)
		getKeyBkg.Position = UDim2.fromOffset(100, 2)
		getKeyBkg.BackgroundTransparency = 1
		getKeyBkg.Parent = getKey
		addCorner(getKeyBkg, 4)
		local getKeyStroke = Instance.new("UIStroke")
		getKeyStroke.Color = Color3.fromHSV((uipallet.Main:ToHSV()))
		getKeyStroke.Thickness = 1
		getKeyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		getKeyStroke.Parent = getKeyBkg

		local getKeyLabel = Instance.new("TextLabel")
		getKeyLabel.Size = UDim2.new(1, -4, 1, -4)
		getKeyLabel.Position = UDim2.fromOffset(2, 2)
		getKeyLabel.BackgroundColor3 = uipallet.Main
		getKeyLabel.Text = "Get a key"
		getKeyLabel.FontFace = uipallet.FontSemiBold
		getKeyLabel.TextSize = 13
		getKeyLabel.TextColor3 = Color3.fromHSV((uipallet.Main:ToHSV()))
		getKeyLabel.Parent = getKeyBkg
		addCorner(getKeyLabel, UDim.new(0, 4))

		hwidLabel = Instance.new("TextLabel")
		hwidLabel.Text = "HWID  " .. getHwid():sub(1, 30)
		hwidLabel.FontFace = Font.fromEnum(Enum.Font.Code)
		hwidLabel.TextSize = 10
		hwidLabel.TextColor3 = Color3.fromRGB(90, 97, 110)
		hwidLabel.BackgroundTransparency = 1
		hwidLabel.TextXAlignment = Enum.TextXAlignment.Left
		hwidLabel.Size = UDim2.new(1, -40, 0, 14)
		hwidLabel.Position = UDim2.fromOffset(20, 256)
		hwidLabel.Parent = card
	end

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

	local function setStatus(msg, clr)
		status.Text = msg or ""
		status.TextColor3 = clr or statusColors.error
	end

	local busy = false
	local function submit()
		if busy then return end
		if not normalize(input.Text) then
			setStatus("Enter a key.", statusColors.error)
			return
		end

		busy = true
		buttonLabel.Text = "Checking..."
		setStatus("Validating...", statusColors.dim)

		local key, entry = Keysystem.validate(input.Text)
		if key then
			setStatus("Key accepted.", statusColors.ok)
			buttonLabel.Text = "Continue"
			apply(key, entry)
			task.wait(0.4)
			finish({ key = key, entry = entry })
		else
			busy = false
			buttonLabel.Text = "Continue"
			setStatus(entry or "Invalid key.", statusColors.error)
		end
	end

	local function copyLink()
		local link = LINKVERTISE
		if API_BASE ~= "" and REDEEM_TOKEN ~= "" then
			local target = API_BASE .. "/redeem?t=" .. HttpService:UrlEncode(REDEEM_TOKEN) ..
				"&hwid=" .. HttpService:UrlEncode(getHwid())
			link = LINKVERTISE .. (LINKVERTISE:find("?", 1, true) and "&" or "?") ..
				"r=" .. HttpService:UrlEncode(target)
		end
		local copied = pcall(setclipboard, link)
		if copied then
			setStatus("Link copied - open it in your browser, then paste your key.", statusColors.dim)
		else
			setStatus("Open: " .. link, statusColors.dim)
		end
	end

	-- Button hover effects (match new.lua)
	track(button.MouseEnter:Connect(function()
		tween(buttonBkg, { BackgroundColor3 = colorLight(uipallet.Main, 0.0875) })
	end))
	track(button.MouseLeave:Connect(function()
		tween(buttonBkg, { BackgroundColor3 = colorLight(uipallet.Main, 0.05) })
	end))
	track(button.MouseButton1Click:Connect(submit))

	track(input.FocusLost:Connect(function(enterPressed)
		if enterPressed then submit() end
	end))

	track(close.MouseButton1Click:Connect(function()
		finish(false)
	end))

	if getKey then
		track(getKey.MouseEnter:Connect(function()
			tween(getKeyBkg, { BackgroundTransparency = 0.2 })
			tween(getKeyStroke, { Color = Color3.fromHSV((uipallet.Main:ToHSV())) })
		end))
		track(getKey.MouseLeave:Connect(function()
			tween(getKeyBkg, { BackgroundTransparency = 1 })
		end))
		track(getKey.MouseButton1Click:Connect(copyLink))
		track(hwidLabel.MouseButton1Click:Connect(function()
			if pcall(setclipboard, getHwid()) then
				setStatus("HWID copied.", statusColors.dim)
			end
		end))
		hwidLabel.Active = true
	end

	-- Drag (match new.lua)
	local dragging, dragStart, startPos
	track(header.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1
			or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = i.Position
			startPos = card.AbsolutePosition
			card.AnchorPoint = Vector2.new(0, 0)
			card.Position = UDim2.fromOffset(startPos.X, startPos.Y)
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

-- == entry point ===========================================================
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