local shader_common_stuff = [[

vec2 rotate(vec2 v, float t) {
	float s = sin(t);
	float c = cos(t);
	return vec2(
		v.x * c + v.y * -s,
		v.x * s + v.y * c
	);
}

]]

local shader_3d_stuff = [[
extern vec3 cam_offset;
extern vec3 cam_euler;

extern vec3 obj_euler;

const bool ortho = false;

vec3 rotate_euler(vec3 v, vec3 e) {
	v.xy = rotate(v.xy, e.x);
	v.xz = rotate(v.xz, e.y);
	v.yz = rotate(v.yz, e.z);
	return v;
}

mat4 proj(vec2 screen, float fov, float near, float far) {
	float aspect = screen.x / screen.y;
	float f = 1.0 / tan(fov / 2.0);
	float xpr = f / aspect;
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

vec4 transform_to_screen(vec4 v) {
	//apply object rotation
	v.xyz = rotate_euler(v.xyz, obj_euler);

	//move camera
	v.xyz -= cam_offset.xyz;

	//rotate camera
	v.xyz = rotate_euler(v.xyz, cam_euler);

	//ortho cam
	if (ortho) {
		v.xy /= love_ScreenSize.xy * 0.5;
		v.z /= 1000.0;
	}
	else {
		//perspective cam
		v = proj(love_ScreenSize.xy, 1.0, 1.0, 1000.0) * v;
	}
	return v;
}
]]

local shader_noise_stuff = [[
vec3 hash3(vec2 p) {
	vec3 q = vec3(dot(p, vec2(127.1, 311.7)),
				  dot(p, vec2(269.5, 183.3)),
				  dot(p, vec2(419.2, 371.9)));
	return fract(sin(q) * 43758.5453);
}

vec3 hash3_signed(vec2 p) {
	return hash3(p) * 2.0 - vec3(1.0);
}

vec3 noise_point(vec2 x, float u) {
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
		vec3  o = noise_point(p + g, u);
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

const float TAU = 3.14159;
float fracnoise(vec2 p, float t, float u, float v, int octaves, float octave_factor, float distort) {
	float n = 0.0;

	float i_of = 1.0 / octave_factor;
	float octave_total = 0.0;

	for(int i = 0; i < octaves; i++) {
		float f = pow(octave_factor, float(i + 1));
		octave_total += f;
		float nval = noise(
			rotate(
				p,
				t * TAU + float(i) * 0.71
			),
			u, v
		);
		n += f * nval;
		//modify
		p *= i_of;
		p += rotate(
			vec2(69.5, 13.3),
			(float(i) * (nval * distort))
		);
	}

	return n /= octave_total;
}
]]

local world_shader = love.graphics.newShader(shader_common_stuff..shader_noise_stuff..[[
extern float t;
extern float detail_scale;
extern vec2 seed_offset;

#ifdef PIXEL
vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
	vec2 pos = screen_coords * 0.05 * detail_scale + seed_offset;

	//points for distance
	float hd = 0.2;
	vec3 h1 = hd * hash3_signed(seed_offset);
	vec3 h2 = hd * hash3_signed(seed_offset + vec2(38.1, 91.3));
	
	vec2 p1 = h1.xy;
	vec2 p2 = h2.xy;
	vec2 p3 = vec2(h1.z, h2.x);
	vec2 cent = (p1 + p2 + p3) / 3.0;
	vec2 mid = vec2(0.5);
	p1 = p1 - cent + mid;
	p2 = p2 - cent + mid;
	p3 = p3 - cent + mid;

	float dmid = min(
		min(
			length(texture_coords - p1),
			length(texture_coords - p2)
		),
		length(texture_coords - p3)
	);

	float n = fracnoise(
		pos,
		t, 1.0, 1.0,
		4, 0.47,
		0.1
	);
	n = 1.0 - abs(n) * 0.75;
	n -= dmid * 3.0;

	float biome = 0.5 + fracnoise(
		pos * 0.51,
		t, 1.0, 1.0,
		1, 0.5,
		0.0
	) * 0.5;

	float vn = fracnoise(
		pos * 0.56 + vec2(84.3, 75.1),
		t,
		0.5, 1.0,
		4, 0.7,
		1.0
	);
	float vegetation = float(
		//noise bound
		abs(vn) < 0.25
		//height bound
		&& n > 0.4
		&& n < 0.6
	);

	return vec4(
		n,
		biome,
		vegetation,
		color.a
	);
}
#endif
]])

local shader_terrain_stuff = [[
extern Image height_map;

extern Image terrain;

extern float height_scale;

float height(vec2 uv) {
	return Texel(height_map, uv).r * height_scale;
}

float height_at(vec2 uv) {
	return height(Texel(terrain, uv).xy);
}
]]

local terrain_mesh_shader = love.graphics.newShader(shader_common_stuff..shader_3d_stuff..shader_terrain_stuff..[[
extern Image gradient_map;

#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position) {
	vec2 uv = VaryingTexCoord.xy;
	vec4 t = Texel(terrain, uv);

	vec2 luv = t.xy;

	float h = height(luv);

	//forward to frag for grad map lookup
	VaryingTexCoord.xy = luv;

	//project height
	vertex_position.z = h;
	
	return transform_to_screen(vertex_position);
}
#endif
#ifdef PIXEL
vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
	color.rgb = Texel(gradient_map, texture_coords).rgb;

	return color;
}
#endif
]])

local vegetation_mesh_shader = love.graphics.newShader(shader_common_stuff..shader_noise_stuff..shader_3d_stuff..shader_terrain_stuff..[[
extern Image gradient_map;

extern float veg_height_scale;
extern float terrain_res;

#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position) {
	vec2 uv = VaryingTexCoord.xy;
	
	//offset entire vegetation (including sample pos) by noise
	vec2 voff = vec2(
		noise(
			uv * 128.0, 
			1.0, 1.0
		),
		noise(
			uv * 128.0 + vec2(4923.2, -230.1),
			1.0, 1.0
		)
	);
	voff = voff * 2.0;
	uv += voff / terrain_res;
	vertex_position.xy += voff;

	//sample
	vec4 t = Texel(terrain, uv);

	vec2 luv = t.xy;
	float veg_amount = t.z;

	bool is_point = (VaryingColor.r == 0.0);
	float point = float(is_point);

	if(veg_amount <= 0.0 && is_point) {
		//clip
		return vec4(1.0 / 0.0);
	}

	//write vert colour
	
	//pick native colour
	VaryingColor.rgb = mix(
		vec3(0.0, 0.2, 0.1),
		vec3(0.1, 0.3, 0.0),
		point
	) + hash3(uv * 1000.0) * 0.05;
	
	//mix with underlying colour
	VaryingColor = mix(
		Texel(gradient_map, luv),
		VaryingColor,
		veg_amount * 0.25 + point * 0.5
	);

	float h = 
		height(luv)
		+ (point * 2.0 - 1.0)
			* veg_height_scale * (veg_amount * point);

	//forward to frag for grad map lookup
	VaryingTexCoord.xy = luv;

	//project height
	vertex_position.z = h;
	
	return transform_to_screen(vertex_position);
}
#endif
#ifdef PIXEL
vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
	return color;
}
#endif
]])

return {
	world = world_shader,
	terrain_mesh = terrain_mesh_shader,
	vegetation_mesh = vegetation_mesh_shader,
}