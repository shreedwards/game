package island

import "core:math"
import "core:math/rand"

import rl "vendor:raylib"

import "../collision"

// Seed offset for the island's tree: added to the island seed so the tree is
// decorrelated from the ground's noise layers but still fully determined by
// the one island seed.
TREE_SEED :: 7

// Texel size in world units. Tree UVs are always world distances divided by
// the swatch's world size (SWATCH_RES texels), never stretched to fit a face:
// texels stay the same size no matter how big a face is, and each face just
// crops its window out of the (repeating) swatch.
BARK_TEXEL :: 0.05 // world units per bark texel
LEAF_TEXEL :: 0.05 // world units per leaf texel

Tree :: struct {
	leaves: rl.Model,
	trunk: rl.Model,
	tris: [dynamic]collision.Triangle
}

@(private="file")
MAX_NODES :: 4

@(private="file")
MAX_CHILDREN :: 2

@(private="file")
SPLIT_CHANCE :: 0.5

@(private="file")
MIN_LENGTH :: 2.0

@(private="file")
MAX_LENGTH :: 4.0

// Depth weighting for branch length: the random MIN_LENGTH..MAX_LENGTH is scaled
// by a factor blended from TRUNK_LENGTH_SCALE at the root to TIP_LENGTH_SCALE at
// the tips. Biasing the tip factor above the trunk factor moves length out of
// the trunk and into the upper branches.
@(private="file")
TRUNK_LENGTH_SCALE :: 0.8

@(private="file")
TIP_LENGTH_SCALE :: 1.0

// Trunk radius at the root; branches taper toward the tips with depth.
@(private="file")
BASE_RADIUS :: 1.0

// Number of sides on each branch ring.
@(private="file")
SIDES :: 8

// How far the primary (continuing) child may bend off the parent heading.
@(private="file")
PRIMARY_BEND :: 0.2

// Angular range the secondary child forks away from the parent heading.
@(private="file")
FORK_MIN :: 0.3
@(private="file")
FORK_MAX :: 0.6

// Secondary branches are thinner than the primary continuation.
@(private="file")
SECONDARY_RADIUS :: 0.7

// Lower bound on cos(half-angle) when mitering a ring, so sharp turns don't
// blow the corrected radius up to infinity.
@(private="file")
MITER_MIN :: 0.5

// Leaf hemisphere radius as a random multiple of the branch tip radius.
@(private="file")
LEAF_MIN_SCALE :: 15.0
@(private="file")
LEAF_MAX_SCALE :: 20.0

// Latitude bands on each leaf hemisphere (longitude reuses SIDES).
@(private="file")
LEAF_STACKS :: 4

Node :: struct {
	position:   rl.Vector3,
	radius:     f32,
	leaf_scale: f32, // random leaf size for this node's tip, drawn at gen time
	children:   [MAX_CHILDREN]^Node
}

// Grows a tree from `seed` and returns it ready to place: bark (trunk/branch
// tubes) and leaves (canopy domes) as two uploaded models, plus the tree's
// collision tris in tree-LOCAL space (the caller offsets them to the tree's
// world position). They are separate models so the leaves can render with the
// alpha-cutout leaf shader (and the leaf swatch) while the bark stays opaque
// (with the bark swatch); wiring those materials up is the caller's job. The
// intermediate node graph is built, skinned, and freed internally, so callers
// only make this one call. The same seed always yields the same tree.
create_tree :: proc(seed: u64) -> Tree {
	root := _grow_tree(seed)
	defer _free_tree(root)

	bark_mesh, leaf_mesh := _tree_mesh(root)

	tree := Tree {
		trunk  = rl.LoadModelFromMesh(bark_mesh),
		leaves = rl.LoadModelFromMesh(leaf_mesh)
	}

	collision.append_mesh_tris(&tree.tris, bark_mesh, rl.Vector3 { })
	collision.append_mesh_tris(&tree.tris, leaf_mesh, rl.Vector3 { })

	return tree
}

