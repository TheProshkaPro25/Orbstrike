extends RefCounted
## Общие низкополигональные детали внешних арен. Только декор; MultiMesh собирает Arena.
static func material(color: Color, roughness: float = .8, metal: float = .0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metal
	return m

static func piece(arena: Node3D, mesh: Mesh, mat: Material, center: Vector3, yaw: float, p: Vector3, size: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var basis := Basis(Vector3.UP,yaw)
	arena._static(mesh,mat,center+basis*p,size,(basis*Basis.from_euler(rot)).get_euler())

static func beam(arena: Node3D, mesh: Mesh, mat: Material, a: Vector3, b: Vector3, width: float) -> void:
	var delta := b-a
	arena._static(mesh,mat,(a+b)*.5,Vector3(width,delta.length(),width),Basis(Quaternion(Vector3.UP,delta.normalized())).get_euler())

static func ring(arena: Node3D, mat: Material, radius: float, y: float, width: float) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius-width
	mesh.outer_radius = radius+width
	mesh.rings = 128
	mesh.ring_segments = 6
	arena._mi(mesh,mat,Vector3(0,y,0))

static func rod(segments: int = 10) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1
	mesh.bottom_radius = 1
	mesh.height = 1
	mesh.radial_segments = segments
	return mesh

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for p in [a,b,c,a,c,d]: st.add_vertex(p)

## Объёмный полукруглый архивольт, без перекрывающей проём плоскости.
static func arch(radius: float, thickness: float, depth: float, segments: int = 24) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a := PI*i/segments
		var b := PI*(i+1)/segments
		var p := Vector2(cos(a),sin(a))
		var q := Vector2(cos(b),sin(b))
		var r := radius+thickness
		var f := depth*.5
		_quad(st,Vector3(p.x*radius,p.y*radius,f),Vector3(p.x*r,p.y*r,f),Vector3(q.x*r,q.y*r,f),Vector3(q.x*radius,q.y*radius,f))
		_quad(st,Vector3(q.x*radius,q.y*radius,-f),Vector3(q.x*r,q.y*r,-f),Vector3(p.x*r,p.y*r,-f),Vector3(p.x*radius,p.y*radius,-f))
		_quad(st,Vector3(p.x*r,p.y*r,f),Vector3(p.x*r,p.y*r,-f),Vector3(q.x*r,q.y*r,-f),Vector3(q.x*r,q.y*r,f))
		_quad(st,Vector3(q.x*radius,q.y*radius,f),Vector3(q.x*radius,q.y*radius,-f),Vector3(p.x*radius,p.y*radius,-f),Vector3(p.x*radius,p.y*radius,f))
	# Плоские опоры полукольца тоже имеют объём: с торца не видно внутрь свода.
	for side in [1.0,-1.0]:
		var inner: float = side*radius
		var outer: float = side*(radius+thickness)
		var f := depth*.5
		if side > 0:
			_quad(st,Vector3(outer,0,f),Vector3(inner,0,f),Vector3(inner,0,-f),Vector3(outer,0,-f))
		else:
			_quad(st,Vector3(inner,0,f),Vector3(outer,0,f),Vector3(outer,0,-f),Vector3(inner,0,-f))
	st.generate_normals()
	return st.commit()

## Лодочный корпус: узкие заострённые концы, борт и киль, без прозрачных оболочек.
static func hull() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	var inner: Array[Vector3] = []
	for i in 16:
		var a := TAU*i/16.0
		top.append(Vector3(cos(a)*3.8,2.1,sin(a)*10.5))
		bottom.append(Vector3(cos(a)*2.4,.3,sin(a)*8.0))
		inner.append(Vector3(cos(a)*3.55,1.88,sin(a)*10.17))
	for i in 16:
		var j := (i+1)%16
		_quad(st,top[i],bottom[i],bottom[j],top[j])
		_quad(st,top[j],inner[j],inner[i],top[i])
		_quad(st,inner[j],Vector3(inner[j].x*.70,.55,inner[j].z*.80),Vector3(inner[i].x*.70,.55,inner[i].z*.80),inner[i])
		for p in [Vector3(0,.3,0),bottom[j],bottom[i]]: st.add_vertex(p)
		for p in [Vector3(0,.55,0),Vector3(inner[i].x*.70,.55,inner[i].z*.80),Vector3(inner[j].x*.70,.55,inner[j].z*.80)]: st.add_vertex(p)
	st.generate_normals()
	return st.commit()
