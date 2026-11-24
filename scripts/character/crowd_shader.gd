class_name CrowdShader

## Turns any material of a human (the skin, the hair, a fur, a StandardMaterial3D) into one that
## poses its mesh from a texture of bone matrices instead of a skeleton: the same shader with a
## skinning step written in front of its vertex(), so the far crowd looks like the real thing.
##
## The mesh carries, per vertex, up to four bones (CUSTOM0, bytes) and their weights (CUSTOM1,
## bytes), and its instance (a MultiMesh's INSTANCE_CUSTOM) the clip it plays (CrowdClips.params).
## The texture holds a 3x4 matrix per bone and row, three texels each (HumanMerge).

const TIME := &"crowd_time"
const BONES := &"crowd_bones"

const DECLARATIONS := """
uniform sampler2D crowd_bones : filter_nearest, repeat_disable;
global uniform float crowd_time;

mat4 crowd_bone(int bone, int row) {
	return transpose(mat4(texelFetch(crowd_bones, ivec2(bone * 3, row), 0),
		texelFetch(crowd_bones, ivec2(bone * 3 + 1, row), 0),
		texelFetch(crowd_bones, ivec2(bone * 3 + 2, row), 0), vec4(0.0, 0.0, 0.0, 1.0)));
}

mat4 crowd_pose(vec4 bones, vec4 weights, vec4 clip) {
	float rows = max(abs(clip.y), 1.0);
	float at = max(crowd_time - clip.z, 0.0) * clip.w;
	at = clip.y > 0.0 ? mod(at, rows) : min(at, rows - 1.0);
	float first = floor(at);
	float second = clip.y > 0.0 ? mod(first + 1.0, rows) : min(first + 1.0, rows - 1.0);
	float blend = at - first;
	int row_a = int(clip.x + first + 0.5);
	int row_b = int(clip.x + second + 0.5);
	ivec4 index = ivec4(bones * 255.0 + 0.5);
	mat4 pose = mat4(0.0);
	float total = 0.0;
	for (int i = 0; i < 4; i++) {
		if (weights[i] > 0.0) {
			pose = pose + (crowd_bone(index[i], row_a) * (1.0 - blend) + crowd_bone(index[i], row_b) * blend) * weights[i];
			total += weights[i];
		}
	}
	return total > 0.0 ? pose * (1.0 / total) : mat4(1.0);
}
"""
const CALL := """
	{
		mat4 crowd_m = crowd_pose(CUSTOM0, CUSTOM1, INSTANCE_CUSTOM);
		VERTEX = (crowd_m * vec4(VERTEX, 1.0)).xyz;
		NORMAL = normalize(mat3(crowd_m) * NORMAL);
		TANGENT = normalize(mat3(crowd_m) * TANGENT);
		BINORMAL = normalize(mat3(crowd_m) * BINORMAL);
	}
"""

## A built-in material, as far as it shows from afar: %s the render modes, %s the alpha lines.
const STANDARD := """shader_type spatial;
%s
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool vertex_color = false;
uniform bool vertex_color_srgb = false;
uniform float roughness = 1.0;
uniform sampler2D texture_roughness : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 roughness_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float metallic = 0.0;
uniform sampler2D texture_metallic : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 metallic_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform bool normal_map = false;
uniform sampler2D texture_normal : hint_roughness_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale = 1.0;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);

void vertex() {
	UV = UV * uv_scale.xy + uv_offset.xy;
}

void fragment() {
	vec4 color = albedo * texture(texture_albedo, UV);
	if (vertex_color) {
		vec3 tint = COLOR.rgb;
		if (vertex_color_srgb) {
			tint = mix(pow((tint + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), tint * (1.0 / 12.92), lessThan(tint, vec3(0.04045)));
		}
		color.rgb *= tint;
	}
	ALBEDO = color.rgb;
	ROUGHNESS = roughness * dot(texture(texture_roughness, UV), roughness_channel);
	METALLIC = metallic * dot(texture(texture_metallic, UV), metallic_channel);
	if (normal_map) {
		NORMAL_MAP = texture(texture_normal, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	%s
}
"""

## Source code (hash) -> the shader with the skinning step.
static var _shaders := {}
static var _registered := false


## The global the shaders read; before any of them compiles (GameManager).
static func register_globals() -> void:
	if _registered:
		return
	_registered = true
	if not ProjectSettings.has_setting("shader_globals/" + String(TIME)):
		RenderingServer.global_shader_parameter_add(TIME, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)


