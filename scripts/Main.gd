extends Node2D
## Gray-box pinball v2, built procedurally. ORIGINAL generic table of primitives.
## Controls: LEFT flipper = A / Left-Arrow, RIGHT flipper = D / Right-Arrow, LAUNCH/RESET = Space.

const W := 720.0
const H := 1280.0
const BALL_R := 13.0
const L_REST := 0.42
const L_UP := -0.45
const R_REST := -0.42
const R_UP := 0.45
const FLIP_SPEED := 26.0
const LAUNCH_SPEED := 1850.0

var score := 0
var balls := 3
var ball_live := false
var ball: RigidBody2D
var lflip: AnimatableBody2D
var rflip: AnimatableBody2D
var lbl_score: Label
var lbl_balls: Label
var lbl_msg: Label
var launch_at := Vector2(662, 1150)

func _ready() -> void:
    _bg()
    # Cabinet: left wall, top, right outer wall, and the launch-lane floor.
    _wall(PackedVector2Array([
        Vector2(320, 1238), Vector2(150, 1150), Vector2(24, 1000), Vector2(24, 24),
        Vector2(696, 24), Vector2(696, 1180), Vector2(628, 1180),
    ]))
    # Lane divider (right boundary of play, open above y=260) + bottom-right funnel to the drain.
    _wall(PackedVector2Array([
        Vector2(628, 260), Vector2(628, 1130), Vector2(440, 1238),
    ]))
    _bumpers()
    lflip = _flipper(Vector2(245, 1115), L_REST, false)
    rflip = _flipper(Vector2(515, 1115), R_REST, true)
    _ball_and_drain()
    _ui()
    _reset_ball()

func _bg() -> void:
    var r := ColorRect.new()
    r.size = Vector2(W, H)
    r.color = Color(0.06, 0.07, 0.10)
    r.z_index = -10
    add_child(r)

func _circle(rad: float) -> PackedVector2Array:
    var p := PackedVector2Array()
    for i in 24:
        p.append(Vector2(cos(TAU * i / 24.0), sin(TAU * i / 24.0)) * rad)
    return p

func _wall(points: PackedVector2Array) -> void:
    var body := StaticBody2D.new()
    var mat := PhysicsMaterial.new()
    mat.bounce = 0.15
    mat.friction = 0.2
    body.physics_material_override = mat
    for i in points.size() - 1:
        var seg := SegmentShape2D.new()
        seg.a = points[i]
        seg.b = points[i + 1]
        var cs := CollisionShape2D.new()
        cs.shape = seg
        body.add_child(cs)
    add_child(body)
    var line := Line2D.new()
    line.points = points
    line.width = 4.0
    line.default_color = Color(0.35, 0.5, 0.75)
    add_child(line)

func _bumpers() -> void:
    for c in [Vector2(235, 380), Vector2(W - 235, 380), Vector2(W / 2.0, 560)]:
        var area := Area2D.new()
        area.position = c
        var ash := CircleShape2D.new()
        ash.radius = 38.0
        var acs := CollisionShape2D.new()
        acs.shape = ash
        area.add_child(acs)
        var vis := Polygon2D.new()
        vis.polygon = _circle(38.0)
        vis.color = Color(0.9, 0.45, 0.35)
        area.add_child(vis)
        var center: Vector2 = c
        area.body_entered.connect(func(b: Node) -> void: _bump(b, center))
        add_child(area)

func _bump(b: Node, center: Vector2) -> void:
    if b != ball:
        return
    score += 100
    _update_ui()
    var dir := ball.global_position - center
    if dir.length() < 1.0:
        dir = Vector2.UP
    dir = dir.normalized()
    var spd: float = max(ball.linear_velocity.length(), 520.0) + 160.0
    ball.linear_velocity = dir * spd

func _flipper(pivot: Vector2, rest: float, mirrored: bool) -> AnimatableBody2D:
    var f := AnimatableBody2D.new()
    f.position = pivot
    f.rotation = rest
    f.sync_to_physics = true
    var d := -1.0 if mirrored else 1.0
    var pts := PackedVector2Array([
        Vector2(0, -11), Vector2(130 * d, -7), Vector2(130 * d, 7), Vector2(0, 11),
    ])
    var sh := ConvexPolygonShape2D.new()
    sh.points = pts
    var cs := CollisionShape2D.new()
    cs.shape = sh
    f.add_child(cs)
    var vis := Polygon2D.new()
    vis.polygon = pts
    vis.color = Color(0.85, 0.85, 0.4)
    f.add_child(vis)
    add_child(f)
    return f

func _ball_and_drain() -> void:
    ball = RigidBody2D.new()
    ball.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
    ball.mass = 0.1
    ball.gravity_scale = 1.0
    var mat := PhysicsMaterial.new()
    mat.bounce = 0.2
    mat.friction = 0.2
    ball.physics_material_override = mat
    var sh := CircleShape2D.new()
    sh.radius = BALL_R
    var cs := CollisionShape2D.new()
    cs.shape = sh
    ball.add_child(cs)
    var vis := Polygon2D.new()
    vis.polygon = _circle(BALL_R)
    vis.color = Color(0.85, 0.92, 1.0)
    ball.add_child(vis)
    add_child(ball)
    var drain := Area2D.new()
    drain.position = Vector2(W / 2.0, H + 50.0)
    var dsh := RectangleShape2D.new()
    dsh.size = Vector2(W * 2.0, 60)
    var dcs := CollisionShape2D.new()
    dcs.shape = dsh
    drain.add_child(dcs)
    add_child(drain)
    drain.body_entered.connect(_on_drain_body)

func _on_drain_body(b: Node) -> void:
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
    lbl_msg.position = Vector2(150, H / 2.0 - 40.0)
    lbl_msg.add_theme_font_size_override("font_size", 34)
    layer.add_child(lbl_msg)
    _update_ui()

func _update_ui() -> void:
    lbl_score.text = "SCORE  %d" % score
    lbl_balls.text = "BALLS  %d" % balls

func _reset_ball() -> void:
    ball_live = false
    ball.linear_velocity = Vector2.ZERO
    ball.angular_velocity = 0.0
    ball.global_position = launch_at
    ball.sleeping = false
    lbl_msg.text = "SPACE to launch"

func _drain() -> void:
    if not ball_live:
        return
    balls -= 1
    _update_ui()
    if balls <= 0:
        balls = 3
        score = 0
        _update_ui()
        lbl_msg.text = "GAME OVER - SPACE to restart"
    _reset_ball()

func _physics_process(delta: float) -> void:
    var lt := L_UP if (Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)) else L_REST
    lflip.rotation = move_toward(lflip.rotation, lt, FLIP_SPEED * delta)
    var rt := R_UP if (Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) else R_REST
    rflip.rotation = move_toward(rflip.rotation, rt, FLIP_SPEED * delta)
    if not ball_live and Input.is_key_pressed(KEY_SPACE):
        ball_live = true
        lbl_msg.text = ""
        ball.linear_velocity = Vector2(-0.2, -1.0).normalized() * LAUNCH_SPEED
