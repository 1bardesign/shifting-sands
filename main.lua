--shorthand
lg = love.graphics

local shaders = require("shaders")

local detail_scale = 1

local terrain_res = 256
local terrain_size = 200

local chunky_pixels = 1

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
end

function love.load()
	first_draw = true

	pixel = lg.newCanvas(1, 1)

	love.resize(lg.getDimensions())

	--terrain geom
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
	terrain_mesh = lg.newMesh( #verts, "triangles", "static")
	terrain_mesh:setVertices(verts)
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
				vx - 0.5, vy - 0.5,
				u, v,
			})
			table.insert(veg_verts, {
				vx + 0.5, vy - 0.5,
				u, v,
			})
			table.insert(veg_verts, {
				vx + 0.5, vy + 0.5,
				u, v,
			})
			table.insert(veg_verts, {
				vx - 0.5, vy + 0.5,
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

	colour_map = lg.newImage("grad.png")
	height_map = lg.newImage("height.png")

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
		height_map = height_map,
		height_scale = 32,
		terrain = terrain_canvas,
		terrain_grad = gradient_canvas,
		terrain_res = terrain_res,
		obj_euler = {0, 0.0, math.pi * 0.5},
		--camera
		cam_from = {
			0,
			terrain_size * -0.3,
			terrain_size * 0.7
		},
		cam_to = {0, 0, 0},

		veg_vert_start = veg_offset,
		veg_height_scale = 2,
	}

	for i,v in ipairs({
		shaders.terrain_mesh,
		shaders.vegetation_mesh,
	}) do
		send_uniform_table(v, mesh_shader_uniforms)
	end
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

	local c_o = mesh_shader_uniforms.cam_from
	local l = (0.4 + math.sin(cam_t * 0.3) * 0.2) * terrain_res
	c_o[1] = math.sin(cam_t) * l
	c_o[3] = math.cos(cam_t) * l

	for i,v in ipairs{
		shaders.terrain_mesh,
		shaders.vegetation_mesh,
	} do
		send_uniform_table(v, mesh_shader_uniforms)
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
	
	--clear to sea col (todo: lookup from tex)
	local r = 0x1b / 255
	local g = 0x30 / 255
	local b = 0x99 / 255
	lg.clear(
		r, g, b, 1.0,
		0, 0
	)

	lg.setShader(shaders.terrain_mesh)
	--render island
	lg.draw(
		terrain_mesh,
		cw * 0.5, ch * 0.5
	)
	--render vegetation
	lg.setShader(shaders.vegetation_mesh)
	--render island
	lg.draw(
		vegetation_mesh,
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
	
	if love.keyboard.isDown("`") then
		lg.setBlendMode("alpha", "alphamultiply")

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
	elseif k == "s" and ctrl then
		local id = sbc:newImageData()
		love.filesystem.write(
			string.format("screenshot-%d.png", os.time()),
			id:encode("png")
		)
	end
end