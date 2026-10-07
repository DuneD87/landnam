class_name DamageInfo
extends RefCounted

## Un golpe que llega a un Hurtbox: cuánto hace, quién lo da, dónde y hacia dónde empuja.
## Lo crea quien golpea (hoja, zarpa, flecha) y lo consume el HealthComponent del que lo recibe.

var amount: float = 0.0
## Desgaste de la guardia: al romperla, el que recibe se tambalea.
var poise: float = 0.0
## Quien da el golpe (el cuerpo, no el arma): la IA lo toma como objetivo al recibirlo.
var source: Node3D = null
## Punto de contacto en mundo.
var point: Vector3 = Vector3.ZERO
## Dirección del golpe en mundo (hacia donde empuja), normalizada.
var direction: Vector3 = Vector3.ZERO
## Metros que desplaza al que lo recibe si le hace tambalearse.
var knockback: float = 0.0
var kind: ItemData.DamageKind = ItemData.DamageKind.SLASH
## Multiplicador que añade la parte golpeada (cabeza) — lo rellena el Hurtbox.
var part_multiplier: float = 1.0
## Viene de lejos (flecha, piedra, lanza arrojada): solo lo para un escudo, y no se puede hacer
## una parada contra él.
var ranged: bool = false
## Se puede parar en seco (Guard.parry_window). Una embestida o un salto de fiera, no.
var parryable: bool = true
## Lo que hizo con él la guardia del que lo recibe (Guard.Result): el daño y el desgaste ya vienen
## rebajados, y quien reacciona al golpe (sangre, tajos, tambaleo) lo tiene en cuenta.
var guarded: int = 0


static func create(amount_: float, source_: Node3D, point_: Vector3, direction_: Vector3,
		poise_: float = 0.0) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount_
	info.source = source_
	info.point = point_
	info.direction = direction_.normalized() if direction_.length_squared() > 1e-8 else Vector3.ZERO
	info.poise = poise_
	return info
