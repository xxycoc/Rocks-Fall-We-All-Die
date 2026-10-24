class_name Sfx
## Obstacle sounds (P2). Drop a sound into res://audio/ with one of these names
## (.ogg, .wav or .mp3) and the obstacle plays it, positioned in 3D so hikers can
## hear where it comes from. Missing files are skipped silently.
##   boulder_roll     loops while a boulder rolls
##   landslide_siren  the 2 s warning
##   landslide_rumble loops while the wave moves
##   mud_splat        when a mud patch lands
## Remember to add every sound to CREDITS.md.

const DIR := "res://audio/"
const EXTENSIONS: Array[String] = ["ogg", "wav", "mp3"]


## Plays `sound_name` on `player` if the file exists. Returns true if it played.
## `loop` restarts it when it ends, whatever the file's import settings say.
static func play(player: AudioStreamPlayer3D, sound_name: String, loop := false) -> bool:
	if player.stream == null:
		for ext in EXTENSIONS:
			var path := "%s%s.%s" % [DIR, sound_name, ext]
			if ResourceLoader.exists(path):
				player.stream = load(path)
				break
	if player.stream == null:
		return false
	if loop and not player.finished.is_connected(player.play):
		player.finished.connect(player.play)
	player.play()
	return true
