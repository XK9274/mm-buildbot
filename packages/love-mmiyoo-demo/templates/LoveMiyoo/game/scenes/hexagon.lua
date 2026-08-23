-- Adapted from meenbeese/Love2D-Demo (MIT, see README.md).

local scene = {}

local function vecAdd(a, b)
	return { x = a.x + b.x, y = a.y + b.y }
end

local function vecSub(a, b)
	return { x = a.x - b.x, y = a.y - b.y }
end

local function vecMul(v, s)
	return { x = v.x * s, y = v.y * s }
end

local function dot(a, b)
	return a.x * b.x + a.y * b.y
end

local function length(v)
	return math.sqrt(v.x * v.x + v.y * v.y)
end

local function normalize(v)
	local l = length(v)
	if l == 0 then
		return { x = 0, y = 0 }
	else
		return { x = v.x / l, y = v.y / l }
	end
end

local function clamp(x, minVal, maxVal)
	if x < minVal then return minVal
	elseif x > maxVal then return maxVal
	else return x end
end

local gravity = 400           -- pixels per second^2
local damping = 0.1           -- friction
local restitution = 0.9       -- energy retained per bounce (1 = elastic)

-- Sized to fit the 640x480 window with room for the text overlay.
local hex = {
	center = { x = 320, y = 240 },
	radius = 160,
	sides = 6,
	angle = 0,                 -- current rotation angle (radians)
	angularSpeed = math.pi / 4 -- angular speed in radians/sec (45 deg/sec)
}

local ball = {
	x = hex.center.x,
	y = hex.center.y - 80,
	vx = 100,
	vy = 0,
	radius = 10
}

local renderer_info = "unknown renderer"

local function computeHexVertices()
	local vertices = {}
	for i = 1, hex.sides do
		local a = hex.angle + (2 * math.pi * (i - 1)) / hex.sides
		local x = hex.center.x + hex.radius * math.cos(a)
		local y = hex.center.y + hex.radius * math.sin(a)
		table.insert(vertices, { x = x, y = y })
	end
	return vertices
end

function scene.load()
	hex.angle = 0
	ball.x, ball.y = hex.center.x, hex.center.y - 80
	ball.vx, ball.vy = 100, 0

	local name, version, vendor, device = love.graphics.getRendererInfo()
	renderer_info = string.format("%s %s - %s %s", name or "renderer",
		version or "", vendor or "", device or "")
end

