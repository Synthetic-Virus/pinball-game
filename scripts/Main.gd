extends Node3D
## Gray-box 3D pinball. ORIGINAL generic table of primitives.
## Tilted playfield: gravity rolls the ball toward the flipper (near) end.
## Controls: LEFT flipper = A / Left-Arrow, RIGHT flipper = D / Right-Arrow.
## Plunger: HOLD Space to charge the power meter (it oscillates), RELEASE to launch.

const TILT_DEG := 7.0
const HALF_W := 0.26
const NEAR_Z := 0.55
const FAR_Z := -0.55
const BALL_R := 0.013
const WALL_H := 0.05
const FLIP_SPEED := 16.0
const LAUNCH_MIN := 1.3
const LAUNCH_MAX := 3.2
const CHARGE_RATE := 1.7
const VW := 720.0

var score := 0
var balls := 3
var ball_live := false
var charging := false
var power := 0.0
var charge_phase := 0.0
var pf: Node3D
var ball: RigidBody3D
var lflip: AnimatableBody3D
var rflip: AnimatableBody3D
var lbl_score: Label
var lbl_balls: Label
var lbl_msg: Label
var meter_bg: ColorRect
var meter_fill: ColorRect
var ball_start := Vector3(0.215, BALL_R + 0.01, 0.45)

func _ready() -> void:
    _environment()
    _light()
    _camera()
    pf = Node3D.new()
    pf.rotation_degrees = Vector3(TILT_DEG, 0, 0)
    add_child(pf)
    _surface()
    _walls()
    _dome()
    _bumpers()
    lflip = _flipper(Vector3(-0.11, 0.018, 0.44), -0.55, 0.15, false)
    rflip = _flipper(Vector3(0.11, 0.018, 0.44), 0.55, -0.15, true)
    _ball()
    _ui()
    _reset_ball()

func _mat(c: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    m.roughness = 0.6
    return m

func _environment() -> void:
    var we := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.04, 0.05, 0.08)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.65, 0.67, 0.78)
    env.ambient_light_energy = 1.0
    we.environment = env
    add_child(we)

func _light() -> void:
    var l := DirectionalLight3D.new()
    l.rotation_degrees = Vector3(-58, -28, 0)
    l.light_energy = 1.4
    add_child(l)

func _camera() -> void:
    var cam := Camera3D.new()
    cam.fov = 52.0
    cam.position = Vector3(0, 0.62, 1.02)
    add_child(cam)
    cam.look_at(Vector3(0, -0.04, -0.15), Vector3.UP)
    cam.current = true

func _box_body(parent: Node3D, center: Vector3, size: Vector3, c: Color) -> void:
    var b := StaticBody3D.new()
    var col := CollisionShape3D.new()
    var bs := BoxShape3D.new()
    bs.size = size
    col.shape = bs
    b.add_child(col)
    var mi := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = size
    mi.mesh = bm
    mi.material_override = _mat(c)
    b.add_child(mi)
    b.position = center
    parent.add_child(b)

func _seg_wall(a: Vector3, b: Vector3) -> void:
    var mid := (a + b) * 0.5
    var length := (b - a).length()
    if length < 0.001:
        return
    var body := StaticBody3D.new()
    var col := CollisionShape3D.new()
    var bs := BoxShape3D.new()
    bs.size = Vector3(length, WALL_H, 0.02)
    col.shape = bs
    body.add_child(col)
    var mi := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = Vector3(length, WALL_H, 0.02)
    mi.mesh = bm
    mi.material_override = _mat(Color(0.30, 0.40, 0.60))
    body.add_child(mi)
    body.position = mid
    body.rotation.y = atan2(-(b.z - a.z), b.x - a.x)
    pf.add_child(body)

func _surface() -> void:
    _box_body(pf, Vector3(0, -0.01, 0), Vector3(HALF_W * 2.0, 0.02, 1.1), Color(0.10, 0.12, 0.18))