// Builds the node graph for `seed`. A seeded generator is installed into the
// context so every random draw during generation (_branch, _length, _deviate,
// _leaf_scale) is deterministic, without touching the program-wide default RNG.
@(private="file")
_grow_tree :: proc(seed: u64) -> ^Node {
	state := rand.create_u64(seed)
	context.random_generator = rand.default_random_generator(&state)

	root := new_clone(Node {
		position   = { 0.0, 0.0, 0.0 },
		radius     = _radius(0),
		leaf_scale = _leaf_scale()
	})

	_branch(root, { 0.0, 1.0, 0.0 }, 0)

	return root
}

// Recursively frees every node in the graph.
@(private="file")
_free_tree :: proc(root: ^Node) {
	if root == nil {
		return
	}

	for child in root.children {
		_free_tree(child)
	}

	free(root)
}

// Grows the tree from `root`, which is heading in unit direction `dir`. The
// primary child (children[0]) continues roughly along `dir` so it reads as the
// main branch; the secondary child (children[1]) forks off at a wide angle on
// the opposite side and is treated as a separate branch by the mesher.
@(private="file")
_branch :: proc(root:^Node, dir:rl.Vector3, count:int) {

	if count >= MAX_NODES {
		return
	}

	length := _length(count)

	// Random azimuth for the bend/fork plane around the current heading.
	azimuth := rand.float32_range(0.0, 2.0 * math.PI)

	// Primary: small deviation from the parent heading -> continuous trunk.
	bend := rand.float32_range(0.0, PRIMARY_BEND)
	primary_dir := _deviate(dir, bend, azimuth)

	primary_child := new_clone(Node {
		position   = root.position + primary_dir * length,
		radius     = _radius(count + 1),
		leaf_scale = _leaf_scale()
	})

	root.children[0] = primary_child

	_branch(primary_child, primary_dir, count + 1)

	// The root (node 0) never forks: it only grows the trunk straight up.
	// Forking begins at node 1 and above.
	if count > 0 && rand.float32() >= SPLIT_CHANCE {
		// Secondary: real fork, wide angle off the heading and on the opposite
		// side from the primary bend so the two branches swing clear.
		fork := rand.float32_range(FORK_MIN, FORK_MAX)
		secondary_dir := _deviate(dir, fork, azimuth + math.PI)

		secondary_child := new_clone(Node {
			position   = root.position + secondary_dir * length,
			radius     = _radius(count + 1) * SECONDARY_RADIUS,
			leaf_scale = _leaf_scale()
		})

		root.children[1] = secondary_child

		_branch(secondary_child, secondary_dir, count + 1)
	}
}

// Random branch length, weighted by depth so the upper branches get more length
// than the trunk (see TRUNK_LENGTH_SCALE / TIP_LENGTH_SCALE).
@(private="file")
_length :: proc(count: int) -> f32 {
	t := f32(count) / f32(MAX_NODES) // 0 at the root .. toward 1 at the tips
	scale := TRUNK_LENGTH_SCALE + (TIP_LENGTH_SCALE - TRUNK_LENGTH_SCALE) * t
	return rand.float32_range(MIN_LENGTH, MAX_LENGTH) * scale
}

// Random leaf-size multiple, drawn during (seeded) generation so leaf sizes are
// part of the deterministic tree rather than re-rolled at mesh time.
@(private="file")
_leaf_scale :: proc() -> f32 {
	return rand.float32_range(LEAF_MIN_SCALE, LEAF_MAX_SCALE)
}

// Rotates `dir` by polar angle `theta` away from itself, around the azimuth
// `phi` in the plane perpendicular to `dir`. Returns a unit vector.
@(private="file")
_deviate :: proc(dir: rl.Vector3, theta: f32, phi: f32) -> rl.Vector3 {
	right, forward := _basis(dir)
	radial := right * math.cos(phi) + forward * math.sin(phi)
	return rl.Vector3Normalize(dir * math.cos(theta) + radial * math.sin(theta))
}

// An arbitrary orthonormal basis in the plane perpendicular to `axis`.
@(private="file")
_basis :: proc(axis: rl.Vector3) -> (right: rl.Vector3, forward: rl.Vector3) {
	helper := rl.Vector3 { 0, 1, 0 }
	if abs(axis.y) > 0.99 {
		helper = rl.Vector3 { 1, 0, 0 }
	}
	right = rl.Vector3Normalize(rl.Vector3CrossProduct(helper, axis))
	forward = rl.Vector3CrossProduct(axis, right)
	return
}

