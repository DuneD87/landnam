extends RefCounted
## Analytic CPU surface/velocity matching ocean_spectrum.gdshaderinc.
const LENGTHS := [1.0,0.86,1.19,0.67,0.45,0.38,0.31,0.24,0.17,0.135,0.105,0.078]
const HEIGHTS := [0.72,0.42,0.32,0.28,0.24,0.19,0.15,0.12,0.09,0.065,0.045,0.03]
const CHOP := [0.42,0.18,0.10,0.07,0.05,0.04,0.035,0.03,0.025,0.02,0.015,0.015]
const ANGLES := [0.0,-0.27,0.33,-0.51,0.62,-0.73,0.91,-1.04,1.17,-1.31,1.43,-1.57]
static var _key_wind := Vector3.ZERO
static var _key_length := -1.0
static var _key_speed := -1.0
static var _key_spread := -1.0
static var _mode_dir := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO,
	Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
static var _mode_length := PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
static var _mode_k := PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
static var _mode_omega := PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])

static func evaluate(p: Vector3, wind: Vector3, time: float, amplitude: float, steepness: float,
		base_length: float, speed: float, spread: float, ocean_weight: float, depth: float,
		shore_length: float, shore_chop: float, flow_depth: float, min_length: float = 0.0,
		phase_shift := Vector3.ZERO, inland: float = 0.0, inland_scale: float = 1.0,
		swell_length := Vector2.ZERO) -> Dictionary:
	# La clave va en variables sueltas: montar un Array por consulta para compararlo costaba más
	# que varias de las ondas que suma.
	if wind != _key_wind or base_length != _key_length or speed != _key_speed or spread != _key_spread:
		_key_wind = wind
		_key_length = base_length
		_key_speed = speed
		_key_spread = spread
		var side := wind.cross(Vector3.UP if absf(wind.y)<0.9 else Vector3.RIGHT).normalized()
		var vertical := wind.cross(side)
		for i in 12:
			var angle: float=ANGLES[i]*spread
			var wavelength := maxf(base_length*LENGTHS[i],1.0)
			var mode_k := TAU/wavelength
			_mode_dir[i] = (wind*cos(angle)+side*sin(angle)+vertical*sin(float(i)*2.399)*0.28).normalized()
			_mode_length[i] = wavelength
			_mode_k[i] = mode_k
			_mode_omega[i] = speed*sqrt(9.81*mode_k)
	var lateral := Vector3.ZERO
	var height := 0.0
	var slope := Vector3.ZERO
	var jx := Vector3.ZERO
	var jy := Vector3.ZERO
	var jz := Vector3.ZERO
	var velocity := Vector3.ZERO
	var radial := p.normalized()
	var steep := clampf(steepness,0.0,0.95)
	var h2 := 0.22*steep
	var h3 := 0.055*steepness*steepness
	var chop_scale := clampf(depth*0.4/maxf(amplitude,0.01),0.0,1.0)*shore_chop
	var shifted := p+phase_shift
	var fade_depth := flow_depth>0.01
	for i in 12:
		var length: float=_mode_length[i]
		var gate := ocean_weight
		if chop_scale > 0.0:
			gate = maxf(gate,(1.0-smoothstep(shore_length*0.25,shore_length*0.75,length))*chop_scale)
		# LOD de ocean_mode_gate: las octavas más cortas que min_length se apagan (un témpano no
		# siente olas más pequeñas que él).
		if min_length > 0.0:
			gate *= smoothstep(min_length*0.5,min_length*1.5,length)
		# Una onda apagada no aporta a ninguna suma: todas van multiplicadas por la puerta.
		if gate <= 0.0:
			continue
		# Swell de tierra adentro, como en ocean_mode_gate: las octavas largas bajan, la ola corta no.
		if inland > 0.0:
			gate *= lerpf(1.0,inland_scale,inland*smoothstep(swell_length.x,swell_length.y,length))
		var dir: Vector3=_mode_dir[i]
		var k: float=_mode_k[i]
		var omega: float=_mode_omega[i]
		var a: float=amplitude*HEIGHTS[i]
		var horizontal := minf(a*4.0,CHOP[i]/(1.1*k))*steep*gate
		var phase: float=k*shifted.dot(dir)+time*omega+float(i)*2.39996323
		var s := sin(phase)
		var c := cos(phase)
		var profile := s+h2*(2.0*s*s-1.0)+h3*(4.0*s*s*s-3.0*s)
		var derivative := c*(1.0+4.0*h2*s+h3*(12.0*s*s-3.0))
		var ag := a*gate
		height+=ag*profile
		slope+=dir*(ag*k*derivative)
		lateral+=dir*(horizontal*c)
		var dj := dir*(-horizontal*k*s)
		jx+=dir*dj.x
		jy+=dir*dj.y
		jz+=dir*dj.z
		var tangent_dir := dir-radial*dir.dot(radial)
		var attenuation := exp(-k*flow_depth) if fade_depth else 1.0
		velocity+=(-tangent_dir*horizontal*s+radial*ag*derivative)*omega*attenuation
	return {"lateral":lateral,"height":height,"slope":slope,"jacobian":Basis(jx,jy,jz),"velocity":velocity}

static func tangent(t: Vector3, radial: Vector3, radius: float, field: Dictionary) -> Vector3:
	var dv: Vector3=field.jacobian*t
	return t*(1.0+(field.height-radial.dot(field.lateral))/radius)+dv-radial*radial.dot(dv) \
		+radial*(field.slope.dot(t)-field.lateral.dot(t)/radius)
