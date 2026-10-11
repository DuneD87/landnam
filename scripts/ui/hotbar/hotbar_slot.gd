class_name HotbarSlot
extends ItemSlotView

## Hueco de la barra rápida: lo que se saca con su tecla (que lleva en la esquina). No guarda
## cantidad: apunta a un ItemData del inventario. Elegido (lo que va en la mano) se ilumina en
## bronce; lo que lleva la otra mano (el escudo), en escarcha.

@export var slot_index: int = 0

var assigned_data: ItemData = null


func _init() -> void:
	super()
	size_kind = &"hotbar"


func _ready() -> void:
	set_mark(str((slot_index + 1) % 10))


func assign(item_data: ItemData) -> void:
	assigned_data = item_data
	if assigned_data:
		show_item(assigned_data.icon)
	else:
		clear()


## Vuelve a leer el icono del item. Los de bloque se renderizan en el arranque y pueden llegar
## después de que el hueco se haya rellenado (restaurar una partida), y assign() solo copia.
func refresh_icon() -> void:
	if assigned_data:
		show_item(assigned_data.icon)


func clear() -> void:
	assigned_data = null
	show_empty()