// Branch radius for a node at the given depth: thickest at the root, tapering
// toward the tips but never collapsing to zero (so tip rings stay valid).
@(private="file")
_radius :: proc(count: int) -> f32 {
	return BASE_RADIUS * f32(MAX_NODES + 1 - count) / f32(MAX_NODES + 1)
}

// Vertex/index streams for one mesh under construction. Follows the same
// manual buffer-building convention as _island_mesh.
@(private="file")
_Buffers :: struct {
	vertices:  [dynamic]f32,
	texcoords: [dynamic]f32,
	normals:   [dynamic]f32,
	indices:   [dynamic]u16
}

@(private="file")
_upload_mesh :: proc(b: ^_Buffers) -> rl.Mesh {
	mesh := rl.Mesh {
		vertexCount   = i32(len(b.vertices) / 3),
		triangleCount = i32(len(b.indices) / 3),

		vertices  = raw_data(b.vertices),
		texcoords = raw_data(b.texcoords),
		normals   = raw_data(b.normals),
		indices   = raw_data(b.indices)
	}

	rl.UploadMesh(&mesh, false)

	return mesh
}

// Builds and uploads the tree's two meshes: bark tubes and leaf domes. The
// tree is split into spines (a node plus its chain of primary children); each
// spine is skinned as one continuous tube so joints along the main branch are
// seamless. Secondary forks are separate spines whose base is embedded inside
// the parent tube, so they read as branches colliding into and through the
// main branch.
@(private="file")
_tree_mesh :: proc(root: ^Node) -> (bark_mesh: rl.Mesh, leaf_mesh: rl.Mesh) {
	bark : _Buffers
	leaf : _Buffers

	_skin_branch(root, nil, &bark, &leaf)

	return _upload_mesh(&bark), _upload_mesh(&leaf)
}

// Skins the spine that starts at `start` and follows the primary-child chain,
// then recurses into every secondary fork found along it. When `parent` is set
// (a fork), the spine gets an extra base point pushed back inside the parent
// tube so its open end is hidden and it overlaps the main branch.
@(private="file")
_skin_branch :: proc(start: ^Node, parent: ^Node, bark: ^_Buffers, leaf: ^_Buffers) {
	if start == nil {
		return
	}

	// Collect the chain of nodes along the primary children.
	nodes : [dynamic]^Node
	defer delete(nodes)

	for n := start; n != nil; n = n.children[0] {
		append(&nodes, n)
	}

	// Build the polyline (points + radii) to skin.
	points : [dynamic]rl.Vector3
	radii  : [dynamic]f32
	defer delete(points)
	defer delete(radii)

	if parent != nil {
		// Embed the base inside the parent tube, behind the fork node.
		first_dir := rl.Vector3Normalize(start.position - parent.position)
		append(&points, parent.position - first_dir * 0.3 * parent.radius)
		append(&radii, start.radius)
	}

	for n in nodes {
		append(&points, n.position)
		append(&radii, n.radius)
	}

	_skin_tube(points[:], radii[:], bark)

	// Cap this branch's tip with a leaf hemisphere, facing along the tip.
	np := len(points)
	if np >= 2 {
		tip := nodes[len(nodes) - 1]
		tip_dir := rl.Vector3Normalize(points[np - 1] - points[np - 2])
		_append_leaf(points[np - 1], tip_dir, radii[np - 1], tip.leaf_scale, leaf)
	}

	// Every secondary child along the chain starts its own embedded spine.
	for n in nodes {
		_skin_branch(n.children[1], n, bark, leaf)
	}
}

