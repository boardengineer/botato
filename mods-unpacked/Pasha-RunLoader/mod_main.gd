extends Node

# RunLoader installs no script extensions: one watcher node polls for the
# title screen and attaches its panel there, so it can never break the game's
# own code paths. Everything lives in run_loader.gd.

func _ready():
	var script = load(ModLoaderMod.get_unpacked_dir() + "Pasha-RunLoader/run_loader.gd")
	var loader = Node.new()
	loader.name = "RunLoader"
	loader.set_script(script)
	get_tree().root.call_deferred("add_child", loader)
