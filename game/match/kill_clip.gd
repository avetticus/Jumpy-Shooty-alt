class_name KillClip
extends RefCounted
## A few seconds of a match, kept so a kill can be watched again from the killer's
## eyes (see Killcam and KillcamView). Not video: for every player, what this copy of
## the game drew for them about 30 times a second (where they were, where they looked,
## what move they were in), plus the shots, rockets and blows that happened.
##
## Times are seconds on this copy's clock, moved back by how late each player's data
## reached us, so they are (roughly) when things really happened. `offsets` then moves
## each player to where the killer saw them: the killer's own screen showed everyone a
## little in the past too.
##
## A death's remains (a ragdoll or giblets, see Remains) are kept too, as Wrecks: where
## each of their bodies went as they fell, so a replay can show the same fall at its
## own speed (slow motion, a video saved frame by frame) without simulating it again.
##
## So are the map's moving parts (see MapReplay), as PropTracks: a crane and its load,
## flying islands, walls shot through. They are kept on the killer's clock as they
## are (every copy draws them in the present, as the killer did), and each player's
## frames are where they were on the map at that same moment.
##
## The killer's aim: their frames are what this copy drew of them, a little smoothed.
## Every shot also says exactly where they aimed it from and to (Match.shot_aimed), and
## the replay turns the killer's eyes onto that at the moment of each shot (aim_fix).
## Where the killer saw the others is an estimate from the network's timing; a hit says
## where its target was in the killer's eyes, so align_to_hits() moves each target the
## killer hit to where the hits say.

## One player's frames, oldest first.
class Track:
	var times := PackedFloat64Array()
	## Each frame: see Player.shown_state() (feet, velocity, yaw, pitch, pose, flags,
	## rope on, rope anchor, alive, drawn, eye height, weapon, the grappling hook's rope).
	var frames: Array = []
	var character := ""
	var color := Color.WHITE
	var paint := Color(0, 0, 0, 0)   ## team modes: the team's paint (Teams.paint_for); clear otherwise
	var name := ""

	func push(t: float, frame: Array) -> void:
		if not times.is_empty() and t <= times[-1]:
			t = times[-1] + 0.0001   # the estimate of how late data is drifts; never go back
		times.append(t)
		frames.append(frame)

	## Forget frames older than `before`.
	func trim(before: float) -> void:
		var n := 0
		while n < times.size() - 1 and times[n] < before:
			n += 1
		if n > 0:
			times = times.slice(n)
			frames = frames.slice(n)

	func is_empty() -> bool:
		return times.is_empty()

	## The frames from `from` to `to` (and one either side, to blend into), as a new track.
	func slice(from: float, to: float) -> Track:
		var out := Track.new()
		out.character = character
		out.color = color
		out.paint = paint
		out.name = name
		var a := maxi(_index(from), 0)
		var b := mini(_index(to) + 2, times.size())
		out.times = times.slice(a, b)
		out.frames = frames.slice(a, b)
		return out

	## The last frame at or before t (-1 if t is before the first).
	func _index(t: float) -> int:
		var lo := 0
		var hi := times.size() - 1
		if hi < 0 or t < times[0]:
			return -1
		while lo < hi:
			var mid := (lo + hi + 1) >> 1
			if times[mid] <= t:
				lo = mid
			else:
				hi = mid - 1
		return lo

	## The frame at time t, blended between the two either side (positions and aim
	## blend; the move, flags and weapon come from the earlier one). Holds the first
	## and last frames outside the track. Empty if there are no frames.
	func sample(t: float) -> Array:
		if times.is_empty():
			return []
		var i := _index(t)
		if i < 0:
			return frames[0]
		if i >= times.size() - 1:
			return frames[-1]
		var a: Array = frames[i]
		var b: Array = frames[i + 1]
		var span := maxf(times[i + 1] - times[i], 0.0001)
		var u := clampf((t - times[i]) / span, 0.0, 1.0)
		if a[8] != b[8] or (a[0] as Vector3).distance_to(b[0]) > 4.0:
			return a if u < 0.5 else b   # a death or a respawn: no blending across it
		var out := a.duplicate()
		out[0] = (a[0] as Vector3).lerp(b[0], u)
		out[1] = (a[1] as Vector3).lerp(b[1], u)
		out[2] = lerp_angle(float(a[2]), float(b[2]), u)
		out[3] = lerpf(float(a[3]), float(b[3]), u)
		out[7] = (a[7] as Vector3).lerp(b[7], u) if a[6] and b[6] else a[7]
		out[10] = lerpf(float(a[10]), float(b[10]), u)
		if a.size() > 12 and b.size() > 12 and a[12] != null and b[12] != null:
			out[12] = _blend_hook(a[12], b[12], u, span)
		return out

	## The grappling hook's rope between two frames `span` seconds apart (each [hook,
	## slack, seconds since the shot, seconds since it pulled tight]). The hook and the
	## slack blend; the two clocks run on from the earlier frame, so the rope's ripples
	## and its twang move as smoothly in a replay as they did in the match, and a rope
	## that pulled tight between the two frames twangs from the moment it did.
	static func _blend_hook(a: Array, b: Array, u: float, span: float) -> Array:
		if float(b[2]) < float(a[2]):
			return a if u < 0.5 else b   # a new shot: no blending across it
		var twang := float(b[3]) - (1.0 - u) * span if float(b[3]) >= 0.0 else -1.0
		return [(a[0] as Vector3).lerp(b[0], u), lerpf(float(a[1]), float(b[1]), u), lerpf(float(a[2]), float(b[2]), u),
			twang if twang >= 0.0 else -1.0]

	func first_time() -> float:
		return times[0] if not times.is_empty() else INF

	func last_time() -> float:
		return times[-1] if not times.is_empty() else -INF