## Moves the crowd's clock on (once per frame, by whoever owns the crowd).
static func tick(delta: float) -> void:
	CrowdClips.time += delta
	RenderingServer.global_shader_parameter_set(TIME, CrowdClips.time)


## `source` posed by `bones` (the body's texture). A ShaderMaterial keeps its shader, with the step
## in front; a built-in material (whose shader a script cannot read) becomes STANDARD with what
## shows from afar: colour, vertex colour, roughness, metallic, normal map, UV scale, cull mode and
## transparency. Null if its shader cannot take the step.
static func material(source: Material, bones: Texture2D) -> ShaderMaterial:
	if source == null:
		return null
	var result := ShaderMaterial.new()
	result.render_priority = source.render_priority
	var from_shader := source as ShaderMaterial
	var built_in := source as BaseMaterial3D
	if from_shader != null and from_shader.shader != null:
		result.shader = _derived(from_shader.shader.code)
		for uniform: Dictionary in from_shader.shader.get_shader_uniform_list():
			result.set_shader_parameter(uniform.name, from_shader.get_shader_parameter(uniform.name))
	elif built_in != null:
		var modes := PackedStringArray()
		match built_in.cull_mode:
			BaseMaterial3D.CULL_DISABLED:
				modes.append("cull_disabled")
			BaseMaterial3D.CULL_FRONT:
				modes.append("cull_front")
		var alpha := ""
		match built_in.transparency:
			BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				alpha = "ALPHA = color.a; ALPHA_SCISSOR_THRESHOLD = %f;" % built_in.alpha_scissor_threshold
			BaseMaterial3D.TRANSPARENCY_ALPHA_HASH:
				alpha = "ALPHA = color.a; ALPHA_HASH_SCALE = %f;" % built_in.alpha_hash_scale
			BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
				alpha = "ALPHA = color.a;"
		result.shader = _derived(STANDARD % [("render_mode " + ", ".join(modes) + ";") if not modes.is_empty() else "", alpha])
		result.set_shader_parameter(&"albedo", built_in.albedo_color)
		result.set_shader_parameter(&"texture_albedo", built_in.albedo_texture)
		result.set_shader_parameter(&"vertex_color", built_in.vertex_color_use_as_albedo)
		result.set_shader_parameter(&"vertex_color_srgb", built_in.vertex_color_is_srgb)
		result.set_shader_parameter(&"roughness", built_in.roughness)
		result.set_shader_parameter(&"texture_roughness", built_in.roughness_texture)
		result.set_shader_parameter(&"roughness_channel", _channel(built_in.roughness_texture_channel))
		result.set_shader_parameter(&"metallic", built_in.metallic)
		result.set_shader_parameter(&"texture_metallic", built_in.metallic_texture)
		result.set_shader_parameter(&"metallic_channel", _channel(built_in.metallic_texture_channel))
		result.set_shader_parameter(&"normal_map", built_in.normal_enabled and built_in.normal_texture != null)
		result.set_shader_parameter(&"texture_normal", built_in.normal_texture)
		result.set_shader_parameter(&"normal_scale", built_in.normal_scale)
		result.set_shader_parameter(&"uv_scale", built_in.uv1_scale)
		result.set_shader_parameter(&"uv_offset", built_in.uv1_offset)
	if result.shader == null:
		return null
	result.set_shader_parameter(BONES, bones)
	return result


static func _channel(channel: BaseMaterial3D.TextureChannel) -> Vector4:
	match channel:
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			return Vector4(0.0, 1.0, 0.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			return Vector4(0.0, 0.0, 1.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			return Vector4(0.0, 0.0, 0.0, 1.0)
		BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE:
			return Vector4(0.3333, 0.3333, 0.3333, 0.0)
	return Vector4(1.0, 0.0, 0.0, 0.0)


static func _derived(code: String) -> Shader:
	var key := code.hash()
	if _shaders.has(key):
		return _shaders[key]
	var shader: Shader = null
	# In world space the step would pose the vertex after its instance moved it.
	if not code.contains("world_vertex_coords") and not code.contains("skip_vertex_transform"):
		var entry := RegEx.create_from_string("void\\s+vertex\\s*\\(\\s*\\)\\s*\\{").search(code)
		var text := ""
		if entry != null:
			text = code.substr(0, entry.get_start()) + DECLARATIONS + entry.get_string() + CALL + code.substr(entry.get_end())
		else:
			text = code + DECLARATIONS + "\nvoid vertex() {" + CALL + "}\n"
		shader = Shader.new()
		shader.code = text
	_shaders[key] = shader
	return shader
