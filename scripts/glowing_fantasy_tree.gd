extends Node3D

const TREE_LOD_BIAS := 0.35


func _ready() -> void:
	_apply_lod_bias(self)


func _apply_lod_bias(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).lod_bias = TREE_LOD_BIAS
	for child in node.get_children():
		_apply_lod_bias(child)
