extends RefCounted
## Saved location 3; the former illustrated experiment is retained only as source history.
const LOCATION := 3
const NAME := "Каменная бухта"
const DESCRIPTION := "Зелёный архипелаг, морской маяк и светлая площадка среди прозрачных проливов."
static func applies(location: int) -> bool:
	return location == LOCATION
