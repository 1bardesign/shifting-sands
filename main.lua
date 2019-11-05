local world = {}
local entities = {}

local world_shader = love.graphics.newShader([[
extern float t;
extern float detail_scale;

#ifdef PIXEL
vec3 hash3(vec2 p) {
	vec3 q = vec3(dot(p, vec2(127.1, 311.7)),
				  dot(p, vec2(269.5, 183.3)),
				  dot(p, vec2(419.2, 371.9)));
	return fract(sin(q) * 43758.5453);
}

vec3 point(vec2 x, float u) {
	return (hash3(x) - vec3(0.5, 0.5, 0.0)) * vec3(u, u, 1.0) + vec3(x, 0.0);
}

float noise(vec2 x, float u, float v ) {
	vec2 p = floor(x);
	vec2 f = fract(x);

	float vpow = 1.0 + 63.0 * pow(1.0 - v, 4.0);

	float wv = 0.0;
	float wt = 0.0;
	for(int j = -2; j <= 2; j++)
	for(int i = -2; i <= 2; i++)
	{
		vec2  g = vec2(float(i), float(j));
		vec3  o = point(p + g, u);
		vec2  r = o.xy - p - f;

		float d = dot(r, r);
		
		d = sqrt(d);

		float sfac = smoothstep(0.0, 1.0, clamp(d / 1.5, 0.0, 1.0));
		float f = pow(1.0 - sfac, vpow);

		wv += o.z * f;
		wt += f;
	}

	return (wv / wt) * 2.0 - 1.0;
}

const float diminish_octave_scale = 0.25;
float distorted_noise(vec2 x, int iters, float u, float v, vec2 vo1, vec2 vo2) {
	float diminish_octave = float(iters) * diminish_octave_scale;
	for(int i = 0; i < iters; i++) {
		float fac = float(i + 1);
		float scale = 1.0 / float(i + 1);
		vec2 noff = vec2(
			noise(
				(x.xy + vo1 * fac),
				u, v
			),
			noise(
				(x.yx - vo1 * fac),
				u, v
			)
		);
		x += noff / fac * diminish_octave;
	}
	return noise(x, u, v);
}

vec2 rotate(vec2 x, float t) {
	float s = sin(t);
	float c = cos(t);
	return vec2(
		x.x * c + x.y * -s,
		x.x * s + x.y * c
	);
}

const float TAU = 3.14159;
float fracnoise(vec2 p, float t) {
	float n = 0.5;

	n += distorted_noise(
		p * 0.097 + vec2(269.5, 183.3),
		8,
		1.0, 1.0,
		rotate(vec2(127.1, 311.7), t * TAU + 0.3),
		rotate(vec2(269.5, 183.3), -t * TAU + 0.2)
	) * 0.2;

	n += distorted_noise(
		p * 0.13,
		6,
		1.0, 0.8,
		rotate(vec2(127.1, 311.7), t * TAU + 0.3),
		rotate(vec2(269.5, 183.3), -t * TAU + 0.2)
	) * 0.2;

	n += distorted_noise(
		p * 0.21 - vec2(269.5, 183.3),
		4,
		1.0, 0.7,
		rotate(vec2(127.1, 311.7), (t * 1.5) * TAU - 0.3),
		rotate(vec2(269.5, 183.3), -(t * 1.5) * TAU - 0.5)
	) * 0.1;

	return n;
}

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
	vec2 pos = screen_coords * 0.25 * detail_scale;


	float n = fracnoise(pos, t);

	float dmid = length(texture_coords - vec2(0.5));

	n = n * 1.1 + 0.3;
	n -= dmid * 2.5;

	float noffset = 0.5 + distorted_noise(
		pos * 0.43 + vec2(77.3, 99.7),
		3,
		1.0, 1.0,
		rotate(vec2(127.1, 311.7), (t * 0.3) * TAU + 25.0),
		rotate(vec2(269.5, 183.3), -(t * 0.3) * TAU)
	) * 0.5;

	float biome = 0.5 + distorted_noise(
		pos * 0.071 + vec2(874.3, 57.1),
		3,
		1.0, 1.0,
		rotate(vec2(127.1, 311.7), (t * 0.2) * TAU + 25.0),
		rotate(vec2(269.5, 183.3), -(t * 0.2) * TAU)
	) * 0.5;

	float alpha = 0.05;

	alpha *= min(
		min(texture_coords.x, 1.0 - texture_coords.x),
		min(texture_coords.y, 1.0 - texture_coords.y)
	);

	return vec4(
		n,
		biome,
		noffset,
		alpha
	);
}
#endif
]])

