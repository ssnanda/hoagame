extends RefCounted
## One property: where it is, which way it faces, and how it connects to its street.
## Pure data. Rendering lives in world_view.gd, game rules in main.gd.

var id := 0
var street_id := 0
var street_name := ""
var number := 0
var s_along := 0.0                   ## distance along the street, used for numbering
var side := 0                        ## -1 / +1 relative to street direction, 0 on a cul-de-sac bulb
var group := ""                      ## cul-de-sac name, for validation
var kind := "standard"               ## standard | corner | cul_de_sac
var archetype := 0
var center := Vector2.ZERO           ## house footprint center
var front := Vector2.DOWN            ## unit vector from the house toward its street
var house_size := Vector2(112, 140)  ## x = front-to-back depth, y = frontage width
var polygon := PackedVector2Array()  ## lot boundary, world space
var corner_edge := PackedVector2Array()  ## side of a corner lot that faces the other street (2 points)
var curb := Vector2.ZERO             ## where the driveway meets the sidewalk
var driveway_end := Vector2.ZERO     ## where the driveway meets the house
var driveway_width := 40.0
var mailbox := Vector2.ZERO
var address := ""
var trees: Array[Vector3] = []       ## x, y, radius


func rotation() -> float:
	## House drawing frame: local +x points at the street.
	return front.angle()


func right() -> Vector2:
	return Vector2(-front.y, front.x)


func driveway_mid() -> Vector2:
	return curb.lerp(driveway_end, 0.5)


## Footprint corners (world space), optionally grown by `margin`.
func footprint(margin := 0.0) -> PackedVector2Array:
	var f := front
	var r := right()
	var hx := house_size.x * 0.5 + margin
	var hy := house_size.y * 0.5 + margin
	return PackedVector2Array([center + f * hx + r * hy, center + f * hx - r * hy,
			center - f * hx - r * hy, center - f * hx + r * hy])


## Position in lot-local terms: `forward` toward the street, `lateral` to the right.
func local_point(forward: float, lateral: float) -> Vector2:
	return center + front * forward + right() * lateral
