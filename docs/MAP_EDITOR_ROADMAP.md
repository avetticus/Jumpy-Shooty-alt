# Map editor roadmap: MapBlocks to TrenchBroom parity

What it would take for the Godot map tools (`addons/map_tools/`, `MapBlock`) to do
everything a level designer reaches for in TrenchBroom, without leaving Godot and
without changing how maps are stored or played.

Status: **P1 (the hull shape), P2 (the vertex tool) and P3 (edges, faces, push/pull)
are built.** P4 onward are plans.

## Ground rules

- **MapBlock stays the only thing a map is made of.** Maps stay `.tscn` scenes, and
  `MapRoot.build()` stays the one path from blocks to meshes, collision and the
  navigation mesh. No `.map` files, no second source of truth.
- **The 19 existing maps keep working untouched.** Every new feature is additive; an
  old block never changes shape or saved form unless someone edits it.
- **Every tool action is one undo step**, through `apply_edit()` in `plugin.gd`, as
  today.
- **Geometry lives in files with no editor in them** (`map_ops.gd`, `map_commands.gd`,
  `map_mesher.gd`), so `tests/map_tools_test.gd` can drive it headless. Each phase
  below adds tests there.
- **Use what Godot already gives us** rather than rebuilding TrenchBroom's chrome.

## Where we stand

Key: **Have** = already in map_tools. **Godot** = the editor already does it.
**Partial** = some of it. **Build** = in a phase below. **Skip** = not worth it here.

### Views and navigation

| TrenchBroom | Status | Notes |
| --- | --- | --- |
| 3D view + top/front/side 2D views, 1–4 pane layouts | Godot | View menu: 2 or 4 viewports, orthographic per viewport. Draw already works in 2D views |
| Fly camera (WASD), orbit, focus selection | Godot | Freelook (right-drag + WASD), F to focus |
| Grid sizes, `[` `]` | Have | 0.1–4 m |
| Grid drawn on the work plane at the current step | Build (P7) | Godot's grid is fixed; draw ours on the plane under the cursor |
| Textured / flat / wireframe render modes | Godot | Display menu: wireframe, unshaded, overdraw |
| Selected brush edges drawn on top | Build (P7) | Outline overlay for selected blocks |
| Map bounds | Have | Red outline |

### Creating and shaping brushes

| TrenchBroom | Status | Notes |
| --- | --- | --- |
| Draw a brush by dragging (B) | Have | Draw tool, 3D and 2D views |
| Primitives (cylinder, cone, sphere…) | Have | Box, cylinder, tube, cone, wedge, bevel, dome, arch. Better than TB: they stay parametric |
| Resize by dragging a face (extrude) | Have | Face handles, boxes and round shapes |
| Resize a slanted face of any brush | Build (P3) | Needs hulls |
| **Vertex tool** (V): move, multi-select, add, delete | **Build (P2)** | Needs the hull shape (P1) |
| **Edge tool** (E) / **Face tool** (F) | **Build (P3)** | |
| Clip along an axis | Have | Clip tool, boxes / cylinders / tubes |
| **Clip at any angle** (2- and 3-point), keep front/back/both | **Build (P4)** | |
| CSG Hollow | Partial (P5) | Boxes only today |
| **CSG Subtract / Merge (convex) / Intersect** | **Build (P5)** | |
| Snap vertices to grid | Build (P2) | |
| Snap to neighbours | Have | Alt+N, better than TB's |

### Transforming

| TrenchBroom | Status | Notes |
| --- | --- | --- |
| Move, rotate, scale gizmos with snapping | Godot | Snap settings in the 3D toolbar |
| Rotate tool with movable pivot and 15° steps | Partial (P6) | Godot rotates about the selection; add pivot + "turn 90° about X/Y/Z" commands |
| Nudge selection by grid with arrow keys, PgUp/PgDn | Build (P6) | |
| Move / rotate by exact amounts | Godot | Transform dialog (3D view menu) |
| Flip | Have | Mirror, in place or as a copy |
| Shear | Build (P6) | Only meaningful on hulls |
| Duplicate and repeat the last move (Ctrl+D, Ctrl+R) | Build (P6) | Godot duplicates in place; add "repeat last move" |
| Array / radial copies | Have | Better than TB's |

