extends RefCounted
## Analytic CPU surface/velocity matching ocean_spectrum.gdshaderinc.
const LENGTHS := [1.0,0.86,1.19,0.67,0.45,0.38,0.31,0.24,0.17,0.135,0.105,0.078]
const HEIGHTS := [0.72,0.42,0.32,0.28,0.24,0.19,0.15,0.12,0.09,0.065,0.045,0.03]
const CHOP := [0.42,0.18,0.10,0.07,0.05,0.04,0.035,0.03,0.025,0.02,0.015,0.015]
const ANGLES := [0.0,-0.27,0.33,-0.51,0.62,-0.73,0.91,-1.04,1.17,-1.31,1.43,-1.57]
static var _key: Array = []
static var _modes: Array[Dictionary] = []

static func evaluate(p: Vector3, wind: Vector3, time: float, amplitude: float, steepness: float,
		base_length: float, speed: float, spread: float, ocean_weight: float, depth: float,
		shore_length: float, shore_chop: float, flow_depth: float) -> Dictionary:
	var key := [wind,base_length,speed,spread]
	if key != _key:
		_key=key
		_modes.clear()
		var side := wind.cross(Vector3.UP if absf(wind.y)<0.9 else Vector3.RIGHT).normalized()
		var vertical := wind.cross(side)
		for i in 12:
			var angle: float=ANGLES[i]*spread
			var dir := (wind*cos(angle)+side*sin(angle)+vertical*sin(float(i)*2.399)*0.28).normalized()
			var wavelength := maxf(base_length*LENGTHS[i],1.0)
			var k := TAU/wavelength
			_modes.append({"dir":dir,"length":wavelength,"k":k,"omega":speed*sqrt(9.81*k)})
	var lateral := Vector3.ZERO
	var height := 0.0
	var slope := Vector3.ZERO
	var jx := Vector3.ZERO
	var jy := Vector3.ZERO
	var jz := Vector3.ZERO
	var velocity := Vector3.ZERO
	var radial := p.normalized()
	var h2 := 0.22*clampf(steepness,0.0,0.95)
	var h3 := 0.055*steepness*steepness
	for i in 12:
		var mode: Dictionary=_modes[i]
		var dir: Vector3=mode.dir
		var k: float=mode.k
		var omega: float=mode.omega
		var chop := (1.0-smoothstep(shore_length*0.25,shore_length*0.75,mode.length))*clampf(depth*0.4/maxf(amplitude,0.01),0.0,1.0)*shore_chop
		var gate := maxf(ocean_weight,chop)
		var a: float=amplitude*HEIGHTS[i]
		var horizontal := minf(a*4.0,CHOP[i]/(1.1*k))*clampf(steepness,0.0,0.95)*gate
		var phase: float=k*p.dot(dir)+time*omega+float(i)*2.39996323
		var s := sin(phase)
		var c := cos(phase)
		var profile := s+h2*(2.0*s*s-1.0)+h3*(4.0*s*s*s-3.0*s)
		var derivative := c*(1.0+4.0*h2*s+h3*(12.0*s*s-3.0))
		height+=a*gate*profile
		slope+=dir*(a*gate*k*derivative)
		lateral+=dir*(horizontal*c)
		var dj := dir*(-horizontal*k*s)
		jx+=dir*dj.x
		jy+=dir*dj.y
		jz+=dir*dj.z
		var tangent_dir := dir-radial*dir.dot(radial)
		var attenuation := exp(-k*flow_depth) if flow_depth>0.01 else 1.0
		velocity+=(-tangent_dir*horizontal*s+radial*a*gate*derivative)*omega*attenuation
	return {"lateral":lateral,"height":height,"slope":slope,"jacobian":Basis(jx,jy,jz),"velocity":velocity}

static func tangent(t: Vector3, radial: Vector3, radius: float, field: Dictionary) -> Vector3:
	var dv: Vector3=field.jacobian*t
	return t*(1.0+(field.height-radial.dot(field.lateral))/radius)+dv-radial*radial.dot(dv) \
		+radial*(field.slope.dot(t)-field.lateral.dot(t)/radius)
