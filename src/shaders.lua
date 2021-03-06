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
extern vec3 cam_from;
extern vec3 cam_to;

extern vec3 obj_euler;

const bool ortho = false;

varying float cam_distance;
extern vec4 sky_col;

vec3 rotate_euler(vec3 v, vec3 e) {
	v.xy = rotate(v.xy, e.x);
	v.xz = rotate(v.xz, e.y);
	v.yz = rotate(v.yz, e.z);
	return v;
}

mat4 camera_from_to(vec3 from, vec3 to) {
	vec3 forward = normalize(from - to);
	vec3 right = cross(vec3(0.0, 1.0, 0.0), forward);
	vec3 up = cross(forward, right);
	float d_r = dot(right, -from);
	float d_u = dot(up, -from);
	float d_f = dot(forward, -from);
	return mat4(
		right.x, up.x, forward.x, 0.0,
		right.y, up.y, forward.y, 0.0,
		right.z, up.z, forward.z, 0.0,
		d_r,     d_u,  d_f,       1.0
	);
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

#ifdef VERTEX
	//write distance from camera
	cam_distance = length(v.xyz - cam_from);
#endif

	//rotate camera to look at point
	v = camera_from_to(
		cam_from,
		cam_to
	) * v;

	//ortho cam
	if (ortho) {
		v.xy /= love_ScreenSize.xy * 0.5;
		v.z /= 1000.0;
	}
	else {
		if(true) {
			//perspective cam with matrix
			v = proj(love_ScreenSize.xy, 1.0, 1.0, 1000.0) * v;
		} else {
			//fisheye perspective (experimental, needs rescaling)
			v.z = -(length(v.xyz) * 0.5);
			v.xy /= -(v.z);
			v.z /= 1000.0;
			v.x /= love_ScreenSize.x / love_ScreenSize.y;
			//v.w = v.z;
		}
	}
	return v;
}

//todo: externs for this?
const vec3 light_dir = vec3(0.5, 0.5, 1);
const vec3 light_col = vec3(0.7, 0.6, 0.3);
const vec3 light_ambient = vec3(1.0) - light_col;
vec3 light_amount(vec3 normal) {
	//calc lighting
	vec3 light_amount = light_ambient;

	//directional light
	float diffuse_amount = max(
		0.0,
		dot(
			normal,
			normalize(light_dir)
		)
	);
	light_amount += light_col * diffuse_amount;
	return light_amount;
}

#ifdef PIXEL
const float fog_start = 80.0;
const float fog_depth = 100.0;
vec3 do_fog(vec3 c) {
	float fog_amount = clamp((cam_distance - fog_start) / fog_depth, 0.0, 1.0);
	return mix(c, sky_col.rgb, fog_amount);
}
#endif

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

local gradient_shader = love.graphics.newShader([[
extern vec2 texture_size;
extern Image height_map;
#ifdef PIXEL
float height(Image t, vec2 uv) {
	return Texel(height_map, Texel(t, uv).xy).x;
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
	vec2 uv_r = vec2(0.5, 0.0) / texture_size.x;
	vec2 uv_u = vec2(0.0, 0.5) / texture_size.y;
	vec2 d = vec2(
		height(tex, uv - uv_r) - height(tex, uv + uv_r),
		height(tex, uv - uv_u) - height(tex, uv + uv_u)
	);
	return vec4(
		d.x,
		d.y,
		sqrt(1.0 - dot(d, d)),
		1.0
	);
}
#endif
]])

