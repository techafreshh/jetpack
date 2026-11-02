class_name Pilot
extends Node
## Base driver for soldier combat: each physics tick the soldier pulls one
## Command and consumes it. HumanPilot is the sole raw-input reader;
## scripted drivers subclass this and return their own Commands.

class Command extends RefCounted:
	var move_x := 0.0
	var fly := false
	var crouch := false
	var aim_point := Vector2.ZERO
	var fire := false
	var grenade := false
	var switch_to := -1
	var reload := false


func get_command(_delta: float) -> Pilot.Command:
	return Pilot.Command.new()