function scene.update(dt)
	dt = math.min(dt, 1 / 30) -- cap dt so a frame spike can't tunnel the ball through a wall

	-- Update the hexagon's rotation.
	hex.angle = hex.angle + hex.angularSpeed * dt

	-- Update ball velocity and position (gravity + damping).
	ball.vy = ball.vy + gravity * dt
	ball.x = ball.x + ball.vx * dt
	ball.y = ball.y + ball.vy * dt

	-- Apply simple damping to simulate friction.
	ball.vx = ball.vx * (1 - damping * dt)
	ball.vy = ball.vy * (1 - damping * dt)

	-- Collision detection with each edge of the hexagon.
	local vertices = computeHexVertices()
	local numVertices = #vertices
	local margin = 0.1  -- small offset to prevent sticking

	-- For each edge, check if the ball penetrates the wall.
	for i = 1, numVertices do
		local A = vertices[i]
		local B = vertices[(i % numVertices) + 1]  -- Wrap-around for last vertex.

		-- Edge vector and its squared length.
		local edge = vecSub(B, A)
		local edgeLenSq = dot(edge, edge)

		-- Find the point P on the edge closest to the ball.
		local ballPos = { x = ball.x, y = ball.y }
		local AtoBall = vecSub(ballPos, A)
		local t = clamp(dot(AtoBall, edge) / edgeLenSq, 0, 1)
		local P = vecAdd(A, vecMul(edge, t))

		-- Distance from the ball center to P.
		local diff = vecSub(ballPos, P)
		local dist = length(diff)

		if dist < ball.radius then
			-- Determine a collision normal. If the ball's center is exactly on the line,
			-- use the edge's inward normal (the polygon is assumed to be defined CCW).
			local normal
			if dist == 0 then
				normal = normalize({ x = -edge.y, y = edge.x })
			else
				normal = normalize(diff)
			end

			-- Compute the wall's local velocity at point P.
			-- For a rotation about hex.center, the local velocity is omega x r.
			local r = vecSub(P, hex.center)
			local v_wall = { x = -hex.angularSpeed * r.y, y = hex.angularSpeed * r.x }

			local ballVel = { x = ball.vx, y = ball.vy }
			local relativeVel = vecSub(ballVel, v_wall)

			-- Only resolve if the ball is moving into the wall.
			if dot(relativeVel, normal) < 0 then
				-- Reflect the relative velocity.
				local dotVal = dot(relativeVel, normal)
				local refReflect = vecSub(relativeVel, vecMul(normal, (1 + restitution) * dotVal))
				local newVel = vecAdd(refReflect, v_wall)
				ball.vx = newVel.x
				ball.vy = newVel.y

				-- Reposition the ball just outside the wall.
				local penetration = ball.radius - dist
				ball.x = ball.x + normal.x * (penetration + margin)
				ball.y = ball.y + normal.y * (penetration + margin)
			end
		end

		-- Also check collisions with the endpoints of the edge.
		for _, point in ipairs({ A, B }) do
			local diffPoint = vecSub(ballPos, point)
			local dPoint = length(diffPoint)
			if dPoint < ball.radius then
				local normalPoint = (dPoint == 0) and { x = 0, y = -1 } or normalize(diffPoint)
				local r = vecSub(point, hex.center)
				local v_wall = { x = -hex.angularSpeed * r.y, y = hex.angularSpeed * r.x }
				local relativeVel = vecSub({ x = ball.vx, y = ball.vy }, v_wall)
				if dot(relativeVel, normalPoint) < 0 then
					local dotVal = dot(relativeVel, normalPoint)
					local relReflect = vecSub(relativeVel, vecMul(normalPoint, (1 + restitution) * dotVal))
					local newVel = vecAdd(relReflect, v_wall)
					ball.vx = newVel.x
					ball.vy = newVel.y
					local penetration = ball.radius - dPoint
					ball.x = ball.x + normalPoint.x * (penetration + margin)
					ball.y = ball.y + normalPoint.y * (penetration + margin)
				end
			end
		end
	end

	-- Discrete per-frame collision can tunnel through on a dt spike (e.g.
	-- the first frame, or a skipped vsync); recover instead of losing the
	-- ball off-screen forever.
	local escapeDist = hex.radius + ball.radius * 4
	if length(vecSub({ x = ball.x, y = ball.y }, hex.center)) > escapeDist then
		ball.x, ball.y = hex.center.x, hex.center.y - 80
		ball.vx, ball.vy = 100, 0
	end
end

function scene.draw()
	love.graphics.clear(0.03, 0.03, 0.05, 1)

	-- Draw the hexagon.
	local vertices = computeHexVertices()
	love.graphics.setColor(1, 1, 1)
	local points = {}
	for _, v in ipairs(vertices) do
		table.insert(points, v.x)
		table.insert(points, v.y)
	end
	love.graphics.polygon("line", points)

	-- Draw the ball.
	love.graphics.setColor(1, 0, 0)
	love.graphics.circle("fill", ball.x, ball.y, ball.radius)

	love.graphics.setColor(0.7, 0.9, 1, 1)
	love.graphics.print("Ball in a rotating hexagon", 16, 16)
	love.graphics.setColor(0.5, 0.7, 0.9, 1)
	love.graphics.print(renderer_info, 16, 36)
	love.graphics.setColor(0.6, 0.6, 0.6, 1)
	love.graphics.print("Select/B: back to menu   Menu: quit", 16, 456)
end

function scene.keypressed(key)
end

function scene.gamepadpressed(joystick, button)
end

return scene