## What a player left when knocked out, as this copy saw it fall: a Ragdoll's bones or
## Gibs' bodies, each frame every one's place in the world (see their capture()), from
## the moment of the death (on the same clock as the player's Track) for the first
## Killcam.WRECK_FOR seconds. Shared, not copied, by the clips that show it.
class Wreck extends Track:
	var who := 0
	var kind := "ragdoll"     ## or "gibs"
	var fx: Dictionary = {}   ## how the blow fell (Match.death_fx)
	var weapon := ""
	var scrap := 0            ## gibs: how many of the bodies are scrap

	## A new recording of `remains` (a Ragdoll or Gibs), as it was at the death, `at`.
	static func of(remains: Node3D, at: float) -> Wreck:
		var w := Wreck.new()
		w.who = int(remains.get("who"))
		w.kind = "gibs" if remains is Gibs else "ragdoll"
		w.fx = remains.get("blow")
		w.character = str(remains.get("character"))
		w.color = remains.get("body_color")
		w.paint = Teams.paint_for(w.who)   # (the team they died on)
		w.weapon = str(remains.get("weapon"))
		if remains is Gibs:
			w.scrap = (remains as Gibs).scrap_count()
		w.push(at, remains.call("start_pose"))
		return w

	## Every body's place at time t, blended between the frames either side (the first
	## and last held outside the recording).
	func pose_at(t: float) -> Array:
		var i := _index(t)
		if i < 0:
			return frames[0]
		if i >= times.size() - 1:
			return frames[-1]
		var a: Array = frames[i]
		var b: Array = frames[i + 1]
		var u := clampf((t - times[i]) / maxf(times[i + 1] - times[i], 0.0001), 0.0, 1.0)
		var out := []
		for k in mini(a.size(), b.size()):
			out.append((a[k] as Transform3D).interpolate_with(b[k], u))
		return out