// Appends a hemisphere of foliage at a branch tip: dome centered at `center`,
// bulging along unit `axis` (the branch's outgoing direction). Its radius is the
// branch radius times `leaf_scale` (drawn at generation time), so bigger
// branches get bigger leaves and the size stays deterministic per seed.
//
// Texturing: every quad of the dome gets its own four verts and a flat planar
// mapping of the leaf swatch, anchored to the quad's bottom (lowest-in-world)
// edge - u runs along that edge, v rises perpendicular to it in the face
// plane, so the swatch's leaf rects sit upright with their bottoms parallel to
// the face's bottom edge. UVs are world distances over LEAF_TEXEL, so texel
// size is constant and each face just crops its patch of the swatch.
@(private="file")
_append_leaf :: proc(
	center: rl.Vector3,
	axis: rl.Vector3,
	branch_radius: f32,
	leaf_scale: f32,
	b: ^_Buffers
) {
	radius := branch_radius * leaf_scale
	right, forward := _basis(axis)

	// Pull the dome center back by one radius so its round apex (pointing
	// outward, away from the branch) lands exactly on the tip. The dome then
	// opens back down over the branch, so the branch enters it and the tip
	// meets the inner apex (the innermost face) instead of floating in a mouth.
	origin := center - axis * radius * 0.9

	tile := f32(SWATCH_RES) * LEAF_TEXEL // world size of one full swatch repeat

	// Dome lattice, rings from the pole (theta 0, pointing outward) down to the
	// equator (theta pi/2), so the branch end touches the innermost face.
	pts  : [LEAF_STACKS + 1][SIDES]rl.Vector3
	dirs : [LEAF_STACKS + 1][SIDES]rl.Vector3

	for st in 0..=LEAF_STACKS {
		theta := f32(st) / f32(LEAF_STACKS) * (math.PI / 2.0)
		for sl in 0..<SIDES {
			phi := f32(sl) / f32(SIDES) * 2.0 * math.PI
			radial := right * math.cos(phi) + forward * math.sin(phi)
			dir := radial * math.sin(theta) + axis * math.cos(theta)

			dirs[st][sl] = dir
			pts[st][sl]  = origin + dir * radius
		}
	}

	for st in 0..<LEAF_STACKS {
		for sl in 0..<SIDES {
			next := (sl + 1) % SIDES

			// Quad corners: p0/p1 on the pole-side ring, p2/p3 on the ring below.
			p0 := pts[st][sl]
			p1 := pts[st][next]
			p2 := pts[st + 1][sl]
			p3 := pts[st + 1][next]

			// Bottom edge = whichever ring edge sits lower in the world. The
			// dome usually points up, making that the equator-side ring, but a
			// tilted branch can flip it.
			bottom0, bottom1 := p2, p3
			top0 := p0
			if p0.y + p1.y < p2.y + p3.y {
				bottom0, bottom1 = p0, p1
				top0 = p2
			}

			// At the pole ring the "edge" is a single point; align to the real
			// (opposite) edge instead.
			if rl.Vector3LengthSqr(bottom1 - bottom0) < 0.0001 {
				bottom0, bottom1, top0 = top0, top0 == p0 ? p1 : p3, bottom0
			}

			// In-face frame anchored on the bottom edge: ex along it, ey away
			// from it toward the top edge, in the face plane.
			ex := rl.Vector3Normalize(bottom1 - bottom0)
			up := top0 - bottom0
			ey := rl.Vector3Normalize(up - ex * rl.Vector3DotProduct(up, ex))

			base := u16(len(b.vertices) / 3)

			quad_p := [4]rl.Vector3 { p0, p1, p2, p3 }
			quad_n := [4]rl.Vector3 { dirs[st][sl], dirs[st][next], dirs[st + 1][sl], dirs[st + 1][next] }

			for k in 0..<4 {
				p := quad_p[k]
				n := quad_n[k]
				rel := p - bottom0

				append(&b.vertices, p.x, p.y, p.z)
				append(&b.normals, n.x, n.y, n.z)
				append(&b.texcoords,
					rl.Vector3DotProduct(rel, ex) / tile,
					rl.Vector3DotProduct(rel, ey) / tile)
			}

			// Wound CCW so the dome faces outward (same winding as the old
			// shared-vertex quads).
			append(&b.indices, base, base + 2, base + 3)
			append(&b.indices, base, base + 3, base + 1)
		}
	}
}

