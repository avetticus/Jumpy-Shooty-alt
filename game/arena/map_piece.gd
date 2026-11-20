@tool
class_name MapPiece
extends Node3D
## A piece of a map worked out from a few numbers: stairs or a ramp, a row or a ring of
## blocks (MapStairs, MapRow, MapRing). Change a number in the inspector, or drag one
## of its handles in the 3D view (addons/map_tools/piece_gizmo.gd), and
## its blocks are made again.
##
## The blocks it makes are ordinary MapBlock nodes saved in the scene, so in the game
## a piece is just a group: nothing here runs outside the editor. They are marked
## (the meta GENERATED) so the piece knows which children are its own to replace; do
## not edit them by hand, they are thrown away the next time a number changes. To
## edit them, press Bake in the inspector: the piece becomes a plain group.

const GENERATED := &"map_piece_generated"
const GROUP := &"map_pieces"

var _live := false   # numbers set while the scene loads must not rebuild it


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	_live = true
	add_to_group(GROUP)
	if generated().is_empty():
		set_meta("_edit_group_", true)   # a click in the 3D view picks the whole piece
		rebuild.call_deferred()
	else:
		_made()   # loaded with its blocks: they are up to date


## One of its numbers changed (the setters call this).
func _changed() -> void:
	if _live and is_inside_tree():
		rebuild()
		update_configuration_warnings()


## The children it made.
func generated() -> Array[Node]:
	var out: Array[Node] = []
	for c in get_children():
		if c.has_meta(GENERATED):
			out.append(c)
	return out


## Throws its blocks away and makes them again from its numbers.
func rebuild() -> void:
	for c in generated():
		remove_child(c)
		if Engine.is_editor_hint():
			c.queue_free()   # the editor may still be showing it
		else:
			c.free()
	var keeper := owner
	if keeper == null and is_inside_tree() and Engine.is_editor_hint() and get_tree().edited_scene_root == self:
		keeper = self
	for n in _make():
		n.set_meta(GENERATED, true)
		add_child(n, true)
		if keeper:
			adopt(n, keeper)
	_made()
	if Engine.is_editor_hint():
		update_gizmos()   # its handles sit where its numbers put them


## The nodes this piece is made of, not yet in the scene. Each kind of piece says.
func _make() -> Array[Node3D]:
	return []


## After a rebuild (a row notes what it copied).
func _made() -> void:
	pass


## A new block for _make().
func _block(block_name: String, block_kind: String, size: Vector3, at: Vector3, shape := MapBlock.Shape.BOX) -> MapBlock:
	var b := MapBlock.new()
	b.name = block_name
	b.shape = shape
	b.kind = block_kind
	b.size = size
	b.position = at
	return b


## The child a row or a ring repeats: the first one it did not make itself.
func template() -> Node3D:
	for c in get_children():
		if c is Node3D and not c.has_meta(GENERATED):
			return c
	return null


## A number that changes when anything saved about `node` or what is under it does.
static func signature(node: Node) -> int:
	if node == null:
		return 0
	var parts := [node.get_class(), node.name]
	for p in node.get_property_list():
		if p.usage & PROPERTY_USAGE_STORAGE and p.name != "script":
			parts.append(node.get(p.name))
	for c in node.get_children():
		parts.append(signature(c))
	return hash(parts)


## A copy of `node` and what is under it, without the helpers the editor adds (a
## block's preview mesh), which the copy makes for itself.
static func copy(node: Node) -> Node:
	var dup := node.duplicate()
	_strip(dup)
	return dup


static func _strip(node: Node) -> void:
	var real := node.get_children()
	for c in node.get_children(true):
		if c not in real:
			node.remove_child(c)
			c.free()
	for c in real:
		_strip(c)


## Makes `keeper` the owner of `node` and everything under it, so it is saved with
## the scene. `node` must already be in the scene under `keeper`. What is inside a
## scene placed in it (a linked prefab) stays that scene's: only its root is adopted,
## so the map saves a link to the file, not copies of what is in it.
static func adopt(node: Node, keeper: Node) -> void:
	node.owner = keeper
	if node != keeper and not node.scene_file_path.is_empty():
		return
	for c in node.get_children():
		adopt(c, keeper)
