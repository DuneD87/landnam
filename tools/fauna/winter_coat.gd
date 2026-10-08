extends SceneTree

## Pelaje de invierno a partir de la textura de un animal del pack (liebre ártica a partir del
## conejo, zorro ártico a partir del zorro): el pelo pasa a blanco y conserva su detalle (la luz de
## cada pelo), y lo que no es pelo se queda como estaba: los ojos y lo muy oscuro (nariz, uñas) y lo
## rosado (dentro de las orejas, boca y lengua).
##   godot --headless --path . --script res://tools/fauna/winter_coat.gd -- \
##       --source=res://models/animals/rabbit/rabbit_body.png --out=res://models/animals/rabbit/arctic_hare_body.png
## [--white=0.80] blanco de la parte más oscura del pelo; la más clara llega a 1.
## [--keep_dark=0.12] por debajo de esta luminancia no se toca (ojos, nariz).

const COOL := Color(0.97, 0.985, 1.0)


func _initialize() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	if not args.has("source") or not args.has("out"):
		push_error("Faltan --source y --out")
		quit(1)
		return
	var white := float(args.get("white", "0.80"))
	var keep_dark := float(args.get("keep_dark", "0.12"))
	var image := Image.load_from_file(ProjectSettings.globalize_path(args.source))
	if image == null:
		push_error("No se puede leer %s" % args.source)
		quit(1)
		return
	image.convert(Image.FORMAT_RGBA8)
	var size := image.get_size()
	for y in size.y:
		for x in size.x:
			var c := image.get_pixel(x, y)
			var lum := c.get_luminance()
			# Pelo: lo que no es muy oscuro ni rosado. Lo rosado tira a rojo sobre verde mucho más
			# que el pardo del pelo.
			var fur := smoothstep(keep_dark, keep_dark + 0.1, lum) * (1.0 - smoothstep(0.1, 0.18, c.r - c.g))
			if fur <= 0.0:
				continue
			var shade := white + (1.0 - white) * clampf((lum - keep_dark) / 0.6, 0.0, 1.0)
			var snow := Color(shade * COOL.r, shade * COOL.g, shade * COOL.b, c.a)
			image.set_pixel(x, y, c.lerp(snow, fur))
	var err := image.save_png(ProjectSettings.globalize_path(args.out))
	print("%s → %s (%s)" % [args.source, args.out, error_string(err)])
	quit(0 if err == OK else 1)
