extends RefCounted
## The inspector's movement: walking, golf cart and collision. No drawing, no input
## reading. The street controller feeds it a move vector in [-1, 1] each frame.

const Neighborhood := preload("res://scripts/world/neighborhood.gd")
const LotSlots := preload("res://scripts/world/lot_slots.gd")

const WALK_SPEED := 380.0
const CART_SPEED := 2.2
const DEADZONE := 0.12
const BODY_RADIUS := 14.0
const ACCEL := 16.0

var position := Vector2.ZERO
var velocity := Vector2.ZERO
var facing := 0.0           ## target heading for drawing
var angle := 0.0            ## smoothed heading
var phase := 0.0            ## gait phase
var moving := false
var cart := false
var speed_mult := 1.0       ## <1 while slowed by an incident (soaked, chasing a dog)


func speed_fraction() -> float:
	return clampf(velocity.length() / (WALK_SPEED * (CART_SPEED if cart else 1.0)), 0.0, 1.0)


## `obstacles` are lot-slot entries or {pos, rot, half}; `circles` are pedestrians to side-step.
func update(delta: float, move: Vector2, hood: Neighborhood, obstacles: Array, circles: Array) -> void:
	var target := Vector2.ZERO
	if move.length() > DEADZONE:
		var strength := (move.length() - DEADZONE) / (1.0 - DEADZONE)
		target = move.normalized() * WALK_SPEED * strength * (CART_SPEED if cart else 1.0) * speed_mult
	velocity = velocity.lerp(target, 1.0 - exp(-ACCEL * delta))
	if velocity.length() < 4.0 and target == Vector2.ZERO:
		velocity = Vector2.ZERO
	moving = velocity.length() > 20.0
	if velocity == Vector2.ZERO:
		return
	var previous := position
	var candidate := previous + velocity * delta
	candidate = _stay_on_surface(hood, previous, candidate)
	candidate = _sidestep(previous, candidate, circles, hood)
	candidate = _keep_clear(previous, candidate, obstacles)
	position = candidate
	if velocity.length() > 20.0:
		facing = velocity.angle() + PI * 0.5
	phase += delta * 10.0 * speed_fraction()


func smooth_heading(delta: float) -> void:
	angle = lerp_angle(angle, facing, 1.0 - exp(-12.0 * delta))


func _walkable(hood: Neighborhood, p: Vector2) -> bool:
	if cart:
		# Carts stay on pavement; driveways are too tight, so park at the curb and walk in.
		return hood.edge_distance(p) <= Neighborhood.WALK_W * 0.8 and not hood.is_water(p) \
				and p.x > 4.0 and p.x < Neighborhood.WORLD_W - 4.0 and p.y > 4.0 and p.y < Neighborhood.WORLD_H - 4.0
	return hood.is_walkable(p)


func _stay_on_surface(hood: Neighborhood, previous: Vector2, candidate: Vector2) -> Vector2:
	if _walkable(hood, candidate):
		return candidate
	var horizontal := Vector2(candidate.x, previous.y)
	if _walkable(hood, horizontal):
		return horizontal
	var vertical := Vector2(previous.x, candidate.y)
	if _walkable(hood, vertical):
		return vertical
	return previous


## Side-passes pedestrians instead of stopping dead behind them.
func _sidestep(previous: Vector2, candidate: Vector2, circles: Array, hood: Neighborhood) -> Vector2:
	var push := Vector2.ZERO
	var too_close := false
	var heading := candidate - previous
	for other: Vector2 in circles:
		var d := candidate.distance_to(other)
		if d >= 52.0 or d < 0.01:
			continue
		var away := (candidate - other) / d
		var tangent := Vector2(-away.y, away.x)
		if tangent.dot(heading) < 0.0:
			tangent = -tangent
		push += away * (52.0 - d) * 0.5 + tangent * (52.0 - d) * 0.35
		too_close = too_close or d < 26.0
	if push == Vector2.ZERO:
		return candidate
	var pushed := candidate + push
	if _walkable(hood, pushed):
		return pushed
	return previous if too_close else candidate


func _keep_clear(previous: Vector2, candidate: Vector2, obstacles: Array) -> Vector2:
	for entry: Dictionary in obstacles:
		if not LotSlots.entry_contains(entry, candidate, BODY_RADIUS):
			continue
		if not LotSlots.entry_contains(entry, Vector2(candidate.x, previous.y), BODY_RADIUS):
			candidate.y = previous.y
		elif not LotSlots.entry_contains(entry, Vector2(previous.x, candidate.y), BODY_RADIUS):
			candidate.x = previous.x
		else:
			candidate = previous
	return candidate
