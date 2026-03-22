## GameManager - Autoload Singleton
## Pure state machine. Emits signals, lets each system react.
##
## Setup: Project > Project Settings > Autoload > Add as "GameManager"

extends Node

signal state_changed(new_state: State)

enum State {
	MENU,
	CINEMATIC,
	PLAYING,
}

var current_state: State = State.MENU
var player: CharacterBody3D


func register_player(p: CharacterBody3D) -> void:
	player = p


func start_game() -> void:
	if current_state != State.MENU:
		return
	_change_state(State.CINEMATIC)


## Called by the player when the cinematic tween finishes
func cinematic_completed() -> void:
	if current_state != State.CINEMATIC:
		return
	_change_state(State.PLAYING)


func _change_state(new_state: State) -> void:
	current_state = new_state
	state_changed.emit(new_state)