local world_shader = love.graphics.newShader(shader_common_stuff..shader_noise_stuff..[[
extern float t;
extern float detail_scale;
extern vec2 seed_offset;

#ifdef PIXEL
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
	vec2 pos = screen_coords * 0.05 * detail_scale + seed_offset;

	//points for distance
	float dmid = 1000.0;
	float hd = 0.15;
	vec2 mid = vec2(0.5);
	for(int i = 0; i < 3; i++) {
		vec3 h = hash3(seed_offset + vec2(38.1, 91.3) * (i + 1));
		float hb = fract((h.x + h.y + h.z) * 1337.0);
		h.xy = rotate(vec2(h.x, 0.0), h.y * TAU);
		//offset mid
		h.xy = h.xy * hd + mid;
		//scale
		h.z = mix(0.9, 2.0, abs(h.z));
		//calc distance
		float d = length(uv - h.xy) * h.z;

		//set dmid
		dmid = min(dmid, d);
	}

	float n = fracnoise(
		pos,
		t, 1.0, 1.0,
		4, 0.47,
		0.1
	);
	n = 1.0 - abs(n) * 0.75;
	n -= dmid * 3.0;


	float biome = max(
		0.0,
		noise(uv + seed_offset, 0.0, 1.0)
	);

	float vn = noise(
		pos * 0.16 + vec2(84.3, 75.1),
		0.0, 1.0
	);

	vn = sin(
		vn * 5.0 * TAU
	) + 
	noise(
		pos * 1.26 + vec2(34.3, 15.1),
		1.0, 1.0
	) * 1.2;

	float vegetation = float(abs(vn) < 0.8) * clamp(1.0 - abs(vn), 0.4, 1.0);

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
#ifdef VERTEX
attribute vec3 VertexEdgeInfo;
#endif
const float edge_project_distance = 1000.0;

extern Image height_map;

extern Image terrain;
extern Image terrain_grad;

extern float height_scale;

float height(vec2 uv) {
	return Texel(height_map, uv).r * height_scale;
}

float height_at(vec2 uv) {
	return height(Texel(terrain, uv).xy);
}

vec2 offset_terrain_read_uv(vec2 uv, vec2 pos) {
	uv.x += noise(pos * 0.2, 0.0, 1.0) / 16.0;
	return uv;
}
]]

local terrain_mesh_shader = love.graphics.newShader(shader_common_stuff..shader_noise_stuff..shader_3d_stuff..shader_terrain_stuff..[[
extern Image colour_map;

varying vec3 v_normal;
varying vec2 v_pos;

#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position) {
	
	//extrude edge verts
	vertex_position.x = mix(vertex_position.x, edge_project_distance, VertexEdgeInfo.x);
	vertex_position.y = mix(vertex_position.y, edge_project_distance, VertexEdgeInfo.y);

	v_pos = vertex_position.xy;

	vec2 uv = VaryingTexCoord.xy;
	vec4 t = Texel(terrain, uv);


	vec2 luv = t.xy;

	float h = height(luv);

	//forward to frag for grad map lookup
	VaryingTexCoord.xy = luv;

	//project height
	vertex_position.z = h;

	//send gradient
	v_normal = Texel(terrain_grad, uv).rgb * vec3(1.0, 1.0, 1.0 / height_scale);
	
	return transform_to_screen(vertex_position);
}
#endif
#ifdef PIXEL
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
	//offset
	uv = offset_terrain_read_uv(uv, v_pos);
	
	color.rgb = Texel(colour_map, uv).rgb;

	//surface normal
	vec3 normal = normalize(v_normal);

	//multiply light
	color.rgb *= light_amount(normal);

	color.rgb = do_fog(color.rgb);

	return color;
}
#endif
]])

