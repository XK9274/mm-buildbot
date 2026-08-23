-- Adapted from messersm/love2d-demos, thunderstorm/ (procedural rain + a
-- full-screen lightning flash; the layered artwork and audio are dropped --
-- see README.md).

local scene = {}

local function randfloat(min, max)
	return min + love.math.random() * (max - min)
end

local rain, next_bolt_in, bolt_alpha

local function newRain()
	local width, height = love.graphics.getDimensions()
	local drops = {}
	for _ = 1, 300 do
		table.insert(drops, {
			x = love.math.random(0, width),
			y = love.math.random(0, height),
			length = love.math.random(10, 30),
			speed = love.math.random(height, height * 2),
		})
	end
	return { drops = drops, height = height }
end

function scene.load()
	rain = newRain()
	next_bolt_in = randfloat(2, 5)
	bolt_alpha = 0
end

function scene.update(dt)
	for _, drop in pairs(rain.drops) do
		drop.y = drop.y + drop.speed * dt
		if drop.y > rain.height then
			drop.y = 0
		end
	end

	if bolt_alpha > 0 then
		bolt_alpha = math.max(0, bolt_alpha - dt * 2.5)
	end

	next_bolt_in = next_bolt_in - dt
	if next_bolt_in <= 0 then
		bolt_alpha = 0.6
		next_bolt_in = randfloat(3, 8)
	end
end

function scene.draw()
	love.graphics.clear(0.05, 0.06, 0.10, 1)

	love.graphics.setColor(0.6, 0.6, 0.7, 0.25)
	for _, drop in pairs(rain.drops) do
		love.graphics.line(drop.x, drop.y, drop.x, drop.y + drop.length)
	end

	if bolt_alpha > 0 then
		love.graphics.setColor(1, 1, 1, bolt_alpha)
		love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
	end

	love.graphics.setColor(0.7, 0.9, 1, 1)
	love.graphics.print("Thunderstorm", 16, 16)
end

return scene
