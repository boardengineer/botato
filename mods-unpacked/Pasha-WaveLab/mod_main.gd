extends Node

# WaveLab installs no script extensions: everything is driven by a watcher
# node polling scene state, so it can never break the game's own code paths.

func _ready():
	var script = load(ModLoaderMod.get_unpacked_dir() + "Pasha-WaveLab/wavelab_watcher.gd")
	var watcher = Node.new()
	watcher.name = "WaveLabWatcher"
	watcher.set_script(script)
	get_tree().root.call_deferred("add_child", watcher)
