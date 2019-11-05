local shaders = require("shaders")

local detail_scale = 1

local terrain_res = 256
local terrain_size = 200

local chunky_pixels = 1

function love.load()
	pixel = love.graphics.newCanvas(1, 1)

	--screenbuffer
	sw, sh = love.graphics.getDimensions()
	cw, ch = math.floor(sw / chunky_pixels), math.floor(sh / chunky_pixels)
	
	sbc = love.graphics.newCanvas(cw, ch, {
		msaa = 16,
	})
	sbc:setFilter("nearest", "nearest")

	--canvas for rendering terrain
	terrain_canvas = love.graphics.newCanvas(terrain_res, terrain_res, {format="rgba16f"})

	gradient_map = love.graphics.newImage("grad.png")
	height_map = love.graphics.newImage("height.png")

	shaders.world:send("detail_scale", detail_scale)

	shaders.mesh:send("gradient_map", gradient_map)
	shaders.mesh:send("height_map", height_map)

	local verts = {}
	--generate corners
	for y = 0, terrain_res do
		for x = 0, terrain_res do
			local u = x / terrain_res
			local v = y / terrain_res
			table.insert(verts, {
				--centered
				(u - 0.5) * terrain_size,
				(v - 0.5) * terrain_size,
				--uvs
				u, v
			})
		end
	end
	--generate index map
	local indices = {}
	local step_y = terrain_res + 1
	for y = 0, terrain_res - 1 do
		for x = 0, terrain_res - 1 do
			local i = x + y * step_y + 1;
			local a = 0
			local b = 1
			local c = step_y
			local d = step_y + 1

			table.insert(indices, i + a)
			table.insert(indices, i + b)
			table.insert(indices, i + c)
			table.insert(indices, i + b)
			table.insert(indices, i + c)
			table.insert(indices, i + d)
		end
	end
	--upload to gpu
	terrain_mesh = love.graphics.newMesh( step_y * step_y, "triangles", "static")
	terrain_mesh:setVertices(verts)
	terrain_mesh:setVertexMap(indices)
end

local t = love.math.random()
local t_scale = (1 / 10000)

local cam_t = love.math.random() * math.pi * 2
local cam_t_scale = (1 / 20) * math.pi * 2

function love.draw()
	--render to canvas
	love.graphics.setCanvas(terrain_canvas)
	
	love.graphics.setBlendMode("alpha", "alphamultiply")
	
	love.graphics.setShader(shaders.world)
	shaders.world:send("t", t)

	love.graphics.draw(
		pixel,
		0, 0,
		0,
		terrain_res, terrain_res
	)
	
	--render mesh
	love.graphics.setBlendMode("alpha", "alphamultiply")
	love.graphics.setCanvas({
		sbc,
		depth = true,
	})
	love.graphics.setDepthMode("greater", true)
	local r = 0x1b / 255
	local g = 0x30 / 255
	local b = 0x99 / 255
	love.graphics.clear(
		r, g, b, 0,
		0, 0
	)
	love.graphics.setShader(shaders.mesh)
	shaders.mesh:send("terrain", terrain_canvas)
	shaders.mesh:send("obj_euler", {cam_t, 0.0, math.pi * 0.5})
	shaders.mesh:send("cam_offset", {0, terrain_size * -0.2, terrain_size * 0.5})
	shaders.mesh:send("cam_euler", {0, 0, -0.5})
	-- shaders.mesh:send("terrain_res", terrain_res)
	shaders.mesh:send("height_scale", 24)
	--render using mesh
	love.graphics.draw(
		terrain_mesh,
		cw * 0.5, ch * 0.5
	)

	--upscale canvas to screen
	love.graphics.setBlendMode("alpha", "premultiplied")
	love.graphics.setDepthMode()
	love.graphics.setShader()
	love.graphics.setCanvas()
	love.graphics.draw(
		sbc,
		sw * 0.5, sh * 0.5,
		0,
		chunky_pixels, chunky_pixels,
		cw * 0.5, ch * 0.5
	)
	
	if love.keyboard.isDown("`") then
		love.graphics.draw(terrain_canvas)

		love.graphics.setBlendMode("alpha", "alphamultiply")
		love.graphics.print(string.format(
			"fps: %d - %04.3f",
			love.timer.getFPS(),
			tostring(last_dt)
		))
	end
end

function love.update(dt)
	t = t + dt * t_scale
	cam_t = cam_t + dt * cam_t_scale 

	last_dt = dt
end

function love.keypressed(k)
	local ctrl = love.keyboard.isDown("lctrl")
	if k == "r" and ctrl then
		love.event.quit("restart")
	elseif k == "q" and ctrl or k == "escape" then
		love.event.quit()
	end
end