### Selection and organising

| TrenchBroom | Status | Notes |
| --- | --- | --- |
| Groups, open a group to edit inside | Godot | Node3D groups + selection groups (already used by every map) |
| **Linked groups** (copies that update together) | Partial (P6) | Row and Ring pieces do it for repeats; prefabs are copies with no link. Add "place linked" (scene instance) |
| Layers: hide, lock, leave out of the game | Partial (P6) | Hide = left out of the game (have). Add a Layers list in the Map dock for top-level groups |
| Hide / isolate selection | Partial (P6) | Hide is Godot's; add Isolate |
| Lock | Godot | Node lock |
| Select touching / inside / tall | Build (P6) | |
| Select by texture | Have | Right-click a kind in the dock |
| Invert selection | Build (P6) | |

### Texturing ("UV editing")

Blocks have no UVs: colour comes from the palette kind and patterns are drawn in world
space by `map_surface.gdshader`, so they already line up from block to block. Much of
what TrenchBroom's UV tools are used for is therefore automatic here.

| TrenchBroom | Status | Notes |
| --- | --- | --- |
| Texture browser, apply on click | Have | Kinds in the Map dock |
| Per-face texture | Build (P8) | A different kind on one face |
| Offset / rotate / scale / flip per face, reset, fit | Build (P8) | As pattern settings per face, not UVs |
| Copy / paste face attributes, alt-drag | Build (P8) | |
| Texture lock (patterns follow a moved brush) | Partial | Moving parts already carry their patterns (`MapMesher.riding()`); static blocks deliberately do not |
| Image textures, WAD / texture collections | Skip | Would change the art pipeline. See "Decisions" |

### Entities

| TrenchBroom | Status | Notes |
| --- | --- | --- |
| Entity browser | Godot | Add Node / instance scene; every map node type is a script class |
| Entity property editor with smart editors | Godot | Inspector, with typed exports and dropdowns |
| Brush entities (brushes tied to an entity) | Godot | A MapMover, MapIsland, MapHazard… with blocks under it |
| Target / link lines between entities | Build (P7) | Draw lines from terminals and levers to the events they trigger |
| FGD / DEF / ENT definitions | Skip | Script classes do this job |

### Checking and running

| TrenchBroom | Status | Notes |
| --- | --- | --- |
| Issue browser (bad brushes, empty groups…) | Partial (P7) | Configuration warnings + tests exist; add a Problems list in the Map dock that selects the culprit |
| Compile, launch the engine | Godot | F6 plays the open map |
| Point file / portal file (leaks) | Skip | No BSP compile, no leaks |
| Games, mods, game configs | Skip | One game |
| Autosave, backups | Godot | |

## The foundation: a hull shape

Everything in phases 2–5 needs blocks that can be any convex shape. The code is
already most of the way there:

- `MapMesher.hull_points()` returns the corner lists a wedge, bevel, dome or arch is
  made of. `MapMesher._hulls()` draws those with `hull_faces()`, a general convex-hull
  face finder.
- `MapRoot.collision_shapes()` turns the same corner lists into
  `ConvexPolygonShape3D`s.
- The navigation mesh is baked from static colliders, so it follows for free.

### Design

- **New shape `HULL`** (`SHAPE_NAMES` entry `"hull"`) with
  `@export var points: PackedVector3Array`: the corners, in the block's own frame,
  centred on the origin.
- **Points, not planes.** TrenchBroom stores planes in `.map` files but its tools edit
  vertices. Points fit `hull_points()` and collision directly. Faces and planes are
  worked out from the points when needed (`hull_faces()`).