## One of the map's moving parts (see MapReplay): what it looked like, kept only when
## it changed (with the last look before a change kept too, so a part that stood still
## a while blends only across the change). Shared, not copied, while it records.
class PropTrack:
	var times := PackedFloat64Array()
	var states: Array = []
	var seen := -INF   ## when it was last looked at (Killcam)

	## Look at it at time t: kept if it changed.
	func look(t: float, state: Variant) -> void:
		if states.is_empty() or state != states[-1]:
			if not times.is_empty() and seen > times[-1] + 0.0001:
				_push(seen, states[-1])   # (it stood still until just now)
			_push(t, state)
		seen = t

	func _push(t: float, state: Variant) -> void:
		if not times.is_empty() and t <= times[-1]:
			t = times[-1] + 0.0001
		times.append(t)
		states.append(state)

	## Forget looks older than `before`, but the last one before it (what it looked like then).
	func trim(before: float) -> void:
		var n := 0
		while n < times.size() - 1 and times[n + 1] <= before:
			n += 1
		if n > 0:
			times = times.slice(n)
			states = states.slice(n)

	func is_empty() -> bool:
		return times.is_empty()

	## The looks from `from` to `to`, and the one before `from`, as a new track.
	func slice(from: float, to: float) -> PropTrack:
		var out := PropTrack.new()
		var a := 0
		while a < times.size() - 1 and times[a + 1] <= from:
			a += 1
		var b := a
		while b < times.size() and times[b] <= to:
			b += 1
		b = mini(b + 1, times.size())
		out.times = times.slice(a, b)
		out.states = states.slice(a, b)
		out.seen = seen
		return out

	## [the look at or before t, the next one (null: none), 0..1 between them]. The
	## first look holds before the track, and the last after it.
	func at(t: float) -> Array:
		if times.is_empty():
			return [null, null, 0.0]
		if t <= times[0]:
			return [states[0], null, 0.0]
		var lo := 0
		var hi := times.size() - 1
		while lo < hi:
			var mid := (lo + hi + 1) >> 1
			if times[mid] <= t:
				lo = mid
			else:
				hi = mid - 1
		if lo >= times.size() - 1:
			return [states[-1], null, 0.0]
		var u := clampf((t - times[lo]) / maxf(times[lo + 1] - times[lo], 0.0001), 0.0, 1.0)
		return [states[lo], states[lo + 1], u]


## Player id -> Track.
var tracks: Dictionary = {}
## What happened, oldest first: {t, kind ("shot", "projectile", "boom", "melee", and for
## sticky grenades "stick", "armed", "gone"), who, ...}.
var events: Array = []
## What deaths left (Wreck), oldest first: any still lying about during the clip.
var wrecks: Array = []
## The map's moving parts: key (its path in the map, see MapReplay) -> PropTrack.
var props: Dictionary = {}
## The kill (see Match.kill_info).
var info: Dictionary = {}
var killer := 0
var victim := 0
## When the killer landed the blow, and the stretch to watch.
var kill_time := 0.0
var start := 0.0
var end := 0.0
## Player id -> seconds to add to the killer's time to sample them (minus how far in
## the past the killer's screen showed them). 0 for the killer.
var offsets: Dictionary = {}
## Player id -> seconds to add to an event's time: when the killer saw it.
var event_offsets: Dictionary = {}
var map := ""


## The time to sample player `id` at, for killer time t.
func time_for(id: int, t: float) -> float:
	return t + float(offsets.get(id, 0.0))


## When the killer saw event `e`.
func event_time(e: Dictionary) -> float:
	return float(e.t) + float(event_offsets.get(int(e.who), 0.0))