// Skins a polyline of `points` (with per-point `radii`) into a continuous tube:
// one ring of SIDES+1 verts per point (the last duplicates the first so the
// texture can wrap), connected point-to-point. A parallel-transported frame
// keeps rings from twisting, and interior rings are mitered (oriented on the
// bend bisector, radius scaled by 1/cos) so corners stay flush.
//
// Texturing: v is the accumulated world arc length along the spine, so the
// bark swatch's vertical grain runs down the branch; u is the world distance
// walked around the ring's actual circumference. Both are divided by the
// swatch's world size (BARK_TEXEL per texel), so texel size is constant
// regardless of branch girth or segment length - faces crop, never stretch.
@(private="file")
_skin_tube :: proc(points: []rl.Vector3, radii: []f32, b: ^_Buffers) {
	n := len(points)
	if n < 2 {
		return
	}

	tile := f32(SWATCH_RES) * BARK_TEXEL // world size of one full swatch repeat

	prev_tan  : rl.Vector3
	right     : rl.Vector3
	prev_base : u16
	along     : f32 // world arc length from the spine base

	for i in 0..<n {
		// Tangent: segment direction at the ends, bend bisector in between.
		tan : rl.Vector3
		switch {
		case i == 0:
			tan = rl.Vector3Normalize(points[1] - points[0])
		case i == n - 1:
			tan = rl.Vector3Normalize(points[i] - points[i - 1])
		case:
			d0 := rl.Vector3Normalize(points[i] - points[i - 1])
			d1 := rl.Vector3Normalize(points[i + 1] - points[i])
			tan = d0 + d1
			tan = rl.Vector3Length(tan) < 0.0001 ? d1 : rl.Vector3Normalize(tan)
		}

		// Parallel-transport the frame from the previous ring to avoid twist.
		if i == 0 {
			right, _ = _basis(tan)
		} else {
			right = _rotate_between(right, prev_tan, tan)
			right = rl.Vector3Normalize(right - tan * rl.Vector3DotProduct(right, tan))
		}
		up := rl.Vector3Normalize(rl.Vector3CrossProduct(tan, right))

		// Miter: widen interior rings so the bend is covered without pinching.
		r := radii[i]
		if i != 0 && i != n - 1 {
			in_dir := rl.Vector3Normalize(points[i] - points[i - 1])
			cos_half := max(rl.Vector3DotProduct(tan, in_dir), MITER_MIN)
			r /= cos_half
		}

		if i > 0 {
			along += rl.Vector3Length(points[i] - points[i - 1])
		}

		base := u16(len(b.vertices) / 3)

		// One ring of SIDES+1 verts; the seam vert repeats the first position
		// with the full-circumference u so the swatch wraps around the ring.
		circumference := 2.0 * math.PI * r
		for j in 0..=SIDES {
			angle := f32(j) / f32(SIDES) * 2.0 * math.PI
			dir := right * math.cos(angle) + up * math.sin(angle)
			p := points[i] + dir * r

			append(&b.vertices, p.x, p.y, p.z)
			append(&b.normals, dir.x, dir.y, dir.z)
			append(&b.texcoords, f32(j) / f32(SIDES) * circumference / tile, along / tile)
		}

		if i > 0 {
			for j in 0..<SIDES {
				bi := prev_base + u16(j)
				bn := prev_base + u16(j + 1)
				ti := base + u16(j)
				tn := base + u16(j + 1)

				// Two triangles per side quad, wound CCW so faces point out.
				append(&b.indices, bi, bn, tn)
				append(&b.indices, bi, tn, ti)
			}
		}

		prev_tan  = tan
		prev_base = base
	}
}

// Rotates `v` by the minimal rotation that carries unit vector `from` onto unit
// vector `to` (Rodrigues' formula). Used to parallel-transport the ring frame.
@(private="file")
_rotate_between :: proc(v: rl.Vector3, from: rl.Vector3, to: rl.Vector3) -> rl.Vector3 {
	axis := rl.Vector3CrossProduct(from, to)
	s := rl.Vector3Length(axis)
	c := rl.Vector3DotProduct(from, to)

	if s < 0.0001 {
		return v // parallel: no rotation needed
	}
	axis = axis / s

	// cos(angle) = c, sin(angle) = s for unit from/to.
	return v * c + rl.Vector3CrossProduct(axis, v) * s + axis * rl.Vector3DotProduct(axis, v) * (1.0 - c)
}