func _walls() -> void:
    var h := WALL_H
    _box_body(pf, Vector3(-HALF_W, h / 2.0, 0), Vector3(0.02, h, 1.1), Color(0.30, 0.40, 0.60))
    _box_body(pf, Vector3(HALF_W, h / 2.0, 0), Vector3(0.02, h, 1.1), Color(0.30, 0.40, 0.60))
    _box_body(pf, Vector3(0.17, h / 2.0, 0.1), Vector3(0.02, h, 0.9), Color(0.30, 0.40, 0.60))
    _box_body(pf, Vector3(-0.175, h / 2.0, NEAR_Z), Vector3(0.17, h, 0.02), Color(0.30, 0.40, 0.60))
    _box_body(pf, Vector3(0.175, h / 2.0, NEAR_Z), Vector3(0.17, h, 0.02), Color(0.30, 0.40, 0.60))

func _dome() -> void:
    # Rounded top arch: ball launched up the right lane follows the curve into the playfield.
    var rx := 0.255
    var rz := 0.18
    var cz := -0.30
    var n := 12
    var pts := PackedVector3Array()
    for i in n + 1:
        var ang := PI * float(i) / float(n)
        pts.append(Vector3(rx * cos(ang), WALL_H / 2.0, cz - rz * sin(ang)))
    for i in pts.size() - 1:
        _seg_wall(pts[i], pts[i + 1])

func _bumpers() -> void:
    for c in [Vector3(-0.10, 0, -0.18), Vector3(0.06, 0, -0.28), Vector3(-0.02, 0, 0.02)]:
        var area := Area3D.new()
        var col := CollisionShape3D.new()
        var cyl := CylinderShape3D.new()
        cyl.radius = 0.034
        cyl.height = 0.06
        col.shape = cyl
        area.add_child(col)
        var mi := MeshInstance3D.new()
        var cm := CylinderMesh.new()
        cm.top_radius = 0.034
        cm.bottom_radius = 0.034
        cm.height = 0.06
        mi.mesh = cm
        mi.material_override = _mat(Color(0.90, 0.45, 0.35))
        area.add_child(mi)
        area.position = c + Vector3(0, 0.03, 0)
        var a := area
        area.body_entered.connect(func(b: Node) -> void: _bump(b, a))
        pf.add_child(area)

func _bump(b: Node, area: Area3D) -> void:
    if b != ball:
        return
    score += 100
    _update_ui()
    var d := ball.global_position - area.global_position
    d.y = 0.0
    if d.length() < 0.001:
        d = Vector3(0, 0, 1)
    ball.linear_velocity = d.normalized() * 1.5

func _flipper(pos: Vector3, rest: float, up: float, mirrored: bool) -> AnimatableBody3D:
    var f := AnimatableBody3D.new()
    f.sync_to_physics = true
    f.position = pos
    f.rotation.y = rest
    f.set_meta("rest", rest)
    f.set_meta("up", up)
    var d := -1.0 if mirrored else 1.0
    var size := Vector3(0.11, 0.022, 0.028)
    var col := CollisionShape3D.new()
    var bs := BoxShape3D.new()
    bs.size = size
    col.shape = bs
    col.position = Vector3(0.055 * d, 0, 0)
    f.add_child(col)
    var mi := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = size
    mi.mesh = bm
    mi.position = Vector3(0.055 * d, 0, 0)
    mi.material_override = _mat(Color(0.88, 0.86, 0.40))
    f.add_child(mi)
    pf.add_child(f)
    return f