- **Size stays meaningful.** `size` is the bounds of the points. Setting it (inspector,
  resize handles, scale gizmo) scales the points about the centre, so existing tools
  that only know `size` keep working.
- **Points are always the hull's own corners.** After every edit, drop points that are
  inside the hull or on a face (`MapMesher.hull_corners()`, new), and snap to the grid.
- **Convexity is enforced, as in TrenchBroom.** A vertex move that would make the
  shape concave is refused (shown in red while dragging). Concave shapes stay several
  blocks.
- **Converting.** Map > Make Editable turns the selection into hulls:
  - box, wedge, bevel and solid dome: exact, one block each;
  - cylinder and cone: exact, one block (the flat sides you already see);
  - tube, arch and hollow or cut-open dome: one hull block per lump, in a group.
  A converted block keeps its kind, tint, settings and transform.
- **`to_piece()`** adds `"points"`, scaled by the transform's scale as `size` is now.

### What else has to learn about hulls

These places branch on `piece.shape` and currently treat anything that is not a box as
round:

| Where | What it does | Change |
| --- | --- | --- |
| `map_mesher.gd` `build()`, `hull_points()` | Drawing | Add `"hull"`: one lump, its points |
| `map_root.gd:322` | Footstep material lookup | Use the bounds of the points |
| `map_root.gd:464` | Highest floor under a point | Point-in-hull test (xz) |
| `map_root.gd:803` | Which block a player stands on (islands, movers) | Point-in-hull test |
| `map_root.gd:1024` | Hazard contact | Point-in-hull test |
| `map_destruction.gd:112, 144` | Per-cell breaking is box-only | Hulls break whole-block only; warn if set to Per Cell |
| `block_gizmo.gd` | Face handles | Hulls get vertex/face handles instead (P2, P3) |
| `map_ops.gd` `clip()`, `hollow()`, `aligned_box()`, `ray_box()` | Box geometry | Hull versions (P4, P5); ray test against hull faces |
| `tests/map_flicker_test.gd` | Overlapping-face check | Add `"hull"` to the hull branch |
| `tests/map_scene_test.gd` | Map sanity | Hull blocks: convex, at least 4 corners not in one plane |
| `tools/arena/*.py` builders | Write blocks | No change needed; they never write hulls |

`hull_faces()` tests every three points against all the others, so it gets slow with
many corners. Cap a hull at 64 corners, and cache the faces on the block in the editor.

## Phases

Sizes: **S** about a day, **M** a few days, **L** one to two weeks. Each phase ends
with tests in `tests/map_tools_test.gd` (headless) and a section in
`docs/DEVELOPMENT.md`.

### P1. Hull shape (M) — done
The foundation above: the shape, conversion, drawing, collision, the runtime checks,
destruction rules, tests. No new mouse tools yet: hull blocks can be made by converting
and edited by typing points in the inspector.
**Done when** a converted box, wedge and cylinder look, collide, are stood on and break
(whole) exactly as before conversion, and every existing map still passes its tests.

What was built:
- `MapBlock.Shape.HULL` with `points` (kept centred; `size` is their bounds and
  stretches them), `shape_lumps()`, `points_bounds()`, and warnings for a flat hull or
  one over 32 corners. Choosing Hull in the inspector converts the current shape.
- `MapMesher`: `hull_corners()`, `hull_planes()`, `hull_has()`, `hull_top()`,
  `MAX_HULL_CORNERS`. `hull_faces()` now stops testing a plane as soon as points lie
  on both sides of it (same result, faster).
- `MapRoot`: hulls are exact for standing on movers, moving ground and hazards; the
  box round them for footsteps.
- `MapOps.make_editable()` / Map > Make Editable (Hull): exact conversion, multi-lump
  shapes become groups. Mirror (copy and in place) mirrors hull corners.
