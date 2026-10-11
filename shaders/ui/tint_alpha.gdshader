// Pinta una textura de un solo color conservando su transparencia: las siluetas negras de los
// huecos vacíos salen en bronce tenue, como grabadas (ItemSlotView).
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.79, 0.64, 0.42, 0.22);

void fragment() {
	COLOR = vec4(tint.rgb, texture(TEXTURE, UV).a * tint.a);
}
