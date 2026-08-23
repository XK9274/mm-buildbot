-- Menu launcher for the demo scenes under scenes/. Add new demos to the
-- `scenes` list below as they're written.

local scenes = {
	{ name = "Ball in a Rotating Hexagon", module = require("scenes.hexagon") },
	{ name = "The Tutorial", module = require("scenes.tutorial") },
	{ name = "Circle Amongst Squares", module = require("scenes.circle_squares") },
	{ name = "Thunderstorm", module = require("scenes.thunderstorm") },
}

local state = "menu" -- "menu" or "scene"
local selected = 1
local active_scene = nil

local function quit()
	love.event.quit()
end

local function enterScene(index)
	active_scene = scenes[index].module
	state = "scene"
	if active_scene.load then
		active_scene.load()
	end
end

local function backToMenu()
	active_scene = nil
	state = "menu"
end

local function moveSelection(delta)
	selected = ((selected - 1 + delta) % #scenes) + 1
end

function love.update(dt)
	if state == "scene" and active_scene and active_scene.update then
		active_scene.update(dt)
	end
end

function love.keyreleased(key)
	if state == "scene" and active_scene and active_scene.keyreleased then
		active_scene.keyreleased(key)
	end
end

function love.mousepressed(x, y, button, istouch)
	if state == "scene" and active_scene and active_scene.mousepressed then
		active_scene.mousepressed(x, y, button, istouch)
	end
end

function love.mousereleased(x, y, button, istouch)
	if state == "scene" and active_scene and active_scene.mousereleased then
		active_scene.mousereleased(x, y, button, istouch)
	end
end

function love.wheelmoved(x, y)
	if state == "scene" and active_scene and active_scene.wheelmoved then
		active_scene.wheelmoved(x, y)
	end
end

function love.draw()
	if state == "scene" and active_scene then
		active_scene.draw()
		return
	end

	love.graphics.clear(0.03, 0.03, 0.05, 1)
	love.graphics.setColor(0.7, 0.9, 1, 1)
	love.graphics.print("LOVE 11.5 - SDL2 backend", 16, 16)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.print("Select a demo", 16, 46)

	for i, entry in ipairs(scenes) do
		local y = 90 + (i - 1) * 32
		if i == selected then
			love.graphics.setColor(1, 0.85, 0.3, 1)
			love.graphics.print("> " .. entry.name, 32, y)
		else
			love.graphics.setColor(0.7, 0.7, 0.7, 1)
			love.graphics.print("  " .. entry.name, 32, y)
		end
	end

	love.graphics.setColor(0.6, 0.6, 0.6, 1)
	love.graphics.print("Up/Down: select   A/Start: launch   Menu: quit", 16, 456)
end

function love.keypressed(key)
	if key == "home" then
		quit()
		return
	end

	if state == "menu" then
		if key == "escape" then
			quit()
		elseif key == "up" then
			moveSelection(-1)
		elseif key == "down" then
			moveSelection(1)
		elseif key == "return" or key == "space" then
			enterScene(selected)
		end
	elseif state == "scene" then
		if key == "escape" or key == "backspace" then
			backToMenu()
		elseif active_scene.keypressed then
			active_scene.keypressed(key)
		end
	end
end

-- SDL2 game controller support: the MMIYOO joystick driver maps its
-- physical Menu button to "guide" and Select to "back".
function love.gamepadpressed(joystick, button)
	if button == "guide" then
		quit()
		return
	end

	if state == "menu" then
		if button == "dpup" then
			moveSelection(-1)
		elseif button == "dpdown" then
			moveSelection(1)
		elseif button == "a" or button == "start" then
			enterScene(selected)
		elseif button == "back" then
			quit()
		end
	elseif state == "scene" then
		if button == "b" or button == "back" then
			backToMenu()
		elseif active_scene.gamepadpressed then
			active_scene.gamepadpressed(joystick, button)
		end
	end
end
