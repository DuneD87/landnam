extends Node3D


@export var viewport_size: Vector2i = Vector2i(320, 180)
@export var corner_margin: int = 20
@export var border_color: Color = Color(0.2, 0.2, 0.2, 0.8)
@export var auto_update_position: bool = true

var depth_viewport: SubViewport
var depth_quad: MeshInstance3D
var depth_camera: Camera3D
var display_container: Control
var depth_texture_rect: TextureRect
var main_camera: Camera3D

func _ready():
	main_camera = get_viewport().get_camera_3d()
	if not main_camera:
		push_error("No se encontró cámara principal")
		return
	
	_create_depth_capture_system()
	
	_create_ui_display()
	
	_setup_depth_shader()

func _create_depth_capture_system():
	depth_viewport = SubViewport.new()
	depth_viewport.size = viewport_size
	depth_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(depth_viewport)
	
	depth_camera = Camera3D.new()
	depth_viewport.add_child(depth_camera)
	
	depth_quad = MeshInstance3D.new()
	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(2, 2)
	depth_quad.mesh = quad_mesh
	depth_quad.extra_cull_margin = 16384
	depth_viewport.add_child(depth_quad)

func _create_ui_display():
	var canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)
	
	display_container = MarginContainer.new()
	display_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	display_container.add_theme_constant_override("margin_top", corner_margin)
	display_container.add_theme_constant_override("margin_right", corner_margin)
	canvas_layer.add_child(display_container)
	
	var panel_container = PanelContainer.new()
	var style_box = StyleBoxFlat.new()
	style_box.set_border_width_all(2)
	style_box.border_color = border_color
	style_box.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	style_box.set_corner_radius_all(5)
	panel_container.add_theme_stylebox_override("panel", style_box)
	display_container.add_child(panel_container)
	
	depth_texture_rect = TextureRect.new()
	depth_texture_rect.custom_minimum_size = Vector2(viewport_size.x, viewport_size.y)
	depth_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	depth_texture_rect.texture = depth_viewport.get_texture()
	panel_container.add_child(depth_texture_rect)
	
	var label = Label.new()
	label.text = "Depth Buffer"
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.9))
	label.position = Vector2(5, 5)
	depth_texture_rect.add_child(label)

func _setup_depth_shader():
	var shader_code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float near_plane = 0.1;
uniform float far_plane = 100.0;
uniform bool visualize_linear = true;
uniform vec3 near_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 far_color : source_color = vec3(0.0, 0.0, 0.2);
uniform float contrast = 1.5;

void vertex() {
	// Posicionar el quad para cubrir toda la pantalla
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

void fragment() {
	// Obtener la profundidad del depth buffer
	float depth = texture(depth_texture, SCREEN_UV).x;
	
	// Convertir a profundidad lineal si está habilitado
	float linear_depth;
	if (visualize_linear) {
		// Convertir de profundidad no lineal a lineal
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0);
		vec4 view_space = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		view_space.xyz /= view_space.w;
		linear_depth = -view_space.z;
		
		// Normalizar entre near y far
		linear_depth = (linear_depth - near_plane) / (far_plane - near_plane);
		linear_depth = clamp(linear_depth, 0.0, 1.0);
	} else {
		linear_depth = depth;
	}
	
	// Aplicar contraste
	linear_depth = pow(linear_depth, contrast);
	
	// Invertir para que los objetos cercanos sean brillantes
	float depth_value = 1.0 - linear_depth;
	
	// Crear gradiente de color
	vec3 color = mix(far_color, near_color, depth_value);
	
	// Añadir un efecto de edge detection sutil
	vec2 texel_size = 1.0 / vec2(textureSize(depth_texture, 0));
	float depth_diff = 0.0;
	depth_diff += abs(depth - texture(depth_texture, SCREEN_UV + vec2(texel_size.x, 0.0)).x);
	depth_diff += abs(depth - texture(depth_texture, SCREEN_UV + vec2(-texel_size.x, 0.0)).x);
	depth_diff += abs(depth - texture(depth_texture, SCREEN_UV + vec2(0.0, texel_size.y)).x);
	depth_diff += abs(depth - texture(depth_texture, SCREEN_UV + vec2(0.0, -texel_size.y)).x);
	
	// Resaltar bordes
	if (depth_diff > 0.01) {
		color *= 0.7;
	}
	
	ALBEDO = color;
	ALPHA = 1.0;
}
"""
	
	var shader = Shader.new()
	shader.code = shader_code
	
	var material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("near_plane", 0.1)
	material.set_shader_parameter("far_plane", 50.0)
	material.set_shader_parameter("visualize_linear", true)
	material.set_shader_parameter("near_color", Vector3(1.0, 1.0, 1.0))
	material.set_shader_parameter("far_color", Vector3(0.0, 0.0, 0.2))
	material.set_shader_parameter("contrast", 1.5)
	
	depth_quad.material_override = material

func _process(_delta):
	if depth_camera and main_camera:
		depth_camera.global_transform = main_camera.global_transform
		depth_camera.fov = main_camera.fov
		depth_camera.near = main_camera.near
		depth_camera.far = main_camera.far

func _notification(what):
	if what == NOTIFICATION_WM_SIZE_CHANGED and auto_update_position:
		if display_container:
			display_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)

func set_viewport_size(size: Vector2i):
	viewport_size = size
	if depth_viewport:
		depth_viewport.size = size
	if depth_texture_rect:
		depth_texture_rect.custom_minimum_size = Vector2(size.x, size.y)

func set_depth_range(near: float, far: float):
	if depth_quad and depth_quad.material_override:
		depth_quad.material_override.set_shader_parameter("near_plane", near)
		depth_quad.material_override.set_shader_parameter("far_plane", far)

func set_depth_colors(near_col: Color, far_col: Color):
	if depth_quad and depth_quad.material_override:
		depth_quad.material_override.set_shader_parameter("near_color", Vector3(near_col.r, near_col.g, near_col.b))
		depth_quad.material_override.set_shader_parameter("far_color", Vector3(far_col.r, far_col.g, far_col.b))

func toggle_visibility():
	if display_container:
		display_container.visible = !display_container.visible