func _ball() -> void:
    ball = RigidBody3D.new()
    ball.continuous_cd = true
    ball.mass = 0.08
    var pm := PhysicsMaterial.new()
    pm.bounce = 0.15
    pm.friction = 0.4
    ball.physics_material_override = pm
    var col := CollisionShape3D.new()
    var s := SphereShape3D.new()
    s.radius = BALL_R
    col.shape = s
    ball.add_child(col)
    var mi := MeshInstance3D.new()
    var sm := SphereMesh.new()
    sm.radius = BALL_R
    sm.height = BALL_R * 2.0
    mi.mesh = sm
    mi.material_override = _mat(Color(0.85, 0.92, 1.0))
    ball.add_child(mi)
    pf.add_child(ball)
    var drain := Area3D.new()
    var dc := CollisionShape3D.new()
    var db := BoxShape3D.new()
    db.size = Vector3(1.4, 0.5, 0.3)
    dc.shape = db
    drain.add_child(dc)
    drain.position = Vector3(0, 0, 0.85)
    pf.add_child(drain)
    drain.body_entered.connect(_on_drain)

func _on_drain(b: Node) -> void:
    if b == ball:
        _drain()

func _ui() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    lbl_score = Label.new()
    lbl_score.position = Vector2(24, 20)
    lbl_score.add_theme_font_size_override("font_size", 40)
    layer.add_child(lbl_score)
    lbl_balls = Label.new()
    lbl_balls.position = Vector2(24, 72)
    lbl_balls.add_theme_font_size_override("font_size", 30)
    layer.add_child(lbl_balls)
    lbl_msg = Label.new()
    lbl_msg.position = Vector2(150, 1108)
    lbl_msg.add_theme_font_size_override("font_size", 30)
    layer.add_child(lbl_msg)
    meter_bg = ColorRect.new()
    meter_bg.position = Vector2(VW / 2.0 - 150.0, 1170)
    meter_bg.size = Vector2(300, 26)
    meter_bg.color = Color(0.15, 0.16, 0.20)
    layer.add_child(meter_bg)
    meter_fill = ColorRect.new()
    meter_fill.position = meter_bg.position
    meter_fill.size = Vector2(0, 26)
    meter_fill.color = Color(0.40, 0.85, 0.50)
    layer.add_child(meter_fill)
    _update_ui()

func _update_ui() -> void:
    lbl_score.text = "SCORE  %d" % score
    lbl_balls.text = "BALLS  %d" % balls

func _update_meter() -> void:
    meter_fill.size = Vector2(300.0 * power, 26)
    meter_fill.color = Color(0.40, 0.85, 0.50).lerp(Color(0.95, 0.45, 0.30), power)

func _reset_ball() -> void:
    ball_live = false
    charging = false
    power = 0.0
    charge_phase = 0.0
    ball.linear_velocity = Vector3.ZERO
    ball.angular_velocity = Vector3.ZERO
    ball.position = ball_start
    ball.sleeping = false
    lbl_msg.text = "HOLD SPACE, release to launch"
    _update_meter()

func _drain() -> void:
    if not ball_live:
        return
    balls -= 1
    _update_ui()
    if balls <= 0:
        balls = 3
        score = 0
        _update_ui()
    _reset_ball()

func _launch(p: float) -> void:
    ball_live = true
    lbl_msg.text = ""
    var up_table := (pf.global_transform.basis * Vector3(0, 0, -1)).normalized()
    var speed := lerpf(LAUNCH_MIN, LAUNCH_MAX, clampf(p, 0.0, 1.0))
    ball.linear_velocity = up_table * speed

func _physics_process(delta: float) -> void:
    var lt: float = lflip.get_meta("up") if (Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)) else lflip.get_meta("rest")
    lflip.rotation.y = move_toward(lflip.rotation.y, lt, FLIP_SPEED * delta)
    var rt: float = rflip.get_meta("up") if (Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) else rflip.get_meta("rest")
    rflip.rotation.y = move_toward(rflip.rotation.y, rt, FLIP_SPEED * delta)
    if not ball_live:
        if Input.is_key_pressed(KEY_SPACE):
            charging = true
            charge_phase += delta * CHARGE_RATE
            power = pingpong(charge_phase, 1.0)
            lbl_msg.text = "release to launch"
            _update_meter()
        elif charging:
            charging = false
            _launch(power)
            charge_phase = 0.0
            power = 0.0
            _update_meter()