- Tests: a hull section in `tests/map_tools_test.gd`, a built-map hazard check in
  `tests/map_scene_test.gd`, hulls in `tests/map_flicker_test.gd`.

Known limits, left for later phases:
- Typing a corner in the inspector re-centres the shape without moving the block, so
  the shape shifts by the change in its middle (and inspector undo doesn't move it
  back). The vertex tool (P2) will set corners and position together.
- Collision of a converted cylinder is its flat sides, not Godot's round cylinder.
- Clip and Hollow ignore hulls until P4 and P5.

### P2. Vertex tool (M–L) — done
Built as `addons/map_tools/tool_vertex.gd` with the geometry in `map_ops.gd`
(`reshaped()`, `without_points()`, `hull_placement()`, `hull_edges()`, `ray_hull()`),
tested in `tests/map_tools_test.gd` ("vertex tool"). Each edit sets the corners and the
block's position together, so the shape stays put while its corners stay centred (the
P1 limit for inspector edits still applies to typing in Points by hand).

Differences from the plan:
- "Convex" is enforced the TrenchBroom way for dents: a moved corner may not end up
  inside the shape. Pulling a corner out past a neighbour is allowed; the neighbour,
  now inside, is dropped.
- A double-click on a face adds the corner at the face's middle, not where you click.
- A click away from the corners selects a block by the box round it (as the other
  tools do), so a click in a hull's empty corner can pick it.

The original plan:
- Tool `V` in the strip, alongside Draw and Clip. Selected hull blocks show their
  corners. Non-hull blocks offer "Make Editable" instead.
- Click a corner to select it, Shift to add, drag a box in the view to select several.
  Corners of different blocks that sit in the same place move together.
- Drag to move, snapped to the grid; in a 2D view it moves in that view's plane; in
  3D, on the plane facing the camera, Shift for up/down. Arrow keys nudge by the grid.
- Double-click an edge or face to add a corner there; Delete removes corners.
- Red preview and refusal when the result would be concave or flat.
- One undo step per drag.

### P3. Edge and face tools; slanted resize (M) — done
Built into the Vertex tool rather than as separate E and F tools: Godot's 3D editor
already uses E and R (rotate, scale), and one tool that picks whatever is clicked (a
corner first, then an edge, then a face) needs no mode switching.
- Edges: click to pick (its two corners), drag to move by whole grid squares.
- Faces: click to pick (its corners); dragging a face pushes or pulls it along its own
  normal with every other face keeping its plane (`MapOps.extruded()`, which rebuilds
  the corners from the planes with `Geometry3D.compute_convex_mesh_points`). Refused
  when the face would vanish or the shape go flat.
- Hull blocks' gizmo handles are now one per face, at its middle, doing the same push
  and pull (`MapOps.pushed_face()`, which also handles a scaled block).
- Moving a face freely (rather than along its normal) is done by picking its corners
  and nudging them with the arrow keys; dragging a face always pushes or pulls.

