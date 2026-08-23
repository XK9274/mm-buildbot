-- Adapted from messersm/love2d-demos, the-tutorial/.

local scene = {}

local function newCondition(c)
	c = c or {}
	function c.update(self, dt) end
	return c
end

local function KeyDown(key)
	local c = newCondition({ key = key })
	function c.update(self, dt)
		self.is_true = love.keyboard.isDown(self.key)
	end
	return c
end

local function TimePassed(time)
	local c = newCondition({ time = time })
	function c.update(self, dt)
		self.time = self.time - dt
		if self.time <= 0 then
			self.is_true = true
		end
	end
	return c
end

local function deepcopy(x)
	if type(x) == "table" then
		local t = {}
		for key, value in pairs(x) do
			t[key] = deepcopy(value)
		end
		return t
	end
	return x
end

local states = {
	start = {
		text = "Welcome to this tutorial. Press Start/Return.",
		transitions = {
			{ condition = KeyDown("return"), next = "well_done" },
			{ condition = TimePassed(5), next = "too_slow" },
		},
	},
	well_done = {
		text = "Very good.",
		transitions = { { condition = TimePassed(2), next = "the_end" } },
	},
	too_slow = {
		text = "You are too slow.",
		transitions = { { condition = TimePassed(2), next = "the_end" } },
	},
	the_end = {
		text = "The end. Press X to restart.",
		transitions = { { condition = KeyDown("lshift"), next = "start" } }, -- BTN_X
	},
}

local current, font

function scene.load()
	font = love.graphics.newFont(16)
	current = deepcopy(states.start)
end

function scene.update(dt)
	for _, t in pairs(current.transitions) do
		t.condition:update(dt)
		if t.condition.is_true then
			current = deepcopy(states[t.next])
			break
		end
	end
end

function scene.draw()
	local width, height = love.graphics.getDimensions()
	love.graphics.setFont(font)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.printf(current.text, 0, height / 2 - 20, width, "center")
end

return scene
