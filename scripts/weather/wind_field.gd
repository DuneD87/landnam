class_name WindField
extends RefCounted

## Viento hacia donde viaja el aire, en m/s. La proyección tangente evita empuje radial
## y se desvanece suavemente en los dos puntos donde la dirección es vertical.
static func velocity(direction: Vector3, speed: float, weather: float, up: Vector3) -> Vector3:
	if direction.is_zero_approx() or up.is_zero_approx():
		return Vector3.ZERO
	return direction.normalized().slide(up.normalized()) * maxf(speed, 0.0) * maxf(weather, 0.0)