The original plan:
- `E` and `F` modes of the same tool: select edges or faces, move them as above.
- **Extrude** (TrenchBroom's Shift-drag a face): move one face along its normal while
  every other face keeps its plane. Done with planes: offset the face's plane, work out
  the corners again as three-plane intersections. This also gives hulls resize handles
  on any face, slanted or not.

### P4. Clip at any angle (M)
- Two clicks in a 2D view (the cut runs through them, square to the view) or three in
  3D, all snapped to the grid. Enter cuts; a key cycles keep front / back / both.
- An axis-aligned cut of a box still gives boxes (what Clip does now); any other cut
  gives hulls.
- Every selected block the plane passes through is cut, as now.

### P5. CSG: subtract, merge, intersect, hollow (L)
- **Merge**: the convex hull of the selected blocks, as one block (kind from the
  first). Refused if they don't make a convex shape together without filling gaps,
  unless forced.
- **Subtract**: cut the selected blocks out of the blocks they overlap. Each overlapped
  block is split by the cutter's faces into convex pieces, and the ones inside are
  dropped. The pieces keep the original's kind and settings, in a group. Boxes cut by
  boxes stay boxes.
- **Intersect**: what all of the selected blocks share.
- **Hollow for any hull**: walls made by moving each face inward and subtracting.
- Split pieces that are nearly flat or tiny are dropped. A grid-snap pass keeps the
  pieces clean.

### P6. Transforms and organising (M)
- Nudge with arrow keys / PgUp / PgDn by the grid (blocks and groups).
- "Repeat last move", for duplicate-and-move chains.
- Turn 90° about X / Y / Z about the selection's middle or a pivot you place.
- Shear (hulls only): drag a face sideways keeping its plane's direction.
- Select touching, select inside, select tall (everything in a 2D view's column),
  invert selection, isolate selection.
- Layers: a list of the map root's top-level groups in the Map dock with show / lock /
  "left out of the game" switches.
- Linked prefabs: Place Linked instances the prefab scene instead of copying it. Needs
  `MapRoot.build()` and `map_ops.blocks_in()` checked for blocks inside instances.
  Editing the prefab updates every map using it.

### P7. Viewport and checking (M)
- Grid drawn at the current step on the plane under the cursor.
- Edges of the selected blocks drawn over everything.
- Lines from terminals and levers to the events they trigger.
- **Problems** list in the Map dock: hulls that are flat, concave or too detailed;
  blocks outside the bounds; tiny blocks; faces that overlap and flicker (from
  `map_flicker_test.gd`); kinds missing from the palette; too few spawns. Click one to
  select it. The headless tests keep running the same checks.

### P8. Per-face kinds and pattern alignment (L, optional)
The "UV editing" equivalent, for this game's procedural look.
- A face-select mode (shared with P3), for every shape, not just hulls.
- Per-face **kind**: a face can be another kind than its block (a trim, a painted
  floor) with no extra block. Stored on the block as `face_kinds`, keyed by face
  direction (box faces by axis; hull faces by rounded normal, so they survive moving
  corners). The mesher puts that face into the other kind's merged mesh.
- Per-face **pattern offset, turn and scale**, plus Reset and "align to the face next
  to it". Passed to `map_surface.gdshader` in a spare vertex channel (`CUSTOM0`),
  which survives merging by kind.
- Copy / paste a face's settings; Alt-click to paint them on another face.
- Breaking needs the face kinds carried onto the pieces it makes
  (`map_destruction.gd` skins).

## Order and size

| Milestone | Phases | Size | What you get |
| --- | --- | --- | --- |
| Shapes you can bend | P1, P2 | about 2 weeks | Any convex block, vertex editing |
| TrenchBroom feel | + P3, P4, P6 | about 2 more weeks | Edges, faces, slanted extrude, angled clip, nudging, layers, linked prefabs |
| Parity on geometry | + P5, P7 | about 2–3 more weeks | CSG, problems list, viewport aids |
| Faces | + P8 | about 1–2 more weeks | Per-face kinds and pattern alignment |

These are rough. P5 (subtract) and P8 are the ones most likely to run long.

## Decisions to make

1. **Image textures.** Recommended: no. Keep the palette and world-space patterns, do
   P8 for alignment. Real textures with UVs would be a new art pipeline, not an editor
   feature.
2. **Per-cell breaking on hulls.** Recommended: whole-block only for now. Per-cell on
   a slanted slab is possible later, but `map_destruction.gd` is built round boxes.
3. **Linked prefabs.** Recommended: yes (P6). It's TrenchBroom's best newer feature,
   and Godot scene instancing does most of the work.
4. **How far to go.** This fork's aim is a trimmed-down game. Milestone 1 alone
   (vertex editing) covers most of what brush editing adds to map making; the rest can
   wait until a map needs it.
