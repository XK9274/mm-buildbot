-- Adapted from messersm/love2d-demos, circle-amongst-squares/ (audio and the
-- light shader dropped -- see README.md). Collision via lib/bump.lua (MIT,
-- kikito/bump.lua).

local bump = require("lib.bump")

local scene = {}
local world, squares, circle, next_move_in

local function newSquare()
	local width, height = love.graphics.getDimensions()
	local square = {}
	square.width = love.math.random(10, 40)
	square.height = square.width
	square.color = { love.math.random(), love.math.random(), love.math.random(), 1 }
	square.x = love.math.random(0, width - square.width)
	square.y = love.math.random(0, height - square.height)
	return square
end

-- Nudge a square that's sitting near the circle, so the field feels alive.
local function moveSomething()
	local x, y = circle.x + circle.r, circle.y + circle.r
	for _, sq in pairs(squares) do
		local dx = sq.x + sq.width / 2 - x
		local dy = sq.y + sq.height / 2 - y
		local distance = dx * dx + dy * dy
		if 5000 < distance and distance < 8000 then
			local sq_dx = love.math.random(-10, 10)
			local sq_dy = love.math.random(-10, 10)
			sq.x, sq.y = world:move(sq, sq.x + sq_dx, sq.y + sq_dy)
			return true
		end
	end
	return false
end

function scene.load()
	world = bump.newWorld()
	squares = {}
	circle = { x = 0, y = 0, dx = 0, dy = 0, speed = 100, r = 10 }
	world:add(circle, circle.x, circle.y, circle.r * 2, circle.r * 2)

	for _ = 1, 60 do
		local square = newSquare()
		table.insert(squares, square)
		world:add(square, square.x, square.y, square.width, square.height)
	end

	next_move_in = love.math.random(2, 5)
end

function scene.update(dt)
	if love.keyboard.isDown("left") then
		circle.dx = -circle.speed
	elseif love.keyboard.isDown("right") then
		circle.dx = circle.speed
	else
		circle.dx = 0
	end

	if love.keyboard.isDown("up") then
		circle.dy = -circle.speed
	elseif love.keyboard.isDown("down") then
		circle.dy = circle.speed
	else
		circle.dy = 0
	end

	local x = circle.x + circle.dx * dt
	local y = circle.y + circle.dy * dt
	if x ~= circle.x or y ~= circle.y then
		circle.x, circle.y = world:move(circle, x, y)
	end

	next_move_in = next_move_in - dt
	if next_move_in <= 0 then
		next_move_in = moveSomething() and love.math.random(2, 5) or 0.5
	end
end

function scene.draw()
	love.graphics.clear(0.03, 0.03, 0.05, 1)

	for _, sq in pairs(squares) do
		love.graphics.setColor(sq.color)
		love.graphics.rectangle("fill", sq.x, sq.y, sq.width, sq.height)
	end

	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.arc("fill", circle.x + circle.r, circle.y + circle.r, circle.r, 0, math.pi * 2)

	love.graphics.setColor(0.6, 0.6, 0.6, 1)
	love.graphics.print("D-pad to move", 16, 456)
end

return scene
