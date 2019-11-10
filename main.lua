--shorthand
lg = love.graphics

local shaders = require("shaders")

local ui = nil

local detail_scale = 1

local terrain_res = 256
local terrain_size = 200
local terrain_height = 32

local chunky_pixels = 2

function send_uniform_table(shader, t)
	for k, v in pairs(t) do
		if shader:hasUniform(k) then
			shader:send(k, v)
		end
	end
end

function love.resize(w, h)
	cw, ch = math.floor(w / chunky_pixels), math.floor(h / chunky_pixels)
	
	sbc = lg.newCanvas(cw, ch, {
		msaa = 0,
	})
	sbc:setFilter("nearest", "nearest")

	if not ui then
		ui = require("ui")(w, h)
	else
		ui:resize(w, h)
	end
end

function love.load()
	first_draw = true

	pixel = lg.newCanvas(1, 1)

	love.resize(lg.getDimensions())

	--terrain geom
	local terrain_vtable = {
		{"VertexPosition", "float", 2},
		{"VertexTexCoord", "float", 2},
		{"VertexEdgeInfo", "float", 3},
	}
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
				u, v,
				--edge info
				(x == 0 and -1 or x == terrain_res and 1 or 0.0),
				(y == 0 and -1 or y == terrain_res and 1 or 0.0),
				0,
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
	terrain_mesh = lg.newMesh(terrain_vtable, verts, "triangles", "static")
	terrain_mesh:setVertexMap(indices)

	--vegetation geom
	local veg_verts = {}
	local veg_indices = {}
	for y = 1, terrain_res do
		for x = 1, terrain_res do
			local u = (x - 0.5) / terrain_res
			local v = (y - 0.5) / terrain_res
			local vx = (u - 0.5) * terrain_size
			local vy = (v - 0.5) * terrain_size
			local hs = 0.75
			--centered point
			table.insert(veg_verts, {
				vx,
				vy,
				--uvs
				u, v,
				--vert col as point flag
				0.0
			})
			local i = #veg_verts
			--corners
			table.insert(veg_verts, {
				vx - hs, vy - hs,
				u, v,
			})
			table.insert(veg_verts, {
				vx + hs, vy - hs,
				u, v,
			})
			table.insert(veg_verts, {
				vx + hs, vy + hs,
				u, v,
			})
			table.insert(veg_verts, {
				vx - hs, vy + hs,
				u, v,
			})

			table.insert(veg_indices, i)
			table.insert(veg_indices, i+1)
			table.insert(veg_indices, i+2)

			table.insert(veg_indices, i)
			table.insert(veg_indices, i+2)
			table.insert(veg_indices, i+3)

			table.insert(veg_indices, i)
			table.insert(veg_indices, i+3)
			table.insert(veg_indices, i+4)

			table.insert(veg_indices, i)
			table.insert(veg_indices, i+4)
			table.insert(veg_indices, i+1)
		end
	end

	--
	vegetation_mesh = lg.newMesh( #veg_verts, "triangles", "static")
	vegetation_mesh:setVertices(veg_verts)
	vegetation_mesh:setVertexMap(veg_indices)

	--canvas for rendering terrain
	terrain_canvas = lg.newCanvas(terrain_res, terrain_res, {format="rgba16f"})
	gradient_canvas = lg.newCanvas(terrain_res, terrain_res, {format="rgba16f"})

	local climates = {
		"cold",
		"wet",
		"temperate",
		"dry",
	}
	colour_map = love.image.newImageData(16, #climates)
	vegetation_map = love.image.newImageData(16, #climates)
	height_map = love.image.newImageData(16, #climates)
	water_map = love.image.newImageData(16, #climates)
	for i,v in ipairs(climates) do
		local id = love.image.newImageData(
			table.concat{"img/climates/", v, ".png"}
		)
		local w = id:getWidth()
		for j, onto in ipairs {
			colour_map,
			vegetation_map,
			height_map,
			water_map,
		} do
			onto:paste(id, 0, i-1, 0, j-1, w, 1)
		end
	end

	colour_map = lg.newImage(colour_map)
	height_map = lg.newImage(height_map)

	vegetation_map = lg.newImage(vegetation_map)
	water_map = lg.newImage(water_map, {linear=true})

	sea_colour_map = lg.newImage("img/water/body.png")
	foam_colour_map = lg.newImage("img/water/foam.png")
	foam_colour_map:setWrap("repeat")

	world_shader_uniforms = {
		detail_scale = detail_scale,
		seed_offset = {
			(love.math.random() - 0.5) * 1000,
			(love.math.random() - 0.5) * 1000,
		},
		t = love.math.random(),
	}
	send_uniform_table(shaders.world, world_shader_uniforms)

	gradient_shader_uniforms = {
		texture_size = {terrain_res, terrain_res},
		height_map = height_map,
	}
	send_uniform_table(shaders.gradient, gradient_shader_uniforms)

	mesh_shader_uniforms = {
		colour_map = colour_map,
		vegetation_map = vegetation_map,
		height_map = height_map,
		water_map = water_map,

		height_scale = terrain_height,
		terrain = terrain_canvas,
		terrain_grad = gradient_canvas,
		terrain_res = terrain_res,
		obj_euler = {0, 0.0, math.pi * 0.5},
		--camera
		cam_from = {
			0,
			-(terrain_height * 1.5), --(only one not filled in in draw)
			0,
		},
		cam_to = {0, 0, 0},

		veg_vert_start = veg_offset,
		veg_height_scale = 2,

		sea_colour_map = sea_colour_map,
		foam_colour_map = foam_colour_map,
		sea_level = 0, --set in draw
		foam_t = 0,

		sky_col = {
			0x37 / 255,
			0x7c / 255,
			0xbd / 255,
			1
		},
	}
end

local t_scale = (1 / 1000)

function render_terrain()

	local skip_draw = false

	if first_draw then
		lg.setColor(1,1,1,1)
	else
		lg.setColor(1,1,1, 0.01)
		skip_draw = true
	end

	if not skip_draw then
		lg.setCanvas(terrain_canvas)
		lg.setBlendMode("alpha", "alphamultiply")
		lg.setShader(shaders.world)
		lg.draw(
			pixel,
			0, 0,
			0,
			terrain_res, terrain_res
		)

		lg.setCanvas(gradient_canvas)
		lg.setShader(shaders.gradient)
		lg.draw(terrain_canvas)

	end

	lg.setColor(1,1,1,1)
end

local cam_t = love.math.random() * math.pi * 2
local cam_t_scale = (1 / 20) * math.pi * 2

function love.draw()
	--update shaders
	send_uniform_table(shaders.world, world_shader_uniforms)

	local g_t = love.timer.getTime();
	local msu = mesh_shader_uniforms

	local c_o = msu.cam_from
	local l = (0.35 + math.sin(cam_t * 0.3) * 0.1) * terrain_size
	c_o[1] = math.sin(cam_t) * l
	c_o[3] = math.cos(cam_t) * l

	msu.sea_level = terrain_height * (6 / 255) * (1.0 + 0.2 * math.sin(g_t / 10.0))
	msu.foam_t = (g_t / 2.0) % 1

	for i,v in ipairs{
		shaders.terrain_mesh,
		shaders.vegetation_mesh,
		shaders.sea_mesh,
	} do
		send_uniform_table(v, msu)
	end

	--render to canvas
	render_terrain()
	
	--render mesh
	lg.setBlendMode("alpha", "alphamultiply")
	lg.setCanvas({
		sbc,
		depth = true,
	})
	lg.setDepthMode("greater", true)
	
	--clear to error col
	do
		local r = 0x80 / 255
		local g = 0xb9 / 255
		local b = 0xdf / 255
		lg.clear(
			r, g, b, 1,
			0, 0
		)
	end

	--render island
	lg.setShader(shaders.terrain_mesh)
	lg.draw(
		terrain_mesh,
		cw * 0.5, ch * 0.5
	)
	--render vegetation
	lg.setShader(shaders.vegetation_mesh)
	lg.draw(
		vegetation_mesh,
		cw * 0.5, ch * 0.5
	)

	--render water
	lg.setShader(shaders.sea_mesh)
	lg.draw(
		terrain_mesh,
		cw * 0.5, ch * 0.5
	)

	--upscale canvas to screen
	lg.setBlendMode("alpha", "premultiplied")
	lg.setDepthMode()
	lg.setShader()
	lg.setCanvas()
	lg.draw(
		sbc,
		lg.getWidth() * 0.5, lg.getHeight() * 0.5,
		0,
		chunky_pixels, chunky_pixels,
		cw * 0.5, ch * 0.5
	)
	
	--draw ui
	lg.setBlendMode("alpha", "alphamultiply")
	if not hide_ui then
		ui:draw()
	end

	if love.keyboard.isDown("`") then
		--debug
		lg.draw(terrain_canvas, 0, 0)
		lg.draw(gradient_canvas, terrain_canvas:getWidth(), 0)

		lg.print(string.format(
			"fps: %d - %04.3f",
			love.timer.getFPS(),
			tostring(last_dt)
		))
	end

	first_draw = false
end

function love.update(dt)
	world_shader_uniforms.t = world_shader_uniforms.t + dt * t_scale
	cam_t = cam_t + dt * cam_t_scale 

	ui:update(dt)

	last_dt = dt
end

function love.keypressed(k)
	local ctrl = love.keyboard.isDown("lctrl")
	if k == "r" then
		if ctrl then
			love.event.quit("restart")
		else
			love.load()
		end
	elseif k == "q" and ctrl or k == "escape" then
		love.event.quit()
	end
end

--mouse handling
--(single button for now)
local is_clicked = false
function love.mousemoved( x, y, dx, dy, istouch )
	ui:pointer(is_clicked and "drag" or "move", x, y)
end

function love.mousepressed( x, y, button, istouch, presses )
	if button == 1 then
		if hide_ui then
			hide_ui = false
		else
			ui:pointer("click", x, y)
			is_clicked = true
		end
	end
end

function love.mousereleased( x, y, button, istouch, presses )
	if button == 1 then
		ui:pointer("release", x, y)
		is_clicked = false
	end
end