## A copy holding only what is needed to watch [start - margin, end + margin].
func cut(margin: float = 0.6) -> KillClip:
	var out := KillClip.new()
	out.info = info
	out.killer = killer
	out.victim = victim
	out.kill_time = kill_time
	out.start = start
	out.end = end
	out.offsets = offsets.duplicate()
	out.event_offsets = event_offsets.duplicate()
	out.map = map
	for id in tracks:
		var off := float(offsets.get(id, 0.0))
		var part: Track = (tracks[id] as Track).slice(start + off - margin, end + off + margin)
		if not part.is_empty():
			out.tracks[id] = part
	var stuck := {}   # sticky grenade id -> its latest "stick" before the clip, if it is still there when it starts
	for e in events:
		var et := event_time(e)
		if et < start - margin:
			match str(e.get("kind", "")):
				"stick":
					stuck[int(e.id)] = e
				"armed":
					if stuck.has(int(e.id)):
						stuck[int(e.id)] = (stuck[int(e.id)] as Dictionary).merged({"armed": true}, true)
				"boom", "gone":
					stuck.erase(int(e.id))
		elif et <= end + margin:
			out.events.append(e)
	out.events = stuck.values() + out.events
	for w: Wreck in wrecks:   # any lying about during the clip (each holds its last frame once it has settled)
		var off := float(offsets.get(w.who, 0.0))
		if w.first_time() <= end + off + margin and w.first_time() + Remains.LIFETIME >= start + off - margin:
			out.wrecks.append(w)
	for key in props:
		var part: PropTrack = (props[key] as PropTrack).slice(start - margin, end + margin)
		if not part.is_empty():
			out.props[key] = part
	return out


## Whether there is enough of the killer to watch: their recording reaches back at
## least `lead` seconds before the kill. A clip starts no earlier than that recording.
func has_killer(lead: float = 0.0) -> bool:
	var t: Track = tracks.get(killer)
	if t == null or t.is_empty() or t.first_time() > kill_time - lead or t.last_time() < start:
		return false
	start = maxf(start, t.first_time())
	return true


# ---------------------------------------------------------------------------
# The killer's aim, and where their targets were

const AIM_BRIDGE := 0.35   ## shots this close together: the aim is held onto each in turn between them
const AIM_EASE := 0.15     ## ...otherwise it eases onto a shot over this long, and off it again
const AIM_REACH := 1.5     ## metres: a shot from further than this from the killer's eyes moves only the aim

## The killer's shots: [when (the killer's clock), from (their eyes), the way they aimed],
## oldest first.
func aim_keys() -> Array:
	var out := []
	for e in events:
		if int(e.who) != killer:
			continue
		match str(e.kind):
			"aim":
				out.append([event_time(e), e.eye, (e.aim as Vector3).normalized()])
			"projectile":
				out.append([event_time(e), e.origin, (e.direction as Vector3).normalized()])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out


## Yaw and pitch (radians) of a direction, the way Player keeps them.
static func yaw_pitch(dir: Vector3) -> Vector2:
	return Vector2(atan2(-dir.x, -dir.z), asin(clampf(dir.y, -1.0, 1.0)))


## How far (degrees) the killer's recorded aim was off a shot (one of aim_keys()), or
## -1 if their frames do not reach it yet (for the tests' logs).
func aim_miss(key: Array) -> float:
	var track: Track = tracks.get(killer)
	if track == null or track.is_empty() or track.last_time() < float(key[0]) + 0.02 or track.first_time() > float(key[0]):
		return -1.0
	var f := track.sample(float(key[0]))
	var had := Basis.from_euler(Vector3(float(f[3]), float(f[2]), 0.0)) * Vector3.FORWARD
	return rad_to_deg(had.angle_to(key[2]))


