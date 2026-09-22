class_name CreationStep
extends Control

## One page of the new-character flow hosted by CharacterCreationScreen. A
## step edits its part of `character` and may drive the shared `preview`; the
## screen handles the header, Back/Next, and asks can_continue() before
## leaving. Emit validity_changed whenever can_continue() may have changed.

signal validity_changed

var character: CharacterData
var preview: CharacterPreview
## Size factor of the UI (1 at 1440 px of height).
var ui_scale := 1.0


## Name shown in the step list of the header.
func get_title() -> String:
	return ""


func enter() -> void:
	pass


func leave() -> void:
	pass


func can_continue() -> bool:
	return true


## Why the player cannot continue yet, shown next to the Next button.
func blocking_reason() -> String:
	return ""


func px(value: float) -> float:
	return value * ui_scale
