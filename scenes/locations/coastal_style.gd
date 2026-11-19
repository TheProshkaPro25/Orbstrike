extends RefCounted
## Saved location 3; the former illustrated experiment is retained only as source history.
const LOCATION := 3
const NAME := "Каменная бухта"
const DESCRIPTION := "Зелёный архипелаг, морской маяк и светлая площадка среди прозрачных проливов."
const SUN_ROTATION := Vector3(-48, -30, 0)
# Authored x, z, radii, yaw and seed. Build in these coordinates to keep each
# island, its vegetation, terrain textures and contact shadows together.
const ISLANDS := [
	[-400,-255,245,146,-.45,0],[257,-398,184,123,.34,1],[-40,-675,250,116,-.55,2],
	[652,-191,258,154,-.32,3],[-615,182,267,141,.71,4],[572,380,194,122,.12,5],
	[-245,509,211,163,-.17,6],[93,761,191,104,-.17,7],[468,-775,151,87,.28,8],
	[1019,-480,173,97,-.64,9],[-956,-594,263,103,.38,10],[-804,672,228,163,-.28,11],
	[1043,575,291,121,.78,12],[1128,113,90,52,.15,13],[-1088,-42,125,56,.35,14],
	[869,-993,258,109,.41,15],[-333,-1138,316,167,.13,16],[224,-1200,216,120,1.04,17],
	[-1200,966,204,123,.22,18],[588,980,214,111,-.46,19],[-308,1070,141,84,.18,20],
	[994,1098,103,102,.6,21],[278,233,57,32,-.45,22],[-211,227,54,38,-.37,23],
	[-194,-328,31,21,-.47,24],[131,-263,50,38,-.41,25],[338,79,75,39,.31,26],
	[-413,184,58,30,.25,27],[307,-622,66,34,-.91,28],[547,622,72,26,-.11,29],
]

# Enlarge the inner straits; cap the displacement of the distant island belt
# so its silhouette remains inside the existing sea and camera horizon.
const ISLAND_SPACING := .45
const MAX_ISLAND_OFFSET := 430.0

static func island_offset(index: int) -> Vector3:
	var island: Array = ISLANDS[index]
	var center := Vector3(island[0],0.0,island[1])
	return (center*ISLAND_SPACING).limit_length(MAX_ISLAND_OFFSET)


static func applies(location: int) -> bool:
	return location == LOCATION


static func direction_to_sun() -> Vector3:
	return Basis.from_euler(SUN_ROTATION * (PI / 180.0)).z