local vegetation_mesh_shader = love.graphics.newShader(shader_common_stuff..shader_noise_stuff..shader_3d_stuff..shader_terrain_stuff..[[
extern Image colour_map;
extern Image vegetation_map;

extern float veg_height_scale;
extern float terrain_res;

varying vec3 v_normal;

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

	vec2 root_pos = vertex_position.xy;

	float tree_angle = noise(uv * 256 + vec2(158, 98), 0.0, 1.0) * 10.0 * TAU;

	//sample
	vec4 t = Texel(terrain, uv);

	vec2 luv = t.xy;

	//sample veg map
	vec4 vt = Texel(vegetation_map, luv);

	float veg_allowed = float(vt.a > 0.75);

	float veg_amount = t.z * veg_allowed;

	if(veg_amount <= 0.0) {
		//clip with NaN
		return vec4(1.0 / 0.0);
	}

	//extrude tree
	vertex_position.xy += rotate(VertexEdgeInfo.xy * 0.5 + abs(voff * 0.25), tree_angle) * mix(0.2, 1.0, veg_amount);

	bool is_point = (VertexEdgeInfo.z == 1.0);
	float point = float(is_point);

	vec3 normal = Texel(terrain_grad, uv).rgb;

	//write normal
	v_normal = normalize(
		normal + vec3(0, 0, 0.1) * point
		//(looks better without the extra normal info for now; maybe with better lighting!)
		//+ normalize(vec3(rotate(VertexEdgeInfo.xy, tree_angle), 1.0 + VertexEdgeInfo.z)) * 0.5
	);

	//write vert colour
	
	//pick native colour
	VaryingColor.rgb = vt.rgb + hash3(uv * 1000.0) * -0.05;
	
	//mix with underlying colour
	vec2 cuv = offset_terrain_read_uv(luv, root_pos);
	VaryingColor = mix(
		Texel(colour_map, cuv),
		VaryingColor,
		veg_amount * mix(0.3, 0.7, point)
	);

	float h = 
		height(luv)
		+ mix(-0.05, 1.0, point) * veg_height_scale * mix(1.0, veg_amount, point);

	//forward to frag for grad map lookup
	VaryingTexCoord.xy = luv;

	//project height
	vertex_position.z = h;
	
	return transform_to_screen(vertex_position);
}
#endif
#ifdef PIXEL
vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
	//apply lighting
	color.rgb *= light_amount(normalize(v_normal));

	color.rgb = do_fog(color.rgb);

	return color;
}
#endif
]])

local sea_mesh_shader = love.graphics.newShader(shader_common_stuff..shader_noise_stuff..shader_3d_stuff..shader_terrain_stuff..[[
extern float sea_level;
float sea_grad_depth = 0.5;
float sea_foam_ratio = 0.5;

extern Image sea_colour_map;
extern Image foam_colour_map;

extern Image water_map;

extern float foam_t;
extern float terrain_res;

#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position) {
	//extrude edge verts
	bool is_edge = max(abs(VertexEdgeInfo.x), abs(VertexEdgeInfo.y)) > 0.0;
	if(is_edge) {
		//special bs edge vert
		vertex_position.x = mix(vertex_position.x, edge_project_distance, VertexEdgeInfo.x);
		vertex_position.y = mix(vertex_position.y, edge_project_distance, VertexEdgeInfo.y);
		VaryingTexCoord.xy = vec2(0.0);
	} else {
		//normal water vert
		vec2 uv = VaryingTexCoord.xy;
		vec4 t = Texel(terrain, uv);

		vec2 luv = t.xy;

		//forward to frag for grad map lookup
		VaryingTexCoord.xy = luv;

		float h = height(uv);

		//project height
		vertex_position.z += sea_level;

		//pull up to ground water level
		//todo: figure out how to make this not cause huge issues on biome transition!
		float ground_water = Texel(water_map, luv).r;
		if (ground_water > 0.0) {
			vertex_position.z = max(
				vertex_position.z,
				h + 0.01 * (ground_water - 0.5)
			);
		}
	}
	
	return transform_to_screen(vertex_position);
}
#endif
#ifdef PIXEL
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
	float h = height(uv);

	float grad_amount = clamp(
		(h - (sea_level - sea_grad_depth)) / sea_grad_depth,
		0.0, 1.0
	);
	
	//base sea colour	
	color = Texel(sea_colour_map, vec2(grad_amount, 0.0));

	//animated foam
	if(grad_amount > sea_foam_ratio && grad_amount < 1.0) {
		float foam_fac = (grad_amount - sea_foam_ratio) / (1.0 - sea_foam_ratio);
		vec2 fuv = vec2(
			foam_fac - foam_t + noise(uv * terrain_res, 0.0, 1.0) * 0.05,
			0.0
		);
		vec4 foam = Texel(foam_colour_map, fuv);
		foam.a *= foam_fac;
		color.rgb = mix(color.rgb, foam.rgb, foam.a);
		color.a = max(color.a, foam.a);
	}

	//todo: multiply light
	//color.rgb *= light_amount(normal);

	color.rgb = do_fog(color.rgb);

	return color;
}
#endif
]])


return {
	world = world_shader,
	gradient = gradient_shader,
	terrain_mesh = terrain_mesh_shader,
	vegetation_mesh = vegetation_mesh_shader,
	sea_mesh = sea_mesh_shader,
}