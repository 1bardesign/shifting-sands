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

const float diminish_octave_scale = 0.5;
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
float fracnoise(vec2 p, float t, int distortions, int octaves) {
	float n = 0.0;

	for(int i = 0; i < octaves; i++) {
		float f = pow(0.5, float(i + 1));
		n += f * distorted_noise(
			p * 0.1 * float(i + 1) + vec2(69.5, 13.3) * i,
			distortions,
			1.0, 1.0,
			rotate(vec2(127.1, 311.7),  t * TAU + float(i)),
			rotate(vec2(269.5, 183.3), -t * TAU + float(i))
		);
	}

	return n;
}

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
	vec2 pos = screen_coords * 0.25 * detail_scale;

	float n = fracnoise(pos, t, 1, 8);

	float dmid = length(texture_coords - vec2(0.5));

	n = n + 1.0;
	n -= dmid * 2.5;

	float biome = 0.5 + distorted_noise(
		pos * 0.071 + vec2(874.3, 57.1),
		3,
		1.0, 1.0,
		rotate(vec2(127.1, 311.7), (t * 0.2) * TAU + 25.0),
		rotate(vec2(269.5, 183.3), -(t * 0.2) * TAU)
	) * 0.5;

	float vegetation = float(distorted_noise(
		pos * 0.43 + vec2(77.3, 99.7),
		3,
		1.0, 1.0,
		rotate(vec2(127.1, 311.7), (t * 0.3) * TAU + 25.0),
		rotate(vec2(269.5, 183.3), -(t * 0.3) * TAU)
	) > 0.0 && n > 0.25 && n < 0.75);

	float alpha = 0.01;

	return vec4(
		n,
		biome,
		vegetation,
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

const bool ortho = false;

vec2 rotate(vec2 v, float t) {
	float s = sin(t);
	float c = cos(t);
	return vec2(
		v.x * c + v.y * -s,
		v.x * s + v.y * c
	);
}

vec3 rotate_euler(vec3 v, vec3 e) {
	v.xy = rotate(v.xy, e.x);
	v.xz = rotate(v.xz, e.y);
	v.yz = rotate(v.yz, e.z);
	return v;
}

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
		v = proj(love_ScreenSize.xy, 1.0, 0.1, 1000.0) * v;
	}
	return v;
}

float height(vec2 uv) {
	return Texel(height_map, uv).r;
}

float height_at(vec2 uv) {
	return height(Texel(terrain, uv).xy);
}

#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position) {
	vec2 uv = VaryingTexCoord.xy;
	vec4 t = Texel(terrain, uv);

	vec2 luv = t.xy;

	float h = height(luv);

	//apply noise offset
	luv.x += t.z * 0.1;

	VaryingTexCoord.xy = luv;

	//project height
	vertex_position.z = h * height_scale;
	
	return transform_to_screen(vertex_position);
}
#endif
#ifdef PIXEL
vec3 light_dir = vec3(0.0, 0.0, 1.0);
vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
	color.rgb = Texel(gradient_map, texture_coords).rgb;

	return color;
}
#endif
]])

return {
	world = world_shader,
	mesh = mesh_shader,
}