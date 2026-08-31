@tool
extends EditorPlugin

var export_plugin: AndroidExportPlugin


func _enter_tree() -> void:
	export_plugin = AndroidExportPlugin.new()
	add_export_plugin(export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(export_plugin)
	export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	var _plugin_name := "OpenStrikeLocation"

	func _supports_platform(platform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform, debug: bool) -> PackedStringArray:
		var build := "debug" if debug else "release"
		return PackedStringArray([
			_plugin_name + "/bin/" + build + "/" + _plugin_name + "-" + build + ".aar"
		])

	func _get_name() -> String:
		return _plugin_name
