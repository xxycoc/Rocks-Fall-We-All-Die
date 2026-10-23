extends Node
## GameManager autoload (P1). Replaces P2's stub; signal names follow CONTRACT.md.
## The host is the source of truth. It broadcasts every state change to all peers,
## so these signals fire on every machine, not just the host.

signal hiker_died(id: int)
signal hiker_revived(id: int)
signal hiker_eliminated(id: int)
signal hiker_extracted(id: int)
signal game_over(winner: String)  # "hikers" or "mountain"

const ROUND_TIME := 300.0   # 5 minutes, per CONTRACT.md
const HIKERS_NEEDED := 2

## id -> "alive" | "buried" | "eliminated" | "extracted"
var hiker_states: Dictionary = {}
var round_running := false
var time_left := ROUND_TIME


# ---------- Called by main.gd on the host ----------

func register_hiker(id: int) -> void:
	if not multiplayer.is_server():
		return
	_set_state.rpc(id, "alive")


func unregister_hiker(id: int) -> void:
	if not multiplayer.is_server():
		return
	_remove_state.rpc(id)
	_check_win()


func start_round() -> void:
	if not multiplayer.is_server():
		return
	_round_started.rpc(ROUND_TIME)


# ---------- Called by hikers (from any peer) ----------

## Hikers report their own state changes to the host:
##   GameManager.report_state.rpc_id(1, hiker.name.to_int(), "buried")
@rpc("any_peer", "call_local", "reliable")
func report_state(id: int, state: String) -> void:
	if not multiplayer.is_server():
		return
	if not hiker_states.has(id):
		return
	_set_state.rpc(id, state)
	_check_win()


# ---------- Helpers ----------

func count_state(state: String) -> int:
	var n := 0
	for s in hiker_states.values():
		if s == state:
			n += 1
	return n


func _process(delta: float) -> void:
	if not round_running:
		return
	time_left = max(time_left - delta, 0.0)
	if multiplayer.is_server() and time_left <= 0.0:
		_end_round("mountain")


func _check_win() -> void:
	if not multiplayer.is_server() or not round_running:
		return
	var extracted := count_state("extracted")
	var still_in := count_state("alive") + count_state("buried")
	# With fewer than 2 hikers (solo testing) one escape is enough.
	var needed := mini(HIKERS_NEEDED, hiker_states.size())
	if needed == 0:
		return
	if extracted >= needed:
		_end_round("hikers")
	elif extracted + still_in < needed:
		# Hikers can no longer get enough out (covers 1 escaped + 3 eliminated).
		_end_round("mountain")


func _end_round(winner: String) -> void:
	_game_over.rpc(winner)


# ---------- Broadcasts (host -> everyone) ----------

@rpc("authority", "call_local", "reliable")
func _set_state(id: int, state: String) -> void:
	var old: String = hiker_states.get(id, "")
	hiker_states[id] = state
	match state:
		"buried":
			hiker_died.emit(id)
		"alive":
			if old == "buried":
				hiker_revived.emit(id)
		"eliminated":
			hiker_eliminated.emit(id)
		"extracted":
			hiker_extracted.emit(id)


@rpc("authority", "call_local", "reliable")
func _remove_state(id: int) -> void:
	hiker_states.erase(id)


@rpc("authority", "call_local", "reliable")
func _round_started(duration: float) -> void:
	for id in hiker_states.keys():
		hiker_states[id] = "alive"
	time_left = duration
	round_running = true


@rpc("authority", "call_local", "reliable")
func _game_over(winner: String) -> void:
	round_running = false
	game_over.emit(winner)