local mesh_shader = love.graphics.newShader([[

extern Image terrain;

extern Image gradient_map;
extern Image height_map;

extern float height_scale;

extern vec3 cam_offset;
extern vec3 cam_euler;

extern vec3 obj_euler;

mat4 proj(vec2 screen, float fov, float near, float far) {
	float aspect = screen.x / screen.y;
	float f = 1.0 / tan(fov / 2.0);
	float xpr = aspect / f;
	float ypr = f;
	float fmn = (far - near);
	float zpr = (far + near) / fmn;
	float zhpr = (2.0 * far * near) / fmn;
	return mat4(
		xpr, 0.0, 0.0, 0.0,
		0.0, ypr, 0.0, 0.0,
		0.0, 0.0, zpr, -1.0,
		0.0, 0.0, zhpr, 0.0
	);
}

vec2 rotate(vec2 v, float t) {
	float s = sin(t);
	float c = cos(t);
	return vec2(
		v.x * c + v.y * -s,
		v.x * s + v.y * c
	);
}

extern float terrain_res;

float height(vec2 uv) {
	return Texel(height_map, uv).r;
}

float height_at(vec2 uv) {
	return height(Texel(terrain, uv).xy);
}

vec3 rotate_euler(vec3 v, vec3 e) {
	v.xy = rotate(v.xy, e.x);
	v.xz = rotate(v.xz, e.y);
	v.yz = rotate(v.yz, e.z);
	return v;
}

varying vec3 v_normal;

#ifdef VERTEX
const bool ortho = false;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
	vec2 uv = VaryingTexCoord.xy;
	vec4 t = Texel(terrain, uv);

	vec2 luv = t.xy;

	float h = height(luv);
	
	vec2 uv_r = vec2(1.0, 0.0) / terrain_res;
	vec2 uv_d = vec2(0.0, 1.0) / terrain_res;
	v_normal = vec3(
		height_at(uv + uv_r) - height_at(uv - uv_r),
		height_at(uv + uv_d) - height_at(uv - uv_d),
		0.0
	);
	v_normal *= 5.0;
	v_normal.z = -sqrt(1.0 - dot(v_normal.xy, v_normal.xy));
	v_normal = normalize(v_normal);

	//apply noise offset
	luv.x += t.z * 0.05;

	vec4 g = Texel(gradient_map, luv);

	//output colour
	VaryingColor.rgb = g.rgb;
	VaryingColor.a = 1.0;

	//project height
	vertex_position.z = h * height_scale;
	
	//apply object rotation
	vertex_position.xyz = rotate_euler(vertex_position.xyz, obj_euler);

	//move camera
	vertex_position.xyz -= cam_offset.xyz;

	//rotate camera
	vertex_position.xyz = rotate_euler(vertex_position.xyz, cam_euler);

	//ortho cam
	if (ortho) {
		vertex_position.xy /= love_ScreenSize.xy * 0.5;
		vertex_position.z /= 1000.0;
	}
	else {
		//perspective cam
		vertex_position = proj(love_ScreenSize.xy, 1.0, 0.1, 1000.0) * vertex_position;
	}

	return vertex_position;
}
#endif
#ifdef PIXEL
vec3 light_dir = vec3(0.0, 0.0, 1.0);
vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
	float light = 0.5 + dot(normalize(v_normal), normalize(-light_dir)) * 0.5;
	color.rgb *= light;
	return color;
}
#endif
]])

local detail_scale = 2

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

	world_shader:send("detail_scale", detail_scale)

	mesh_shader:send("gradient_map", gradient_map)
	mesh_shader:send("height_map", height_map)

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
local t_scale = 10000
function love.draw()
	--render to canvas
	love.graphics.setCanvas(terrain_canvas)
	love.graphics.setShader(world_shader)
	world_shader:send("t", t)
	love.graphics.setBlendMode("alpha", "alphamultiply")

	local overlay_scale = 1.0

	local ox = love.math.random() * (1 - overlay_scale)
	local oy = love.math.random() * (1 - overlay_scale)

	love.graphics.draw(
		pixel,
		ox * terrain_res, oy * terrain_res,
		0,
		terrain_res * overlay_scale,
		terrain_res * overlay_scale
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
	love.graphics.setShader(mesh_shader)
	mesh_shader:send("terrain", terrain_canvas)
	mesh_shader:send("obj_euler", {love.timer.getTime() * 0.05, 0.0, math.pi * 0.5})
	mesh_shader:send("cam_offset", {0, terrain_size * -0.2, terrain_size * 0.5})
	mesh_shader:send("cam_euler", {0, 0, -0.5})
	mesh_shader:send("terrain_res", terrain_res)
	mesh_shader:send("height_scale", 24)
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
	love.graphics.setBlendMode("alpha", "alphamultiply")
	love.graphics.print(string.format(
		"fps: %d - %04.3f",
		love.timer.getFPS(),
		tostring(last_dt)
	))
end

function love.update(dt)
	t = t + dt / t_scale
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