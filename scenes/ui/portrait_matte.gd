extends RefCounted
## Source-preserving UI matte. Only near-white pixels reachable from the image
## border become background; closed white feathers, armour and blade faces stay.
## No disk image is changed. Prepare/cache before menu; never call from hover.
const WHITE_FLOOR := 244
const WHITE_CHROMA := 10
static var generation_count := 0

static func prepare(source: Texture2D, debug_mask: bool = false, interior_regions: Dictionary = {}, battle_regions: Dictionary = {}) -> Dictionary:
	if source == null:
		return {}
	var image := source.get_image()
	if image == null or image.is_empty():
		return {}
	image.convert(Image.FORMAT_RGBA8)
	var dimensions := image.get_size()
	var width := dimensions.x
	var height := dimensions.y
	var count := width * height
	var pixels := image.get_data()
	var candidates := PackedByteArray()
	candidates.resize(count)
	for at in range(count):
		candidates[at] = 1 if _background_candidate(pixels, at) else 0
	var background := PackedByteArray()
	background.resize(count)
	var queue := PackedInt32Array()
	queue.resize(count)
	var tail := 0
	for y in range(height):
		for x in range(width):
			if x != 0 and y != 0 and x != width - 1 and y != height - 1:
				continue
			var at := y * width + x
			if candidates[at] != 0:
				background[at] = 1
				queue[tail] = at
				tail += 1
	var head := 0
	while head < tail:
		var at := queue[head]
		head += 1
		var x := at % width
		for next in [at - width, at + width, at - 1 if x > 0 else -1, at + 1 if x < width - 1 else -1]:
			if next < 0 or next >= count or background[next] != 0 or candidates[next] == 0:
				continue
			background[next] = 1
			queue[tail] = next
			tail += 1
	var exterior_tail := tail
	tail = _mark_interior(pixels, width, height, candidates, background, queue, tail, interior_regions)
	var interior_pixels := tail - exterior_tail
	# Antialiased edge pixels were composited onto white by the source render.
	# Recover their coverage from a nearby opaque contour; leave the source core
	# and every enclosed near-white detail byte-for-byte intact.
	var original := pixels.duplicate()
	var softened_edges := 0
	for at in range(count):
		if background[at] != 0 or candidates[at] != 0:
			continue
		var offset := at * 4
		var low := mini(original[offset], mini(original[offset + 1], original[offset + 2]))
		if low < 170 or not _touches_background(at, width, height, background):
			continue
		var x := at % width
		var y := at / width
		var reference := -1
		var darkest := low
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var nx := x + dx
				var ny := y + dy
				if nx < 0 or ny < 0 or nx >= width or ny >= height:
					continue
				var next := ny * width + nx
				if background[next] != 0 or _touches_background(next, width, height, background):
					continue
				var sample := next * 4
				var value := mini(original[sample], mini(original[sample + 1], original[sample + 2]))
				if value < darkest - 12:
					darkest = value
					reference = sample
		if reference < 0:
			continue
		var coverage := 0.0
		for channel in range(3):
			coverage = maxf(coverage, float(255 - original[offset + channel]) / maxf(1.0, 255 - original[reference + channel]))
		coverage = clampf(coverage, 0.05, 1.0)
		if coverage >= 0.98:
			continue
		for channel in range(3):
			pixels[offset + channel] = clampi(roundi((float(original[offset + channel]) - 255.0 * (1.0 - coverage)) / coverage), 0, 255)
		pixels[offset + 3] = roundi(float(original[offset + 3]) * coverage)
		softened_edges += 1
	var retained_white := 0
	var mask := PackedByteArray()
	if debug_mask:
		mask.resize(count * 4)
	for at in range(count):
		var offset := at * 4
		if background[at] != 0:
			pixels[offset + 3] = 0
		elif candidates[at] != 0:
			retained_white += 1
		if debug_mask:
			var alpha := pixels[offset + 3]
			for channel in range(3):
				mask[offset + channel] = alpha
			mask[offset + 3] = 255
	var result := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, pixels)
	var battle_texture: Texture2D
	var battle_tail := _mark_interior(original, width, height, candidates, background, queue, tail, battle_regions)
	if battle_tail > tail:
		# The battle shader handles the new boundary. Share the base matte's
		# segmentation and leave every pixel outside the reviewed gaps intact.
		var battle_pixels := pixels.duplicate()
		for index in range(tail, battle_tail):
			battle_pixels[queue[index] * 4 + 3] = 0
		battle_texture = ImageTexture.create_from_image(Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, battle_pixels))
	generation_count += 1
	return {"texture": ImageTexture.create_from_image(result), "battle_texture": battle_texture, "mask": ImageTexture.create_from_image(Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, mask)) if debug_mask else null, "background_pixels": tail, "interior_background_pixels": interior_pixels, "softened_edge_pixels": softened_edges, "retained_closed_white_pixels": retained_white, "source_pixels": count, "policy": "border-connected neutral near-white; closed white preserved; source core unchanged; only white-matted contour coverage recovered"}


static func _mark_interior(pixels: PackedByteArray, width: int, height: int, candidates: PackedByteArray, background: PackedByteArray, queue: PackedInt32Array, tail: int, regions: Dictionary) -> int:
	var count := width * height
	if not regions.is_empty():
		var fingerprint := HashingContext.new()
		fingerprint.start(HashingContext.HASH_SHA256)
		fingerprint.update(pixels)
		if fingerprint.finish().hex_encode() != String(regions.rgba_sha256):
			push_error("Portrait source changed: reviewed interior background seeds were not applied")
		else:
			for component: Dictionary in regions.components:
				var seed: Vector2i = component.seed
				if seed.x < 0 or seed.y < 0 or seed.x >= width or seed.y >= height:
					push_error("Portrait interior background seed outside source")
					continue
				var start := tail
				var seed_at := seed.y * width + seed.x
				if candidates[seed_at] == 0 or background[seed_at] != 0:
					push_error("Portrait interior seed no longer identifies enclosed neutral background")
					continue
				background[seed_at] = 1
				queue[tail] = seed_at
				tail += 1
				var head := start
				while head < tail:
					var at := queue[head]
					head += 1
					var x := at % width
					for next in [at - width, at + width, at - 1 if x > 0 else -1, at + 1 if x < width - 1 else -1]:
						if next < 0 or next >= count or background[next] != 0 or candidates[next] == 0:
							continue
						background[next] = 1
						queue[tail] = next
						tail += 1
				if tail - start != int(component.pixels):
					for index in range(start, tail):
						background[queue[index]] = 0
					tail = start
					push_error("Portrait interior component changed: source pixels preserved")
	return tail


static func _background_candidate(pixels: PackedByteArray, at: int) -> bool:
	var offset := at * 4
	var low := mini(pixels[offset], mini(pixels[offset + 1], pixels[offset + 2]))
	var high := maxi(pixels[offset], maxi(pixels[offset + 1], pixels[offset + 2]))
	return low >= WHITE_FLOOR and high - low <= WHITE_CHROMA

static func _touches_background(at: int, width: int, height: int, background: PackedByteArray) -> bool:
	var x := at % width
	var y := at / width
	return (x > 0 and background[at - 1] != 0) or (x < width - 1 and background[at + 1] != 0) or (y > 0 and background[at - width] != 0) or (y < height - 1 and background[at + width] != 0)