## Where the killer's eyes should be turned at time t, from their shots (aim_keys(),
## oldest first): [how much (0..1: 0 leaves the recording alone), yaw, pitch, from where
## (the eyes; INF: no say)]. All the way onto a shot at that shot; between shots close
## together, from one to the next; otherwise easing on before a shot and off after it.
## The recording is blended toward this, not added to: after a flick the recording
## catches up by itself, so the replay does not swing past.
static func aim_fix(keys: Array, t: float) -> Array:
	var none := [0.0, 0.0, 0.0, Vector3.INF]
	if keys.is_empty():
		return none
	var j := -1
	for i in keys.size():
		if float(keys[i][0]) <= t:
			j = i
		else:
			break
	var before: Array = keys[j] if j >= 0 else []
	var after: Array = keys[j + 1] if j + 1 < keys.size() else []
	if not before.is_empty() and not after.is_empty() and float(after[0]) - float(before[0]) <= AIM_BRIDGE:
		var u := (t - float(before[0])) / maxf(float(after[0]) - float(before[0]), 0.0001)
		var a := yaw_pitch(before[2])
		var b := yaw_pitch(after[2])
		return [1.0, lerp_angle(a.x, b.x, u), lerpf(a.y, b.y, u), (before[1] as Vector3).lerp(after[1], u)]
	var w_before := _ease_off(t - float(before[0])) if not before.is_empty() else 0.0
	var w_after := _ease_off(float(after[0]) - t) if not after.is_empty() else 0.0
	if w_before <= 0.0 and w_after <= 0.0:
		return none
	var k: Array = before if w_before >= w_after else after
	var aim := yaw_pitch(k[2])
	return [maxf(w_before, w_after), aim.x, aim.y, k[1]]


static func _ease_off(dt: float) -> float:
	if dt < 0.0 or dt >= AIM_EASE:
		return 0.0
	var u := 1.0 - dt / AIM_EASE
	return u * u * (3.0 - 2.0 * u)


const ALIGN_REACH := 0.3    ## seconds: how far a target may be moved in time to meet the killer's hits
const ALIGN_STEP := 0.005
const ALIGN_COST := 0.3     ## metres per second moved: a little reluctance, so a tie stays where the estimate was

## Every player the killer's shots hit in the clip, moved in time (their `offsets`) to
## where the hits say the killer saw them: the shot that hit went through them on the
## killer's screen, so it does in the replay too. Only hits within reach of a body are
## used; a player with none stays where the network's timing put them.
func align_to_hits() -> void:
	var hits := {}   # player id -> [[killer time, where it hit]]
	for e in events:
		if int(e.who) != killer or str(e.kind) != "shot":
			continue
		var t := event_time(e)
		var ends: PackedVector3Array = e.ends
		var hit: Array = e.hits
		for i in mini(ends.size(), hit.size()):
			if not hit[i]:
				continue
			var who := _body_at(ends[i], t)
			if who != 0:
				if not hits.has(who):
					hits[who] = []
				hits[who].append([t, ends[i]])
	for id in hits:
		var base := float(offsets.get(id, 0.0))
		var best := 0.0
		var best_cost := INF
		var n := int(ALIGN_REACH / ALIGN_STEP)
		for k in range(-n, n + 1):
			var dt := k * ALIGN_STEP
			var cost := absf(dt) * ALIGN_COST
			for h in hits[id]:
				cost += minf(_miss(id, float(h[0]) + base + dt, h[1]), 3.0)   # (the hit is the nearest point to their middle line)
			if cost < best_cost - 0.00001:
				best_cost = cost
				best = dt
		offsets[id] = base + best
		event_offsets[id] = float(event_offsets.get(id, 0.0)) - best


## Which player (not the killer) a hit at `point` was on at killer time t, or 0.
func _body_at(point: Vector3, t: float) -> int:
	var who := 0
	var nearest := 2.5
	for id in tracks:
		if id == killer:
			continue
		var d := _miss(id, time_for(id, t), point)
		if d < nearest:
			nearest = d
			who = id
	return who


## How far `point` is from the middle line of player `id`'s body at their time t.
func _miss(id: int, t: float, point: Vector3) -> float:
	var track: Track = tracks.get(id)
	if track == null or track.is_empty() or t < track.first_time() - 0.1 or t > track.last_time() + 0.1:
		return INF
	var f := track.sample(t)
	if not bool(f[8]):
		return INF
	var feet: Vector3 = f[0]
	var r := Player.CAPSULE_RADIUS
	var top := feet + Vector3(0, maxf(Player.height_for_pose(int(f[4])) - r, r), 0)
	var bottom := feet + Vector3(0, r, 0)
	return point.distance_to(Geometry3D.get_closest_point_to_segment(point, bottom, top))
