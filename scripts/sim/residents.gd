extends RefCounted
## Households: who lives where, what they are like, and what they remember about you.
## Raw numbers stay internal; the UI shows narrative labels.

const FIRST_NAMES := ["Avery", "Jordan", "Maya", "Noah", "Priya", "Mateo", "Nora", "Theo", "Lena", "Malik",
		"Sofia", "Eli", "June", "Arun", "Rosa", "Caleb", "Harper", "Omar", "Ingrid", "Dev"]
const LAST_NAMES := ["Parker", "Nguyen", "Patel", "Robinson", "Garcia", "Wilson", "Okafor", "Chen", "Miller",
		"Henderson", "Johnson", "Brown", "Davis", "Martinez", "Kowalski", "Singh", "Larsen", "Baptiste"]
const TRAITS := ["friendly", "rule_follower", "chronic_complainer", "board_insider", "anti_hoa", "litigious",
		"elderly", "new_homeowner", "investor_landlord", "str_owner", "perfectionist", "gossip", "repeat_offender"]
const TRAIT_BLURBS := {
	"friendly": "Waves at everyone, including the inspector.",
	"rule_follower": "Has read the declaration. Twice.",
	"chronic_complainer": "Files complaints the way others check email.",
	"board_insider": "Sits close to the board and expects a favor now and then.",
	"anti_hoa": "Believes the HOA is a conspiracy with a newsletter.",
	"litigious": "Knows a lawyer. Is a lawyer. Is dating a lawyer.",
	"elderly": "Has lived here since the cul-de-sac was a field.",
	"new_homeowner": "Still has the moving boxes and the optimism.",
	"investor_landlord": "Owns it, doesn't live in it, and answers by email.",
	"str_owner": "Guests arrive with suitcases and leave with reviews.",
	"perfectionist": "Their lawn has been ruled and measured by themselves.",
	"gossip": "Everything you do is common knowledge by dinner.",
	"repeat_offender": "The file is thick and the excuses are creative.",
}


func create(count: int) -> Dictionary:
	var result := {}
	for house in count:
		var rng := RandomNumberGenerator.new()
		rng.seed = house * 4099 + 17
		var traits: Array = []
		while traits.size() < 1 + (1 if rng.randf() < 0.45 else 0):
			var t: String = TRAITS[rng.randi() % TRAITS.size()]
			if not t in traits:
				traits.append(t)
		var rel := 0
		if "friendly" in traits:
			rel += 25
		if "anti_hoa" in traits:
			rel -= 30
		if "board_insider" in traits:
			rel += 10
		if "litigious" in traits:
			rel -= 10
		result[house] = {
			"owner": "%s %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], LAST_NAMES[rng.randi() % LAST_NAMES.size()]],
			"traits": traits,
			"relationship": rel,
			"repeat_count": 0,
			"history": [],
			"memory": [],
			"compliance": 55 + rng.randi() % 36,
			"seat": house % 5 if "board_insider" in traits else -1,
		}
	return result


## Fills fields added after older saves so loading never breaks.
func migrate(properties: Dictionary, count: int) -> Dictionary:
	var fresh := create(count)
	for house in fresh:
		if not properties.has(house):
			properties[house] = fresh[house]
			continue
		var p: Dictionary = properties[house]
		for key in ["traits", "relationship", "memory", "seat", "compliance"]:
			if not p.has(key) or (key == "relationship" and typeof(p[key]) == TYPE_STRING):
				p[key] = fresh[house][key]
		p.erase("address")
		properties[house] = p
	return properties


static func has_trait(property: Dictionary, trait_name: String) -> bool:
	return trait_name in (property.get("traits", []) as Array)


static func relationship_label(score: int) -> String:
	if score <= -60:
		return "Hostile"
	if score <= -20:
		return "Unfriendly"
	if score < 20:
		return "Neutral"
	if score < 60:
		return "Friendly"
	return "Supporter"


## Coarse political grouping used by the selective-enforcement tracker.
static func group(property: Dictionary) -> String:
	if has_trait(property, "board_insider"):
		return "board"
	if has_trait(property, "litigious"):
		return "legal"
	var rel: int = int(property.get("relationship", 0))
	if has_trait(property, "anti_hoa") or has_trait(property, "chronic_complainer") or rel <= -25:
		return "critic"
	if rel >= 25 or has_trait(property, "friendly"):
		return "friend"
	return "neutral"


static func shift(property: Dictionary, delta: int, day: int, reason: String) -> void:
	property.relationship = clampi(int(property.get("relationship", 0)) + delta, -100, 100)
	var memory: Array = property.get("memory", [])
	memory.append({"day": day, "why": reason, "delta": delta})
	if memory.size() > 6:
		memory.pop_front()
	property.memory = memory


## Chance the household cures a notice on its own.
static func compliance_chance(property: Dictionary, bonus := 0) -> int:
	var chance: int = int(property.get("compliance", 60)) + bonus
	chance += int(int(property.get("relationship", 0)) * 0.2)
	chance -= 8 * int(property.get("repeat_count", 0))
	if has_trait(property, "rule_follower"):
		chance += 15
	if has_trait(property, "perfectionist"):
		chance += 10
	if has_trait(property, "anti_hoa"):
		chance -= 15
	if has_trait(property, "investor_landlord"):
		chance -= 8
	if has_trait(property, "repeat_offender"):
		chance -= 15
	if has_trait(property, "elderly"):
		chance -= 5
	return clampi(chance, 8, 95)


## Chance the household disputes a notice, before evidence is considered.
static func dispute_chance(property: Dictionary) -> float:
	var chance := 0.12
	if has_trait(property, "litigious"):
		chance += 0.25
	if has_trait(property, "anti_hoa"):
		chance += 0.12
	if int(property.get("relationship", 0)) < -20:
		chance += 0.1
	if has_trait(property, "friendly"):
		chance -= 0.06
	if has_trait(property, "new_homeowner"):
		chance -= 0.04
	return clampf(chance, 0.02, 0.7)
