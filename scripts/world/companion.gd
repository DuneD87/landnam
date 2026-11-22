class_name Companion extends CharacterBody3D

## Un aldeano que se ha ido con el jugador (SettlementCompanions): lleva el humano que tenía en su
## poblado y anda por el mundo con física, con la gravedad del planeta. Sigue al jugador (andando,
## corriendo o a la carrera según lo lejos que se quede, saltando si algo le corta el paso y rodeando
## paredes y casas por un camino, steer), nada si el agua lo cubre, trepa por donde ha trepado el
## jugador (ClimbRoutes), lo espera donde se le diga o vuelve a casa. Si ni así sale de donde está, o se queda muy atrás, aparece detrás del jugador. Se le habla como
## a un aldeano (VillagerChat).
##
## Lleva cosas en su morral (pack), que el jugador le da y le quita en la charla, y se pone lo que haya
## de ropa, armadura, escudo y arco (CompanionGear). Pelea: va a por lo que ataca al jugador o a él y por
## lo que ha herido el jugador, con la mejor arma que lleve (o la herramienta de su oficio, o los puños),
## de lejos con el arco si tiene flechas, y alza el escudo cuando le van a golpear; las fieras se le
## revuelven (Perception lo sigue viendo). Sin
## vida cae malherido y se levanta al rato; fuera de pelea se recupera poco a poco y come lo asado que
## lleve si le hace falta.
##
## Se le puede decir que se quede a vivir donde está (SETTLE): es un colono de la base del jugador. Hace
## vida allí: de día pasea cerca, al atardecer se sienta junto a una hoguera encendida (Campfire), de
## noche duerme en un petate libre (Bedroll) o, si no lo hay, en el suelo; y defiende la base de lo que
## ataque cerca. En su horario de trabajo hace lo que se le haya mandado (SettlerWork: talar, picar o
## limpiar una zona). Un árbol que le cae encima lo mata (crush), pero casi siempre oye el crujido al
## empezar a caer y se aparta corriendo, o no se mete debajo (_watch_falls). Ver docs/villagers.md.

enum Mode {FOLLOW, WAIT, LEAVE, SETTLE}
## Lo que hace en la base.
enum Chore {STAND, WALK, SIT, SLEEP}

const GROUP := &"companion"
## Siguiendo: se para a STOP m del jugador y echa a andar a más de START; a más de JOG_FROM m trota y
## a más de RUN_FROM corre, cada vez más deprisa hasta la carrera (SPRINT_FROM m). Por pasos y no
## subiendo poco a poco: cada animación casa con su velocidad (a ritmo 1, Villager.*_CLIP_SPEED).
const STOP := 2.2
const START := 3.5
const JOG_FROM := 7.0
const RUN_FROM := 10.0
const SPRINT_FROM := 15.0
const WALK_SPEED := 1.4
const JOG_SPEED := 2.4
const RUN_SPEED := 4.0
const SPRINT_SPEED := 8.0
const ACCEL := 12.0
const TURN_RATE := 6.0
## La animación por la velocidad real (m/s): trota por encima de GAITS.x y corre por encima de GAITS.y;
## para volver a la de abajo tiene que bajar GAIT_MARGIN más.
const GAITS := Vector2(2.0, 3.2)
const GAIT_MARGIN := 0.3
const JUMP_SPEED := 5.0
## En el suelo empuja hacia él a STICK m/s: sin eso, contra una pared de una construcción deja el suelo
## un tick sí y otro no.
const STICK := 0.5
## Atascado: avanzando a menos de STUCK_RATIO de lo que quiere, salta cada JUMP_EVERY s si lo que
## tiene delante es bajo (nada a WALL_HEIGHT m del suelo a WALL_REACH m por delante); contra una pared
## no salta: busca camino (steer). Si sigue así STUCK_TELEPORT s a más de STUCK_FAR m, aparece detrás
## del jugador. A más de TELEPORT m, también.
const STUCK_RATIO := 0.35
const JUMP_EVERY := 0.8
const WALL_HEIGHT := 1.3
const WALL_REACH := 0.6
const STUCK_TELEPORT := 4.0
## Bordes (_ledge_ahead): no pisa donde el suelo queda a más de LEDGE_DROP m por debajo de sus pies (un
## precipicio, la boca de una cueva) andando en línea recta; siguiendo un camino de GroundPath, que ya
## se ha mirado, hasta GroundPath.DROP (bajar de un tejado). Mira hasta su radio más LEDGE_MARGIN m más
## lo que tarda en frenar, en LEDGE_SAMPLES puntos, desde LEDGE_UP m por encima de los pies. Si se para
## en un borde, busca camino (steer); si no hay, su trabajo lo da por imposible (SettlerWork.GIVE_UP).
## Siguiendo al jugador no frena: si el jugador baja, baja detrás (o aparece a su lado).
const LEDGE_DROP := 1.6
const LEDGE_MARGIN := 0.35
const LEDGE_UP := 1.0
const LEDGE_SAMPLES: Array[float] = [0.4, 0.7, 1.0]
const STUCK_FAR := 8.0
const TELEPORT := 50.0
## Dónde aparece: a esto (m) del jugador, por detrás, o girando estos grados si ahí no cabe.
const BEHIND := 2.5
const TELEPORT_ANGLES: Array[float] = [0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0]
## A más de esto (m) del jugador no se mueve ni cae: por allí el terreno no tiene colisión.
const FREEZE := 120.0
## Sin suelo a menos de PROBE_DEPTH m por debajo (aún no ha llegado la colisión) no cae; se mira cada
## PROBE_INTERVAL s.
const PROBE_DEPTH := 60.0
const PROBE_INTERVAL := 0.25
## Esperando, se sienta al rato (s).
const SIT_AFTER := 25.0
## Lo mira a menos de esto (m) si está quieto.
const FACE_PLAYER := 6.0
## Volviendo a casa: se va del todo a más de LEAVE_GONE m del jugador o a los LEAVE_TIME s.
const LEAVE_GONE := 35.0
const LEAVE_TIME := 45.0
## Lo que aguanta, los huecos de su morral y lo que cuenta la protección de su ropa (no la lleva por
## partes, como el jugador: se suma toda).
const MAX_HEALTH := 100.0
const PACK_SLOTS := 12
const ARMOR_SHARE := 0.4
## Pelea con lo que ataca al jugador o a él a menos de ENGAGE m del jugador (esperando, de sí mismo), y
## con lo que el jugador ha herido; lo deja si se aleja más de LEASH m. Se mira cada SCAN_INTERVAL s.
const ENGAGE := 20.0
const LEASH := 30.0
const SCAN_INTERVAL := 0.3
## Golpea al DAMAGE_SCALE de lo que haría el jugador con lo mismo (sin arma, FIST_DAMAGE; nunca menos),
## a ATTACK_SPEED del ritmo del golpe del jugador (MeleeMoveset) y con un respiro de ATTACK_PAUSE s entre
## golpe y golpe. Llega a la fiera con el brazo y lo que mide el arma (ARM más reach).
const DAMAGE_SCALE := 0.8
const FIST_DAMAGE := 6.0
const ARM := 0.45
const ATTACK_SPEED := 1.3
const ATTACK_PAUSE := Vector2(0.4, 1.1)
## El arma se ve mientras pelea y hasta ARMED_TIME s después.
const ARMED_TIME := 5.0
## Lo que dura el respingo al encajar un golpe (s; a mitad de golpe no se inmuta).
const FLINCH_TIME := 0.45
## Sin vida cae malherido: se levanta a los DOWN_TIME s con RISE_HEALTH de su vida.
const DOWN_TIME := 25.0
const RISE_HEALTH := 0.4
## Fuera de pelea, a los REGEN_AFTER s del último golpe recupera REGEN por segundo; y por debajo de
## EAT_BELOW de su vida come, cada EAT_EVERY s, algo de lo que lleva: lo asado cura HEAL_FOOD, un remedio
## HEAL_REMEDY.
const REGEN_AFTER := 8.0
const REGEN := 0.5
const EAT_BELOW := 0.5
const EAT_EVERY := 6.0
const HEAL_FOOD := 25.0
const HEAL_REMEDY := 40.0
## Viviendo en la base: sus petates y hogueras son los que hay a menos de BASE_RADIUS m del sitio que se
## le dio; de día pasea a menos de ROAM m de él y al atardecer se sienta alrededor de la hoguera (a
## FIRE_RING m). Llega a un sitio a menos de ARRIVE m. Pelea con lo que ataca a menos de DEFEND m de la
## base.
const BASE_RADIUS := 40.0
## Comer y beber (SettlerMeals.trip): llega al comedero o al bebedero a menos de MEAL_REACH m, se rinde a
## los MEAL_GIVE_UP s (y come o bebe donde esté) y se queda MEAL_TIME s de pie junto a él.
const MEAL_REACH := 1.3
const MEAL_GIVE_UP := 60.0
const MEAL_TIME := 6.0
const ROAM := 10.0
const FIRE_RING := Vector2(1.6, 2.4)
const ARRIVE := 0.6
const DEFEND := 25.0
## Caminos (steer): si en REPATH s no se acerca al menos PROGRESS m a donde va (o al siguiente punto del
## camino), busca un camino (GroundPath), como mucho PATH_TRIES veces por destino; llega a cada punto a
## menos de WAYPOINT m. Abre las puertas cerradas a menos de DOOR_OPEN m por las que pasa y las cierra
## al quedar a más de DOOR_CLOSE m.
## Gastados los intentos, vuelve a probar a los PATH_RETRY s si sigue sin acercarse.
const REPATH := 1.5
const PROGRESS := 0.3
const PATH_TRIES := 3
const PATH_RETRY := 8.0
const WAYPOINT := 0.6
## Andando en línea recta, cada LOOK_EVERY s mira WALL_LOOK m por delante (rodillas y cabeza): si hay
## una pared, una ventana o una puerta cerrada busca camino ya, sin pegarse a ella REPATH s.
const WALL_LOOK := 1.5
const WALL_LOOK_HEIGHTS: Array[float] = [0.4, 1.5]
const LOOK_EVERY := 0.25
const DOOR_OPEN := 1.6
const DOOR_CLOSE := 2.5
## Aplastado por un árbol: se queda en el suelo GONE_TIME s y se va.
const GONE_TIME := 60.0
## En formación (SettlementCompanions.slot_of): echa a andar a más de SLOT_START m de su hueco y se para a
## menos de SLOT_STOP con el jugador quieto. Va al paso del jugador y, si se queda atrás, más deprisa
## (SLOT_GAIN por metro; al menos al trote a más de SLOT_JOG m y corriendo a más de SLOT_RUN, hasta la
## carrera a SLOT_SPRINT). Si en
## SLOT_GIVE_UP s no se acerca al hueco (cae dentro de una pared) estando a menos de SLOT_NEAR m del
## jugador, se queda donde está hasta que el hueco se mueva SLOT_MOVED m. Se aparta de otro del grupo a
## menos de APART m.
const SLOT_START := 1.2
const SLOT_STOP := 0.5
const SLOT_JOG := 3.0
const SLOT_RUN := 6.0
const SLOT_SPRINT := 12.0
## Fuera de su hueco va al paso del jugador más SLOT_GAIN m/s por cada metro que le falta.
const SLOT_GAIN := 1.2
const SLOT_GIVE_UP := 1.5
const SLOT_NEAR := 7.0
const SLOT_MOVED := 1.5
const APART := 0.9
## A la orden: a por la fiera que se le marca hasta ORDER_LEASH m del jugador; en retirada no pelea
## RETREAT_TIME s y vuelve corriendo.
const ORDER_LEASH := 60.0
const RETREAT_TIME := 12.0
## Mandado a su base desde lejos (homing): va derecho a ella, trotando, hasta quedar a HOME_NEAR m; fuera
## de la vista del jugador (FREEZE) llega cuando habría llegado andando.
const HOME_NEAR := 12.0
const ANIM_HIT := &"combat/hit_react"
const ANIM_DOWN := &"combat/death"
## Un árbol que cae (FallingTree.HAZARD, mientras cae; _watch_falls): se da cuenta seguro (HEAR_SURE_CHANCE) a menos de HEAR_SURE m
## del tocón, y cada vez menos hasta HEAR_RANGE m; dormido, la mitad. Si está en su camino (a menos de
## su anchura más FLEE_MARGIN m del tronco, y no detrás del tocón), tras FLEE_REACT s lo deja todo (el
## golpe a medias, la pelea) y sale ya a la carrera por lo más corto: de lado o detrás del tocón, hasta
## quedar FLEE_EXTRA m fuera; si en FLEE_TIME s no lo ha conseguido, lo deja. Un árbol tarda de 2,3 s
## (6 m) a 3,4 s (15 m) en caer: no hay tiempo para más.
const HEAR_SURE := 20.0
const HEAR_RANGE := 50.0
const HEAR_SURE_CHANCE := 0.95
const FLEE_MARGIN := 0.6
const FLEE_EXTRA := 0.8
const FLEE_REACT := Vector2(0.15, 0.45)
const FLEE_TIME := 5.0
## Dónde estará dentro de esto (s), andando como anda: si va a meterse en su camino, se para fuera.
const LOOK_AHEAD := 0.8
## En una bancada (RowingBench): va hasta ella y se sienta a menos de SEAT_REACH m; si en BOARD_TIME s
## no llega (un barco en el agua, sin camino), aparece sentado. Sentarse es la del trono (sentarse al
## revés para levantarse no hace falta: aparece de pie delante). Remando, ANIM_ROW si existe, a la
## par de su remo (BoatOars.phase, más ROW_PHASE de desfase).
const SEAT_REACH := 1.2
const BOARD_TIME := 12.0
## A un sitio (go_to): llega a menos de GOTO_REACH m (en el plano) y se queda esperando allí. Si no
## llega en lo que tardaría al trote, más GOTO_SPARE s, se queda donde esté. Fuera de la vista del
## jugador (FREEZE), aparece allí.
const GOTO_REACH := 0.6
const GOTO_SPARE := 15.0
const ANIM_SIT_DOWN := &"village/throne_sit"
const ANIM_SEATED := &"village/throne_idle"
const ANIM_ROW := &"village/row"
const ROW_PHASE := 0.0
const RowingPoseScript = preload("res://scripts/world/rowing_pose.gd")
const HIPS := &"mixamorig_Hips"
## Al cargar: lo que espera a que aparezca su bancada (los barcos se recrean al cargar).
const PENDING_BENCH_TIME := 5.0
## Tras algo que se mueve (el jugador, una fiera; steer con moving): no se acerca aunque ande bien, así
## que busca camino cuando lleva CHASE_STUCK s sin avanzar lo que quiere o ve una pared delante, y no
## más de una vez cada REPATH s.
const CHASE_STUCK := 0.5
## Nadar: se pone a nadar con los pies a más de SWIM_DEPTH m bajo la superficie (como el jugador,
## PlayerController.swimming_offset) y deja de nadar cuando hace pie: con el fondo a menos de SWIM_LEAVE
## m bajo la superficie (o fuera del agua). Flota con la cabeza fuera: con los pies a SWIM_FLOAT_MOVE m
## nadando (la cabeza de swimming va a 0,9 m de los pies, tumbada) y a SWIM_FLOAT_IDLE quieto (la de
## swimming_idle, a 1,55 m, de pie). Nada a SWIM_SPEED m/s y, si se queda atrás o va a pelear, a
## SWIM_FAST. En el agua no golpea ni dispara.
const SWIM_DEPTH := 1.45
const SWIM_LEAVE := 1.25
const SWIM_FLOAT_MOVE := 0.8
const SWIM_FLOAT_IDLE := 1.4
const SWIM_SPEED := 2.5
const SWIM_FAST := 3.2
const ANIM_SWIM := &"swimming"
const ANIM_SWIM_IDLE := &"swimming_idle"
## Arco (CompanionGear.bow, con flechas en el morral): dispara a lo que está a más de BOW_MIN m y a
## menos de BOW_RANGE (más lejos, se acerca); si se le echa encima a menos de BOW_CLOSE mientras tensa,
## lo deja y pelea con la mano. Tensa con bow_draw (a BOW_DRAW_SPEED), aguanta BOW_HOLD s, suelta con
## bow_recoil y respira BOW_PAUSE s. Apunta adelantándose a la fiera y a la caída de la flecha, con
## BOW_SPREAD grados de error.
const BOW_MIN := 6.0
const BOW_CLOSE := 3.0
const BOW_RANGE := 35.0
const BOW_DRAW_SPEED := 1.0
const BOW_HOLD := Vector2(0.15, 0.5)
const BOW_PAUSE := Vector2(0.5, 1.2)
const BOW_SPREAD := 1.5
const ANIM_BOW_DRAW := &"combat/bow_draw"
const ANIM_BOW_RECOIL := &"combat/bow_recoil"
## Escudo (CompanionGear.shield): cuando la fiera con la que pelea va a por él y empieza un golpe a menos
## de su alcance más GUARD_RANGE m, lo alza tras GUARD_REACT s (una vez de cada GUARD_MISS no se da
## cuenta) y lo baja GUARD_DROP s después de que acabe. Con el escudo alzado no golpea.
const GUARD_RANGE := 2.5
const GUARD_REACT := Vector2(0.08, 0.3)
const GUARD_MISS := 0.2
const GUARD_DROP := 0.35
const GUARD_RAISE_SPEED := 1.4
const GUARD_HIT_SPEED := 1.3
const ANIM_SHIELD_RAISE := &"combat/shield_block"
## Con un arma a dos manos que para (ItemData.guard_reduction: el espadón, el hacha grande, la maza),
## sin escudo, se cubre con ella igual: la alza con la guardia del espadón.
const ANIM_WEAPON_GUARD := &"combat/greatsword_block_idle"
## Sin con qué parar (una mano sin escudo, una herramienta, los puños), esquiva: al ver venir el golpe
## (como al alzar el escudo: tras GUARD_REACT s, y una vez de cada DODGE_MISS no se da cuenta) da un paso
## atrás, como el del jugador (BodyMotion.BACKSTEP en su CombatPose, PlayerCombat.BACKSTEP_*), hacia
## atrás o en diagonal (hasta DODGE_SIDE grados), sin dejar de mirarla y sin que le den en sus primeras
## décimas. Gasta DODGE_COST de aguante (sin él, no esquiva) y no vuelve a esquivar hasta DODGE_COOL s.
const DODGE_MISS := 0.3
const DODGE_SIDE := 40.0
const DODGE_COST := 10.0
const DODGE_COOL := 1.0
const ANIM_SHIELD_HOLD := &"combat/shield_block_idle"
const ANIM_SHIELD_HIT := &"combat/shield_block_hit"
## Trepar detrás del jugador (ClimbRoutes): busca ruta cada ROUTE_SCAN s; llega a su pie a menos de
## ROUTE_FOOT m (si en ROUTE_GIVE_UP s no llega, la deja) y espera allí su turno. Trepa por los puntos de
## la ruta a CLIMB_SPEED m/s, sin colisión, con climb_up o climb_down al ritmo que casa sus manos con
## la pared (ClimbController.UP_CLIP_SPEED), y corona con climb_top (a TOP_SPEED) hasta donde acabó de pie
## el jugador. climb_top acaba de pie en su origen y empieza colgado: su cadera, medida en el esqueleto,
## por TOP_HIPS (instante, cadera en su marco); el cuerpo corona desde donde su cadera casa con la suya
## (CLIMB_HIPS m sobre los pies, trepando) y llega de pie a TOP_SETTLE s.
const ROUTE_SCAN := 0.5
const ROUTE_FOOT := 0.9
const ROUTE_GIVE_UP := 30.0
const CLIMB_SPEED := 0.9
const CLIMB_HIPS := 1.1
const TOP_SPEED := 1.0
const TOP_SETTLE := 3.2
const TOP_HIPS: Array[Vector4] = [Vector4(0.0, 0.10, -0.68, -1.46), Vector4(0.8, -0.11, -0.26, -1.42),
	Vector4(1.6, 0.01, 0.36, -1.30), Vector4(2.4, -0.07, 0.98, -0.79), Vector4(3.2, -0.01, 1.0, -0.04),
	Vector4(4.0, 0.0, 0.99, 0.0)]
const ANIM_CLIMB_UP := &"combat/climb_up"
const ANIM_CLIMB_DOWN := &"combat/climb_down"
const ANIM_CLIMB_TOP := &"combat/climb_top"

## SettlementPopulation.residents: "id", "name", "sex", "job"...
var resident: Dictionary
## Su poblado (índice en el campo de poblados), su nombre y la confianza (la de SettlementManager).
var village := -1
var village_name := ""
var relations: SettlementRelations
var mode := Mode.FOLLOW
## Viviendo en la base: su sitio, en el marco del terreno (Vector3.INF si no).
var base := Vector3.INF
## La del planeta (PlanetLoader.gravity_strength).
var gravity := 9.8
## Lo que lleva (se guarda con él) y su vida (la buscan las fieras y los golpes por su nombre).
var pack: Inventory
## El morral, con el nombre con el que la tala y la picada dan lo que sacan (DroppedItem.give).
var inventory: Inventory
var health: HealthComponent
## Lo que hace en su horario de trabajo (viviendo en la base), y su hambre (allí come de los cofres).
var work: SettlerWork
var meals: SettlerMeals
## Hasta dónde va (m, desde lo que guarda) a por la fiera que se le marca: el cazador, hasta más allá
## de su zona.
var order_leash := ORDER_LEASH
## La base y el trabajo (SettlerWork.save_data) que dejó al irse con el jugador: a ellos vuelve
## (return_to_base). Vector3.INF si no vivía en ninguna.
var return_base := Vector3.INF
var return_work := {}
## Muerto (aplastado): no se guarda y se va a los GONE_TIME s.
var dead := false
var _gone_left := 0.0

var _terrain: Node3D
var _player: Node3D
## El centro de su poblado, en el marco del terreno (hacia donde vuelve).
var _home := Vector3.ZERO
var _model: Node3D
var _anim_player: AnimationPlayer
var _anim := &""
var _forward := Vector3.FORWARD
## 0 anda, 1 trota, 2 corre.
var _gait := 0
var _moving := false
var _stuck := 0.0
var _jump_left := 0.0
var _jump := false
var _idle := 0.0
var _leave_time := 0.0
var _chatting := false
var _say_left := 0.0
var _ground := true
var _probe_left := 0.0
var _rng := RandomNumberGenerator.new()
var _hurtbox: Hurtbox
## Con lo que pelea (null: los puños), lo que tiene en la mano y lo que le queda a la vista.
var _weapon: ItemData
var _tool: Node3D
var _armed_left := 0.0
## La fiera con la que pelea, o null.
var _target: NPCController
var _scan_left := 0.0
## El golpe: lo que le queda a la animación, cuándo llega (s, −1 ya ha llegado) y el respiro.
var _attack_left := 0.0
var _hit_at := -1.0
var _pause_left := 0.0
var _flinch_left := 0.0
## Malherido: lo que le queda en el suelo.
var _down_left := 0.0
var _since_hit := INF
var _eat_left := 0.0
var _shape: CollisionShape3D
## En la base: lo que hace, lo que le queda, adónde va andando (marco del terreno) y qué hará al llegar,
## hacia dónde mira sentado (la hoguera, marco del terreno) y su petate.
var _chore := Chore.STAND
var _chore_left := 0.0
## Lo que lleva yendo al comedero o al bebedero (s); 0 si no va.
var _meal_time := 0.0
## Lo que le queda de pie junto al comedero o al bebedero tras comer o beber (s).
var _meal_left := 0.0
var _spot := Vector3.ZERO
var _then := Chore.STAND
var _look := Vector3.INF
var _bed: Bedroll
## Acostarse, dormir y levantarse (las animaciones encadenadas); y lo que falta para volver a apoyarse
## en el petate, dormido y quieto (s).
var _sleep_routine: SleepRoutine
var _bed_fit_left := 0.0
## El camino de ahora (puntos, marco del terreno), por cuál va, a dónde (marco del terreno), lo más cerca
## que ha llegado del punto al que va, lo que le queda para buscar otro, los intentos y las puertas que
## ha abierto.
var _path := PackedVector3Array()
## Lo que se deja caer este paso (_ledge_ahead): LEDGE_DROP, o GroundPath.DROP si steer va por un camino.
var _ledge_drop := LEDGE_DROP
var _path_index := 0
var _path_dest := Vector3.INF
var _steer_best := INF
var _steer_left := REPATH
var _path_tries := 0
var _look_left := 0.0
var _opened_doors: Array[WoodenDoor] = []
## A la orden: la fiera se la ha marcado el jugador (order_attack), y lo que le queda de retirada (s).
var _ordered := false
var _retreat_left := 0.0
## En formación: lo más cerca que ha llegado de su hueco, lo que le queda para darlo por imposible y el
## hueco (marco del terreno) que dejó por imposible.
var _slot_best := INF
var _slot_left := SLOT_GIVE_UP
var _slot_held := Vector3.INF
## De vuelta a su base (return_to_base) y lo que lleva andado (s) fuera de la vista del jugador.
var homing := false
var _travel := 0.0

# --- En una bancada ---
## La bancada en la que se sienta o a la que va (RowingBench); _on_bench mientras la tenga.
var bench: RowingBench
var _on_bench := false
var _seated := false
var _board_left := 0.0
## Sentado: su cuerpo en el marco de la bancada; sentándose, de dónde viene y cuánto lleva.
var _seat_pose := Transform3D.IDENTITY
var _rowing_pose: RowingPoseScript
var _stand_pose := Transform3D.IDENTITY
var _sit_time := -1.0
var _sit_length := 0.0
## Al cargar: el entity_id de la bancada en la que iba sentado, hasta encontrarla.
var _pending_bench := ""
var _pending_left := 0.0

# --- Apartarse de un árbol que cae ---
## Adónde corre (marco del terreno), o INF; lo que tarda en reaccionar y lo que le queda para llegar.
var _flee := Vector3.INF
var _flee_wait := 0.0
var _flee_left := 0.0
## Si se ha dado cuenta de cada árbol que cae (instance_id -> bool: se decide una vez por árbol).
var _heard := {}
## El árbol que espera a que caiga, parado fuera de su camino (iba a meterse), o null.
var _hold_for: FallingTree

# --- A un sitio ---
## Adónde va (marco del terreno), o INF; y el tiempo que le queda para llegar.
var _goto := Vector3.INF
var _goto_left := 0.0

# --- Equipo, agua y caminos tras algo que se mueve ---
## Lo que lleva puesto del morral: ropa, armadura, escudo y arco.
var gear: CompanionGear
## Si va por un encargo (SettlementQuests, QuestDirector): el perdido al que se lleva a casa o el que se
## escolta al poblado vecino. Es el "id" de quien lo pidió (el encargo es suyo), o "". No ocupa sitio en el
## grupo, no se le manda trabajar ni quedarse en la base: solo seguir o esperar.
var ward := ""
## Brazos por código sobre su animación, como los del jugador (CombatPose, combat_pose()): el arco
## (BowAnimRig: el arco en el puño, la cuerda en los dedos y la flecha, sobre bow_draw y bow_recoil) y la
## caña del pescador (FishingPose, que lleva SettlerFish). Se crea la primera vez que hace falta.
var pose: CombatPose
var _aim := 0.0
## Nadando; la superficie del agua aquí (radio desde el centro del planeta) y ese centro.
var _swimming := false
var _water_r := 0.0
var _water_center := Vector3.ZERO
## Con el arco fuera; tensándolo, lo que le queda para soltar (s; −1 si no tensa).
var _bow_out := false
var _draw_left := -1.0
## Escudo: alzado; lo que le falta para alzarlo (s; −1 si no va a alzarlo); lo que le queda alzado
## sin peligro; y si ya ha decidido qué hacer con el golpe que viene.
var _guard_up := false
var _guard_wait := -1.0
var _guard_calm := 0.0
var _guard_seen := false
## Esquivando: el tiempo que lleva (s, −1 si no), hacia dónde (mundo), lo que le falta para hacerlo tras
## verlo venir (−1 si nada) y para poder volver a esquivar.
var _dodge_t := -1.0
var _dodge_dir := Vector3.ZERO
var _dodge_wait := -1.0
var _dodge_cool := 0.0
## Lo que falta para poder buscar otro camino tras algo que se mueve (s).
var _search_cool := 0.0

# --- Trepar detrás del jugador ---
## La ruta por la que va a subir (ClimbRoutes) o {}; lo que le queda para llegar a su pie y para volver
## a buscar.
var _route := {}
var _route_left := 0.0
var _route_scan := 0.0
## Trepando (sin colisión): por qué punto de la ruta va; coronando, el instante de climb_top, el marco
## del clip al empezar (mundo) y dónde acaba de pie.
var _climbing := false
var _climb_i := 0
var _topping := false
var _top_t := 0.0
var _top_t0 := 0.0
var _top_from := Vector3.ZERO
var _top_basis := Basis.IDENTITY
var _top_stand := Vector3.ZERO


## [who]: su vecino (SettlementPopulation.residents) del poblado [v] ([v_name]); [model]: su humano
## vestido (Villager.build_model o el del aldeano); [home]: el centro del poblado en el marco del
## terreno [terrain].
func setup(who: Dictionary, v: int, v_name: String, trust: SettlementRelations, model: Node3D,
		terrain: Node3D, player: Node3D, home: Vector3) -> void:
	resident = who
	village = v
	village_name = v_name
	relations = trust
	_terrain = terrain
	_player = player
	_home = home
	name = "Companion_%s" % String(who.get("id", "")).replace(":", "_")
	add_to_group(GROUP)
	collision_layer = Villager.BODY_LAYER
	collision_mask = PhysicsLayers.WORLD
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.4
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = Villager.BODY_RADIUS
	capsule.height = Villager.BODY_HEIGHT
	shape.shape = capsule
	shape.position = Vector3(0.0, Villager.BODY_HEIGHT * 0.5, 0.0)
	add_child(shape)
	_shape = shape
	_model = model
	_model.transform = Transform3D.IDENTITY
	add_child(_model)
	_anim_player = _model.get_node("AnimationPlayer") as AnimationPlayer
	_anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	# Los golpes, el respingo y la caída, los del jugador.
	if not _anim_player.has_animation_library(&"combat") and ResourceLoader.exists(PlayerCombat.COMBAT_LIBRARY):
		_anim_player.add_animation_library(&"combat", load(PlayerCombat.COMBAT_LIBRARY))
	# Trabajos agachados (despiezar), empalmados de los del jugador.
	AnimSplice.attach(_anim_player, _model.get_node("Armature/Skeleton3D") as Skeleton3D)
	_tool = _model.get_node_or_null("Armature/Skeleton3D/ToolHand/Grip/Tool") as Node3D
	(_model.get_node("Armature/Skeleton3D") as Skeleton3D).skeleton_updated.connect(_on_skeleton_updated)
	_sleep_routine = SleepRoutine.new(_anim_player, hash([who.get("look", 0), "sleep"]),
		_model.get_node_or_null("AppearanceRig") as CharacterAppearanceRig)
	if _tool != null:
		_tool.visible = false
	_rng.seed = hash([who.get("look", 0), "companion"])
	gear = CompanionGear.new(self, _model, who.get("outfit", []))
	gear.guard.blocked.connect(_on_guard_blocked)
	gear.guard.broken.connect(_on_guard_broken)
	health = HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = MAX_HEALTH
	health.guard = gear.guard
	health.hit_received.connect(_on_hit)
	health.died.connect(_on_down)
	add_child(health)
	_apply_armor()
	_hurtbox = Hurtbox.attach(self, self, capsule, shape.transform, &"body")
	_hurtbox.health = health
	pack = Inventory.new(PACK_SLOTS)
	pack.name = "Pack"
	add_child(pack)
	pack.inventory_changed.connect(_on_pack_changed)
	inventory = pack
	meals = SettlerMeals.new(self)
	work = SettlerWork.new(self)
	# La herramienta que ya trae en la mano (build_model) es la de su oficio.
	_weapon = _job_tool() if _tool != null else null
	refresh_weapon()


func _ready() -> void:
	set_process(_seated)
	_forward = _tangent(global_basis.z)
	if _forward == Vector3.ZERO:
		_forward = _tangent(Vector3.FORWARD)
	_play(Villager.ANIM_IDLE, 0.0)


func _exit_tree() -> void:
	# Libera reservas y rompe el ciclo SettlerWork -> SettlerTask -> SettlerWork, también al
	# cargar otra partida o retirar el planeta (no solo al morir o cambiar de oficio).
	if work != null:
		work.stop()


## Se queda donde está hasta que se le diga que siga.
func wait_here() -> void:
	_drop_route()
	stand_up()
	_leave_base()
	_goto = Vector3.INF
	mode = Mode.WAIT
	_idle = 0.0


## Va andando (al trote si está lejos) a [spot] (mundo) y se queda esperando allí, defendiendo el sitio,
## hasta que se le diga que siga. Por el camino pelea como esperando. Falso si no puede.
func go_to(spot: Vector3) -> bool:
	if dead or _down_left > 0.0 or mode == Mode.LEAVE or not spot.is_finite():
		return false
	wait_here()
	_target = null
	_ordered = false
	_chatting = false
	_goto = _terrain.global_transform.affine_inverse() * spot
	_goto_left = global_position.distance_to(spot) / JOG_SPEED + GOTO_SPARE
	_stuck = 0.0
	_path_dest = Vector3.INF
	return true


## A la orden del jugador (la rueda del grupo): se pone con [job] (SettlerWork.Job) en campo, en la zona
## de alrededor de [spot] (mundo), sin dejar de ir con el jugador: espera allí trabajando hasta que se
## le diga otra cosa (SettlerWork.field). Falso si no puede.
func field_work(job: SettlerWork.Job, spot: Vector3) -> bool:
	if dead or _down_left > 0.0 or mode == Mode.LEAVE or not spot.is_finite():
		return false
	wait_here()
	_target = null
	_ordered = false
	_chatting = false
	var radius := SettlerWork.CLEAR_RADIUS if job == SettlerWork.Job.CLEAR else SettlerWork.FIELD_RADIUS
	work.assign(job, _terrain.global_transform.affine_inverse() * spot, radius, 0, true)
	return true


## Si trabaja en campo (field_work).
func is_field_working() -> bool:
	return mode == Mode.WAIT and work.active() and work.field


## Si está malherido en el suelo (se levanta al rato).
func is_down() -> bool:
	return _down_left > 0.0


## Si va de camino a un sitio (go_to).
func is_going() -> bool:
	return _goto.is_finite()


## Adónde va (marco del terreno), o INF.
func goto_spot() -> Vector3:
	return _goto


func follow() -> void:
	stand_up()
	_leave_base()
	_goto = Vector3.INF
	mode = Mode.FOLLOW
	_idle = 0.0
	_slot_held = Vector3.INF


## Si tiene una base a la que volver (la que dejó para irse con el jugador).
func has_return_base() -> bool:
	return return_base.is_finite()


## Vuelve a vivir a la base que dejó, con el trabajo que tenía. Falso si no tenía ninguna.
func return_to_base() -> bool:
	if not return_base.is_finite() or dead or mode == Mode.LEAVE:
		return false
	var job := return_work
	settle_here(return_base)
	work.restore(job)
	homing = true
	return true


## A la orden del jugador: a por [creature]. Falso si no puede (malherido, se va) o no vale.
func order_attack(creature: NPCController) -> bool:
	if dead or _down_left > 0.0 or mode == Mode.LEAVE or not _alive(creature):
		return false
	stand_up()
	_retreat_left = 0.0
	_chatting = false
	_target = creature
	_ordered = true
	_show_weapon()
	_to_arms()
	return true


## A la orden del jugador: deja la pelea y, si lo acompaña, vuelve con él corriendo.
func order_retreat() -> void:
	_target = null
	_ordered = false
	_retreat_left = RETREAT_TIME


## Si pelea ahora.
func is_fighting() -> bool:
	return _target != null


## Se queda a vivir donde está (o en [at], marco del terreno: al cargar).
func settle_here(at := Vector3.INF) -> void:
	# Dormido o sentado, se levanta antes (si no, se quedaría de pie sin colisión y se hundiría).
	stand_up()
	_wake()
	_goto = Vector3.INF
	# El trabajo en campo era de ir con el jugador: viviendo aquí, se le manda otro desde el trono.
	if work.field:
		work.stop()
	mode = Mode.SETTLE
	base = at if at.is_finite() else _terrain.global_transform.affine_inverse() * global_position
	return_base = Vector3.INF
	return_work = {}
	homing = false
	_travel = 0.0
	_rest(Chore.STAND, 2.0)


## Se vuelve a su poblado: echa a andar hacia allí y se va del todo al perderse de vista
## (SettlementCompanions lo quita al salir del árbol).
func go_home() -> void:
	_drop_route()
	stand_up()
	_leave_base()
	_goto = Vector3.INF
	mode = Mode.LEAVE
	_leave_time = 0.0


## Se le puede hablar si no se va, no pelea, no está malherido y no duerme.
func can_chat() -> bool:
	return not dead and mode != Mode.LEAVE and _target == null and _down_left <= 0.0 and _chore != Chore.SLEEP \
		and not _climbing


## Al cargar: la vida que tenía (si cayó, la de levantarse).
func restore_health(value: float) -> void:
	if value < 0.0:
		return
	health.health = clampf(maxf(value, MAX_HEALTH * RISE_HEALTH), 0.0, MAX_HEALTH)
	health.health_changed.emit(health.health, health.max_health)


## Dónde se le mira al buscarlo con la vista (Perception): el pecho.
func get_lock_point() -> Vector3:
	return global_position + global_basis.y * Villager.BODY_HEIGHT * 0.65


## Le cambia el morral: el arma, y se pone lo que lleve de ropa, armadura, escudo y arco (CompanionGear).
func _on_pack_changed() -> void:
	refresh_weapon()
	if gear.refresh(pack):
		_apply_armor()
	if gear.shield == null:
		_lower_guard()
	if gear.bow == null or gear.ammo_left(pack) <= 0:
		_cancel_draw()
		_bow_out = false
	_show_gear()


## Lo que le protege lo que lleva puesto (sumado, en ARMOR_SHARE: no la lleva por partes como el jugador).
func _apply_armor() -> void:
	var armor := gear.armor() * ARMOR_SHARE
	health.armor_slash = armor.x
	health.armor_blunt = armor.y
	health.armor_pierce = armor.z


## El escudo y el arco, a la vista cuando toca: el escudo salvo durmiendo, sentado, nadando, con el arco
## fuera o con un arma a dos manos; el arco, solo fuera.
func _show_gear() -> void:
	var resting := _chore == Chore.SLEEP or _seated or dead
	var two_hands := _weapon != null and _weapon.two_handed and _armed_left > 0.0
	gear.show(gear.shield != null and not resting and not _swimming and not _bow_out and not two_hands,
		_bow_out and not resting)


## Con qué pelea: lo mejor que lleve para golpear o, si no, la herramienta de su oficio (o nada: los
## puños). Lo pone en la mano.
func refresh_weapon() -> void:
	var best := _job_tool()
	var best_damage := float(best.damage) if best != null else 0.0
	for item in pack.get_all_items():
		if item != null and _strikes_with(item.data) and float(item.data.damage) > best_damage:
			best = item.data
			best_damage = float(item.data.damage)
	if best == _weapon and (best == null or _tool != null):
		return
	_weapon = best
	_tool = Villager.hold(_model, best.scene_path if best != null else "")
	if _tool != null:
		_tool.visible = _armed_left > 0.0 and not _bow_out


## El jugador le habla: se para y lo mira hasta end_chat.
func begin_chat() -> bool:
	if not can_chat():
		return false
	_chatting = true
	_say_left = 0.0
	if not _seated:
		_play(Villager.ANIM_IDLE)
	return true


## Dice una frase: gesticula un rato.
func say() -> void:
	if not _chatting:
		return
	_say_left = Villager.SAY_TIME
	if not _seated:
		_play(Villager.ANIM_TALK)


func end_chat() -> void:
	_chatting = false
	_idle = 0.0


func is_chatting() -> bool:
	return _chatting


## Hacia dónde mira (tangente, mundo).
func facing() -> Vector3:
	return _forward


## Dónde guardarlo (mundo): trepando, donde acabará de pie; si no, donde está.
func save_position() -> Vector3:
	var spot := work.task.ground_spot() if work != null and work.task != null else Vector3.INF
	if spot.is_finite():
		return spot
	if _climbing and _route.has("stand") and (_route.stand as Vector3).is_finite():
		return _terrain.global_transform * (_route.stand as Vector3)
	return global_position


## Si va trepando detrás del jugador.
func is_climbing() -> bool:
	return _climbing


# --- Trepar detrás del jugador (ClimbRoutes) -------------------------------------------------------

## Un paso hacia el pie de la ruta por la que ha trepado el jugador, y allí espera su turno y empieza a
## trepar: [hacia dónde, a qué velocidad], o [] si no hay ruta (sigue al jugador como siempre).
func _to_route(party: SettlementCompanions, delta: float) -> Array:
	if _target != null or _swimming:
		return []
	if _route.is_empty():
		_route_scan -= delta
		if _route_scan > 0.0:
			return []
		_route_scan = ROUTE_SCAN
		_route = party.routes.find_for(self, _terrain, _player)
		if _route.is_empty():
			return []
		_route_left = ROUTE_GIVE_UP
	if not party.routes.has(_route):
		_route = {}
		return []
	var points: PackedVector3Array = _route.points
	var foot := _terrain.global_transform * points[0]
	var to := (foot - global_position).slide(up_direction)
	if to.length() > ROUTE_FOOT:
		_route_left -= delta
		if _route_left <= 0.0:
			# No llega a su pie: la deja un rato.
			_route = {}
			_route_scan = ROUTE_GIVE_UP
			return []
		var heading := steer(foot, ROUTE_FOOT * 0.7, delta)
		return [heading if heading != Vector3.ZERO else _tangent(to), JOG_SPEED if to.length() > JOG_FROM else WALK_SPEED]
	# Al pie: de cara a la pared, espera a que el jugador corone y a que suba el de delante.
	_face(-(_terrain.global_transform.basis * (_route.normals as PackedVector3Array)[0]), delta)
	var now := party.routes.clock
	if _route.done and now >= float(_route.next):
		_route.next = now + ClimbRoutes.GAP
		_start_climb()
	return [Vector3.ZERO, 0.0]


## Sube (o baja) por una escalera: por [points] (mundo, sus pies), de cara a ella ([normal]: de ella hacia
## él), y acaba de pie en [stand]. Con [top], corona arriba como en una pared (climb_top); sin él, baja y
## acaba al pie. Lo usa el constructor con su andamio (SettlerScaffold).
func climb_ladder(points: PackedVector3Array, normal: Vector3, stand: Vector3, top: bool) -> void:
	var to_local := _terrain.global_transform.affine_inverse()
	var local := PackedVector3Array()
	var normals := PackedVector3Array()
	for point in points:
		local.append(to_local * point)
		normals.append((to_local.basis * normal).normalized())
	_route = {"points": local, "normals": normals, "stand": to_local * stand,
		"facing": (to_local.basis * -normal).normalized(), "top": top, "ladder": true}
	_start_climb()


## Se agarra: sin colisión ni nada en las manos, sube por la ruta.
func _start_climb() -> void:
	_climbing = true
	_topping = false
	_climb_i = 0
	_shape.disabled = true
	velocity = Vector3.ZERO
	_target = null
	_ordered = false
	_chatting = false
	_lower_guard()
	_cancel_draw()
	_bow_out = false
	_attack_left = 0.0
	_hit_at = -1.0
	_flinch_left = 0.0
	_armed_left = 0.0
	if _tool != null:
		_tool.visible = false
	_anim = &""


## Un paso trepando: hacia el siguiente punto de la ruta y, al acabarlos, a coronar.
func _climb_step(up: Vector3, delta: float) -> void:
	if not _route.has("points"):
		_end_climb(false)
		return
	if _topping:
		_top_step(up, delta)
		return
	var points: PackedVector3Array = _route.points
	var normals: PackedVector3Array = _route.normals
	if _climb_i >= points.size():
		if not bool(_route.get("top", true)):
			# Bajando por una escalera (climb_ladder): de pie donde acaban los peldaños.
			_top_stand = _terrain.global_transform * (_route.stand as Vector3)
			_end_climb(true)
			return
		_begin_top(up)
		return
	var target := _terrain.global_transform * points[_climb_i]
	var to := target - global_position
	var step := CLIMB_SPEED * delta
	if to.length() <= step:
		global_position = target
		_climb_i += 1
	else:
		global_position += to.normalized() * step
	var normal := _terrain.global_transform.basis * normals[mini(_climb_i, normals.size() - 1)]
	var facing := _tangent(-normal)
	if facing != Vector3.ZERO:
		_forward = facing
	_pose(up)
	var down := to.dot(up) < -0.3 * to.length()
	_play(ANIM_CLIMB_DOWN if down else ANIM_CLIMB_UP, 0.25)
	_anim_player.speed_scale = CLIMB_SPEED / (ClimbController.DOWN_CLIP_SPEED if down else ClimbController.UP_CLIP_SPEED)


## Empieza a coronar: el clip desde el instante en que su cadera queda tan por debajo del borde como la
## suya (una pared baja empieza más tarde), con su marco corrido para que las caderas casen.
func _begin_top(up: Vector3) -> void:
	var stand: Vector3 = _terrain.global_transform * (_route.stand as Vector3)
	var f := _tangent(_terrain.global_transform.basis * (_route.facing as Vector3))
	if f == Vector3.ZERO:
		f = _forward
	var stand_up_dir := (stand - _terrain.global_position).normalized()
	_top_basis = Basis(stand_up_dir.cross(f).normalized(), stand_up_dir, f)
	_top_stand = stand
	var rise := (stand - global_position).dot(up)
	# La cadera del clip a la altura (en su marco) a la que está la suya: CLIMB_HIPS sobre los pies.
	var want := CLIMB_HIPS - rise
	_top_t0 = 0.0
	for i in range(TOP_HIPS.size() - 1):
		var a := TOP_HIPS[i]
		var b := TOP_HIPS[i + 1]
		if want <= a.z:
			break
		if want <= b.z:
			_top_t0 = lerpf(a.x, b.x, (want - a.z) / maxf(b.z - a.z, 0.001))
			break
		_top_t0 = b.x
	_top_t0 = minf(_top_t0, TOP_SETTLE * 0.75)
	_top_t = _top_t0
	_top_from = global_position + up * CLIMB_HIPS - _top_basis * _top_hips(_top_t0)
	_topping = true
	_forward = f
	# El cuerpo salta al marco del clip (la cadera se queda donde estaba): sin interpolar ese salto.
	global_position = _top_from
	global_basis = _top_basis
	reset_physics_interpolation()
	_play(ANIM_CLIMB_TOP, 0.2, true)
	_anim_player.seek(_top_t0, true)
	_anim_player.speed_scale = TOP_SPEED


## Coronando: su marco va de donde empezó a donde acaba de pie, y al acabar el clip queda allí.
func _top_step(_up: Vector3, delta: float) -> void:
	_top_t += delta * TOP_SPEED
	var k := smoothstep(_top_t0, _top_t0 + (TOP_SETTLE - _top_t0) * 0.8, _top_t)
	global_position = _top_from.lerp(_top_stand, k)
	global_basis = _top_basis
	_forward = _top_basis.z
	if _top_t >= TOP_SETTLE:
		_end_climb(true)


## La cadera de climb_top en su marco en el instante [t] (TOP_HIPS).
func _top_hips(t: float) -> Vector3:
	for i in range(TOP_HIPS.size() - 1):
		var a := TOP_HIPS[i]
		var b := TOP_HIPS[i + 1]
		if t <= b.x:
			var k := clampf((t - a.x) / maxf(b.x - a.x, 0.001), 0.0, 1.0)
			return Vector3(a.y, a.z, a.w).lerp(Vector3(b.y, b.z, b.w), k)
	var last := TOP_HIPS[TOP_HIPS.size() - 1]
	return Vector3(last.y, last.z, last.w)


## Deja de trepar: de pie donde acabó el jugador ([arrived]) o, si no (malherido, muerto), donde esté,
## y vuelve a chocar (cae si está en el aire).
func _end_climb(arrived: bool) -> void:
	if not _climbing:
		_route = {}
		return
	_climbing = false
	_topping = false
	_shape.disabled = _chore == Chore.SLEEP or _seated
	if arrived:
		var up := (_top_stand - _terrain.global_position).normalized()
		global_position = _top_stand + up * 0.05
	velocity = Vector3.ZERO
	_route = {}
	_route_scan = ROUTE_SCAN
	_path_dest = Vector3.INF
	_stuck = 0.0
	_ground = true
	_anim = &""
	_play(Villager.ANIM_IDLE, 0.3)


## Olvida la ruta a la que iba (salvo que ya trepe: eso lo acaba).
func _drop_route() -> void:
	if not _climbing:
		_route = {}


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or _terrain == null \
			or GameManager.current_state != GameManager.State.PLAYING:
		return
	var up := (global_position - _terrain.global_position).normalized()
	up_direction = up
	var to_player := _player.global_position - global_position
	var distance := (to_player - up * to_player.dot(up)).length()
	_since_hit += delta
	if distance <= FREEZE and not _seated and not _climbing:
		_update_swim()
	gear.guard.update(delta)
	_show_gear()
	# Una esquiva a medias que se queda sin pelea (o malherido, muerto, trepando) se acaba: vuelve a
	# poder recibir golpes.
	if _dodge_t >= 0.0 and (dead or _down_left > 0.0 or _climbing or not _alive(_target)):
		_end_dodge()
	if dead:
		_gone_left -= delta
		_move(Vector3.ZERO, 0.0, up, delta)
		_pose(up)
		if _gone_left <= 0.0:
			queue_free()
		return
	if _down_left > 0.0:
		_lie(up, delta)
		return
	# Trepando detrás del jugador lo lleva la ruta: ni pelea ni se para.
	if _climbing:
		_climb_step(up, delta)
		return
	# Los árboles que caen: si se da cuenta y está (o se va a meter) en su camino, se aparta o se para.
	_watch_falls()
	# Ha oído caer un árbol: al reaccionar se levanta (de la bancada, del petate) para correr.
	if _flee.is_finite() and _flee_wait > 0.0:
		_flee_wait -= delta
		if _flee_wait <= 0.0:
			_start_flee(up)
	if _pending_bench != "":
		_find_pending_bench(delta)
		if _pending_bench != "":
			velocity = Vector3.ZERO
			return
	if _on_bench and (not is_instance_valid(bench) or not bench.is_inside_tree() or bench.is_queued_for_deletion()):
		stand_up()
	if _seated:
		# Sentado no pelea ni se mueve: su sitio lo pone _process, con la bancada.
		velocity = Vector3.ZERO
		_target = null
		_recover(delta)
		if _say_left > 0.0:
			_say_left -= delta
		return
	# La fiera puede haberse ido del árbol (un cadáver suelto se libera).
	if _target != null and not is_instance_valid(_target):
		_target = null
	if not _chatting:
		_scan_left -= delta
		if _scan_left <= 0.0:
			_scan_left = SCAN_INTERVAL
			_scan(distance)
	_update_guard(delta)
	_update_aim(delta)
	if _target == null and _draw_left >= 0.0:
		_cancel_draw()
	if _armed_left > 0.0 and _target == null:
		_armed_left -= delta
		if _armed_left <= 0.0:
			_bow_out = false
			if _tool != null:
				_tool.visible = false
	# Siguiendo, primero intenta aparecer junto al jugador (al que, por ejemplo, ha reaparecido lejos).
	if mode == Mode.FOLLOW and not _chatting and _target == null and distance > TELEPORT and _teleport():
		return
	if _retreat_left > 0.0:
		_retreat_left -= delta
	if mode == Mode.SETTLE or work.active():
		work.watch(delta)
	if mode == Mode.SETTLE:
		meals.tick(delta, distance <= FREEZE)
	if distance > FREEZE and mode != Mode.LEAVE:
		velocity = Vector3.ZERO
		if _goto.is_finite():
			_arrive_spot(true)
		if mode == Mode.SETTLE and not _travel_home(delta):
			work.away(delta, _hour())
		return
	if _target == null:
		_recover(delta)
	# El golpe sigue hasta el final aunque la fiera caiga o se vaya.
	if _attack_left > 0.0:
		_attack_left -= delta
		if _hit_at >= 0.0:
			_hit_at -= delta
			if _hit_at < 0.0:
				_land_hit(up)

	var heading := Vector3.ZERO
	var speed := 0.0
	var guard := true
	_ledge_drop = LEDGE_DROP
	if _flinch_left > 0.0:
		_flinch_left -= delta
	elif _flee.is_finite() and _flee_wait <= 0.0:
		var step := _run_from_tree(delta)
		heading = step[0]
		speed = step[1]
	elif _hold_for != null:
		# Quieto fuera de su camino hasta que caiga.
		heading = Vector3.ZERO
		speed = 0.0
	elif _target != null:
		var step := _fight(up, delta)
		heading = step[0]
		speed = step[1]
	elif _chatting:
		_face(to_player, delta)
		if _say_left > 0.0:
			_say_left -= delta
			if _say_left <= 0.0:
				_play(Villager.ANIM_IDLE)
	elif _on_bench:
		var step := _board(up, delta)
		heading = step[0]
		speed = step[1]
		if _seated:
			return
	elif _goto.is_finite():
		var step := _go(up, delta)
		heading = step[0]
		speed = step[1]
	elif is_field_working():
		# Trabajando no se sienta a esperar.
		_idle = 0.0
		var step := work.step(delta)
		heading = step[0]
		speed = step[1]
	else:
		match mode:
			Mode.FOLLOW:
				var step := _follow(to_player, distance, up, delta)
				heading = step[0]
				speed = step[1]
				guard = false
			Mode.LEAVE:
				_leave_time += delta
				if distance > LEAVE_GONE or _leave_time > LEAVE_TIME:
					queue_free()
					return
				heading = _tangent(_terrain.global_transform * _home - global_position)
				speed = WALK_SPEED
			Mode.SETTLE:
				var step := _live(delta)
				heading = step[0]
				speed = step[1]
	# Tumbado en el petate (o en el suelo) no se mueve ni choca.
	if _chore == Chore.SLEEP:
		velocity = Vector3.ZERO
		_moving = false
		_pose(up)
		_animate()
		return
	# Nadando va a su ritmo (al de quien anda o al de quien corre).
	if _swimming and speed > 0.0:
		speed = SWIM_FAST if speed > JOG_SPEED else SWIM_SPEED
	# Al borde de un precipicio o de una cueva se para y busca otro camino.
	if guard and speed > 0.0 and _ledge_ahead(heading, _ledge_drop):
		heading = Vector3.ZERO
		speed = 0.0
		_blocked_by_ledge()
	_moving = speed > 0.0
	_move(heading, speed, up, delta)
	if _moving and _dodge_t < 0.0:
		_face(heading, delta)
		_unstick(heading, speed, distance, delta)
	elif _target != null:
		_stuck = 0.0
	elif not _chatting:
		_stuck = 0.0
		_idle += delta
		# Trabajando mira a lo que golpea, no al jugador.
		if distance < FACE_PLAYER and (mode != Mode.SETTLE or _chore == Chore.STAND) and not work.busy():
			_face(to_player, delta)
	_pose(up)
	_animate()


## Un paso siguiendo al jugador: [hacia dónde, a qué velocidad]. Con formación (cuña o fila) va a su
## hueco, al paso del jugador y más deprisa si se queda atrás; suelto (o en retirada), hacia el jugador
## como siempre. Se aparta de los otros del grupo.
func _follow(to_player: Vector3, distance: float, up: Vector3, delta: float) -> Array:
	var party := _party()
	# Si el jugador ha trepado (o trepa), al pie de su ruta a subir detrás.
	if party != null and _retreat_left <= 0.0:
		var climb := _to_route(party, delta)
		if not climb.is_empty():
			return climb
	var slot := party.slot_of(self) if party != null and _retreat_left <= 0.0 else Vector3.INF
	var heading := Vector3.ZERO
	var speed := 0.0
	if not slot.is_finite():
		var stop := STOP + (party.loose_margin(self) if party != null else 0.0)
		if distance > stop + (START - STOP) or (_moving and distance > stop):
			# En línea recta y, si una pared o una casa se lo impide, por un camino (rodea, busca la puerta).
			heading = steer(_player.global_position, stop * 0.8, delta, true)
			if heading == Vector3.ZERO:
				heading = _tangent(to_player)
			if _retreat_left > 0.0:
				speed = remap(clampf(distance, stop, SPRINT_FROM), stop, SPRINT_FROM, RUN_SPEED, SPRINT_SPEED)
			elif distance < JOG_FROM:
				speed = WALK_SPEED
			elif distance < RUN_FROM:
				speed = JOG_SPEED
			else:
				speed = remap(minf(distance, SPRINT_FROM), RUN_FROM, SPRINT_FROM, RUN_SPEED, SPRINT_SPEED)
	else:
		var to_local := _terrain.global_transform.affine_inverse()
		var slot_local := to_local * slot
		# El hueco que dio por imposible sigue ahí: quieto.
		if _slot_held.is_finite():
			if _slot_held.distance_to(slot_local) < SLOT_MOVED:
				return [Vector3.ZERO, 0.0]
			_slot_held = Vector3.INF
			_slot_best = INF
			_slot_left = SLOT_GIVE_UP
		var d := (slot - global_position).slide(up).length()
		var body := _player as CharacterBody3D
		var pace := body.get_real_velocity().slide(up).length() if body != null else 0.0
		if d > SLOT_START or (_moving and (d > SLOT_STOP or pace > 0.3)):
			heading = steer(slot, SLOT_STOP * 0.8, delta, true)
			var catch_up := WALK_SPEED
			if d > SLOT_RUN:
				catch_up = remap(minf(d, SLOT_SPRINT), SLOT_RUN, SLOT_SPRINT, RUN_SPEED, SPRINT_SPEED)
			elif d > SLOT_JOG:
				catch_up = JOG_SPEED
			# Al paso del jugador y, fuera del hueco, más deprisa cuanto más lejos.
			speed = minf(maxf(catch_up, pace + d * SLOT_GAIN), SPRINT_SPEED) if d > SLOT_STOP \
				else minf(pace, SPRINT_SPEED)
			if d < _slot_best - PROGRESS:
				_slot_best = d
				_slot_left = SLOT_GIVE_UP
			else:
				_slot_left -= delta
				if _slot_left <= 0.0 and distance < SLOT_NEAR and pace < 0.3:
					_slot_held = slot_local
					return [Vector3.ZERO, 0.0]
		else:
			_slot_best = INF
			_slot_left = SLOT_GIVE_UP
	if speed > 0.0 and party != null:
		var push := party.apart_from(self, up)
		if push != Vector3.ZERO:
			heading = _tangent(heading + push * 0.7)
	return [heading, speed]


func _party() -> SettlementCompanions:
	return get_tree().get_first_node_in_group(SettlementCompanions.GROUP) as SettlementCompanions


## Fuera de la vista del jugador y lejos de su base: «anda» hacia ella y aparece allí cuando habría
## llegado. Cierto mientras va de camino (aún no trabaja).
func _travel_home(delta: float) -> bool:
	if not homing or not base.is_finite():
		return false
	var home := _terrain.global_transform * base
	var far := global_position.distance_to(home)
	_travel += delta
	if far > HOME_NEAR and _travel * WALK_SPEED < far:
		return true
	homing = false
	_travel = 0.0
	if far <= HOME_NEAR:
		return false
	global_position = home + (home - _terrain.global_position).normalized() * 0.1
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	return false


## La velocidad de este paso: en el plano, hacia [heading] a [speed]; en vertical, la gravedad (si hay
## suelo debajo: si no, espera a que llegue su colisión).
func _move(heading: Vector3, speed: float, up: Vector3, delta: float) -> void:
	var vertical := up * velocity.dot(up)
	var flat := velocity - vertical
	if _swimming:
		# Nadando: como mucho a SWIM_FAST, y flota con la cabeza fuera (los pies a SWIM_FLOAT_MOVE o
		# SWIM_FLOAT_IDLE m bajo la superficie: un muelle sobre la velocidad vertical); para salir a una
		# orilla alta, un impulso (_unstick).
		flat = flat.move_toward(heading * minf(speed, SWIM_FAST), ACCEL * 0.5 * delta)
		var depth := _water_r - global_position.distance_to(_water_center)
		var float_at := SWIM_FLOAT_MOVE if speed > 0.0 and heading != Vector3.ZERO else SWIM_FLOAT_IDLE
		var rise := clampf((depth - float_at) * 2.0, -2.0, 2.0)
		if _jump:
			rise = JUMP_SPEED * 0.8
		vertical = up * move_toward(velocity.dot(up), rise, 12.0 * delta)
		_jump = false
		_ground = true
		velocity = flat + vertical
		move_and_slide()
		return
	# Esquivando, el paso va a su velocidad desde el primer instante.
	flat = heading * speed if _dodge_t >= 0.0 else flat.move_toward(heading * speed, ACCEL * delta)
	if _jump and is_on_floor():
		vertical = up * JUMP_SPEED
	elif is_on_floor():
		vertical = -up * STICK
		_ground = true
	else:
		_probe_left -= delta
		if _probe_left <= 0.0:
			_probe_left = PROBE_INTERVAL
			_ground = _ground_below(up)
		if _ground:
			vertical -= up * gravity * delta
		else:
			vertical = Vector3.ZERO
			flat = Vector3.ZERO
	_jump = false
	velocity = flat + vertical
	move_and_slide()


## Si avanza mucho menos de lo que quiere: salta (un escalón, un bloque) y, si no sale de ahí y está
## lejos, aparece detrás del jugador.
func _unstick(heading: Vector3, speed: float, distance: float, delta: float) -> void:
	if get_real_velocity().dot(heading) >= speed * STUCK_RATIO:
		_stuck = maxf(_stuck - delta * 2.0, 0.0)
		return
	_stuck += delta
	_jump_left -= delta
	if _swimming and _jump_left <= 0.0 and _stuck > 0.5:
		# Contra la orilla: un impulso para salir del agua.
		_jump_left = JUMP_EVERY * 2.0
		_jump = true
	elif is_on_floor() and _jump_left <= 0.0 and _stuck > 0.25:
		_jump_left = JUMP_EVERY
		if _wall_ahead(heading):
			_steer_left = minf(_steer_left, 0.0)
		else:
			_jump = true
	# Aparece junto al jugador si ni por un camino sale de ahí (o lleva mucho atascado).
	if mode == Mode.FOLLOW and _target == null and _stuck > STUCK_TELEPORT and distance > STUCK_FAR \
			and (_path_tries >= PATH_TRIES or _stuck > STUCK_TELEPORT * 2.0) and _teleport():
		_stuck = 0.0


## Si andando hacia [heading] pisaría donde el suelo queda a más de [drop] m por debajo de sus pies (o
## no lo hay): mira hasta donde le da para frenar (ACCEL), en LEDGE_SAMPLES puntos. En el aire no mira.
func _ledge_ahead(heading: Vector3, drop: float) -> bool:
	if heading == Vector3.ZERO or not is_on_floor() or _swimming:
		return false
	var up := up_direction
	var pace := velocity.slide(up).length()
	var look := Villager.BODY_RADIUS + LEDGE_MARGIN + pace * pace / (2.0 * ACCEL)
	var space := get_world_3d().direct_space_state
	for k in LEDGE_SAMPLES:
		var at := global_position + heading * look * k
		var query := PhysicsRayQueryParameters3D.create(at + up * LEDGE_UP, at - up * drop,
			PhysicsLayers.WORLD, [get_rid()])
		if space.intersect_ray(query).is_empty():
			return true
	return false


## Se ha parado en un borde: el camino en línea recta (o el que llevaba) no vale; que steer busque otro.
func _blocked_by_ledge() -> void:
	_stuck = 0.0
	if not _path.is_empty():
		_path = PackedVector3Array()
		_path_index = 0
	_steer_left = minf(_steer_left, 0.0)


## Si delante (hacia [heading]) hay algo a WALL_HEIGHT m del suelo: una pared, no un escalón.
func _wall_ahead(heading: Vector3) -> bool:
	var from := global_position + up_direction * WALL_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(from, from + heading * (Villager.BODY_RADIUS + WALL_REACH),
		PhysicsLayers.WORLD, [get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Aparece a BEHIND m del jugador, por detrás de hacia donde va (o del lado por el que viene él), en
## un sitio a la vista del jugador y con suelo. Falso si no hay ninguno.
func _teleport() -> bool:
	var space := get_world_3d().direct_space_state
	var up := (_player.global_position - _terrain.global_position).normalized()
	var chest := _player.global_position + up * 1.2
	var body := _player as CharacterBody3D
	var back := _tangent(-body.velocity) if body != null else Vector3.ZERO
	if back == Vector3.ZERO:
		back = _tangent(global_position - _player.global_position)
	if back == Vector3.ZERO:
		back = _tangent(Vector3.FORWARD)
	# Cada uno del grupo prueba primero un ángulo distinto: no aparecen todos en el mismo sitio.
	var party := _party()
	var first := maxi(party.follower_index(self), 0) if party != null else 0
	for i in TELEPORT_ANGLES.size():
		var angle := TELEPORT_ANGLES[(i + first) % TELEPORT_ANGLES.size()]
		var spot := chest + back.rotated(up, deg_to_rad(angle)) * BEHIND
		var clear := PhysicsRayQueryParameters3D.create(chest, spot, PhysicsLayers.WORLD)
		if not space.intersect_ray(clear).is_empty():
			continue
		var down := PhysicsRayQueryParameters3D.create(spot, spot - up * 4.0, PhysicsLayers.WORLD)
		var hit := space.intersect_ray(down)
		if hit.is_empty():
			continue
		global_position = hit.position as Vector3 + up * 0.05
		velocity = Vector3.ZERO
		_forward = _tangent(_player.global_position - global_position)
		_ground = true
		reset_physics_interpolation()
		return true
	return false


func _ground_below(up: Vector3) -> bool:
	var from := global_position + up * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from - up * PROBE_DEPTH, PhysicsLayers.WORLD)
	query.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _face(direction: Vector3, delta: float) -> void:
	var want := _tangent(direction)
	if want == Vector3.ZERO:
		return
	var up := up_direction
	var angle := _forward.signed_angle_to(want, up)
	_forward = _tangent(_forward.rotated(up, clampf(angle, -TURN_RATE * delta, TURN_RATE * delta)))


func _pose(up: Vector3) -> void:
	var forward := _tangent(_forward)
	if forward == Vector3.ZERO:
		forward = _tangent(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT)
	_forward = forward
	global_basis = Basis(up.cross(forward), up, forward)


## Andar o correr a la velocidad a la que va; quieto, de pie o (esperando un rato) sentado. El golpe, el
## respingo y la caída los pone quien los empieza.
func _animate() -> void:
	if _chatting or _attack_left > 0.0 or _flinch_left > 0.0 or _guard_up or _climbing:
		return
	var up := up_direction
	var real := get_real_velocity()
	var speed := (real - up * real.dot(up)).length()
	if _swimming:
		if _moving and speed > 0.15:
			_play(ANIM_SWIM)
			_anim_player.speed_scale = clampf(speed / SWIM_SPEED, 0.6, 1.5)
		else:
			_play(ANIM_SWIM_IDLE)
		return
	if _moving and speed > 0.15:
		var gait := 2 if speed > GAITS.y else (1 if speed > GAITS.x else 0)
		if gait < _gait and speed > GAITS[gait] - GAIT_MARGIN:
			gait = _gait
		_gait = gait
		match gait:
			0:
				_play(Villager.ANIM_WALK)
				_anim_player.speed_scale = speed / Villager.WALK_CLIP_SPEED
			1:
				_play(Villager.ANIM_JOG)
				_anim_player.speed_scale = speed / Villager.JOG_CLIP_SPEED
			_:
				_play(Villager.ANIM_RUN)
				_anim_player.speed_scale = speed / Villager.RUN_CLIP_SPEED
		return
	_anim_player.speed_scale = 1.0
	var sitting := (mode == Mode.WAIT and _idle > SIT_AFTER) or (mode == Mode.SETTLE and _chore == Chore.SIT)
	if _target != null:
		_play(Villager.ANIM_IDLE)
	elif _chore == Chore.SLEEP:
		pass  # SleepRoutine
	else:
		_play(Villager.ANIM_SIT if sitting else Villager.ANIM_IDLE)


func _play(anim: StringName, blend := Villager.BLEND, again := false) -> void:
	if _anim == anim and not again:
		return
	_anim = anim
	_anim_player.speed_scale = 1.0
	_anim_player.play(anim, blend)
	if again:
		_anim_player.seek(0.0, true)


# --- Pelea ----------------------------------------------------------------------------------------

## Lo que guarda (el jugador; esperando, él mismo; viviendo en la base, la base): de ahí se mide lo que
## está a tiro.
func _guard_point() -> Vector3:
	match mode:
		Mode.WAIT:
			return global_position
		Mode.SETTLE:
			return work.guard_point()
	return _player.global_position


## Sigue con la que tiene si aún vale la pena, o busca otra.
func _scan(player_distance: float) -> void:
	if mode == Mode.LEAVE or _retreat_left > 0.0:
		_target = null
		_ordered = false
		return
	if _target != null and not _worth_chasing(_target, player_distance):
		_target = null
	if _target == null:
		_ordered = false
	if _target == null:
		_target = _pick()
		if _target != null:
			_show_weapon()
			_to_arms()
			if mode == Mode.SETTLE:
				work.on_engage(_target)


func _worth_chasing(creature: NPCController, player_distance: float) -> bool:
	var leash := order_leash if _ordered else LEASH
	# El guardia vigila una zona mayor: no suelta lo que aún está en ella.
	if mode == Mode.SETTLE:
		leash = maxf(leash, work.defend_radius() + 5.0)
	if not _alive(creature) or (mode == Mode.FOLLOW and player_distance > leash):
		return false
	return creature.global_position.distance_to(_guard_point()) <= leash


## La más cercana de las que van a por el jugador o a por él, o que ha herido el jugador (siguiéndolo).
func _pick() -> NPCController:
	var guard := _guard_point()
	var best: NPCController
	var settled := mode == Mode.SETTLE
	var reach := work.defend_radius() if settled else ENGAGE
	var best_distance := reach
	for creature in CreatureGrid.near(guard, reach):
		if not _alive(creature) or not (_hostile(creature) or (settled and work.is_threat(creature))):
			continue
		var d := creature.global_position.distance_to(guard)
		if d < best_distance:
			best = creature
			best_distance = d
	return best


static func _alive(creature: NPCController) -> bool:
	return creature != null and is_instance_valid(creature) and creature.active and not creature.is_dead \
		and not creature.dormant


## Si [creature] es de las suyas: le ataca a él, o al jugador o a otro compañero (peleando: la presa que
## huye del jugador también lo tiene de objetivo), o el jugador la ha herido (de caza: siguiéndolo).
func _hostile(creature: NPCController) -> bool:
	var ai := creature.ai_controller
	if ai.target == self:
		return true
	if (ai.target == _player or ai.target is Companion) \
			and ai.get_node_or_null(NodePath(String(ai.get_current_state()))) is CreatureCombatState:
		return true
	return mode == Mode.FOLLOW and creature.health_component != null \
		and creature.health_component.last_attacker == _player


## Un paso de pelea: [hacia dónde, a qué velocidad]. Corre hasta tenerla a tiro, la encara y golpea.
func _fight(up: Vector3, delta: float) -> Array:
	var to := _target.global_position - global_position
	var flat := to - up * to.dot(up)
	var distance := flat.length()
	var toward := _tangent(to)
	# Tensando el arco: suelta a su tiempo, salvo que se le eche encima (entonces, a la mano).
	if _draw_left >= 0.0:
		if distance < BOW_CLOSE:
			_cancel_draw()
		else:
			_face(toward, delta)
			_draw_left -= delta
			if _draw_left < 0.0:
				_loose(up)
			return [Vector3.ZERO, 0.0]
	if _dodge_t >= 0.0:
		_face(toward, delta)
		return _dodging(delta)
	if _attack_left > 0.0 or _guard_up:
		_face(toward, delta)
		return [Vector3.ZERO, 0.0]
	# Nadando no golpea: va hacia ella.
	if _swimming:
		return [toward, SWIM_FAST]
	if distance > BOW_MIN and _can_shoot():
		# Muy lejos o sin verla, se acerca; si no, quieto, la encara y tensa.
		if distance > BOW_RANGE or not _clear_shot():
			var near := steer(_target.global_position, BOW_RANGE * 0.6, delta, true)
			return [near if near != Vector3.ZERO else toward, RUN_SPEED]
		_face(toward, delta)
		_pause_left -= delta
		if _pause_left <= 0.0 and toward != Vector3.ZERO and _forward.angle_to(toward) < deg_to_rad(20.0):
			_draw()
		return [Vector3.ZERO, 0.0]
	if _bow_out:
		# Se le ha echado encima (o no le quedan flechas): guarda el arco y saca lo de la mano.
		_bow_out = false
		_show_weapon()
	var reach := _reach_to(_target)
	if distance > reach:
		# En línea recta y, si algo se lo impide, por un camino (steer).
		var heading := steer(_target.global_position, reach * 0.8, delta, true)
		return [heading if heading != Vector3.ZERO else toward,
			remap(clampf(distance, reach, SPRINT_FROM), reach, SPRINT_FROM, RUN_SPEED, SPRINT_SPEED)]
	_face(toward, delta)
	_pause_left -= delta
	if _pause_left <= 0.0 and toward != Vector3.ZERO and _forward.angle_to(toward) < deg_to_rad(40.0):
		_swing()
	return [Vector3.ZERO, 0.0]


## Lo que hay del centro de él al de [creature] cuando la alcanza: los dos cuerpos, el brazo y el arma.
func _reach_to(creature: NPCController) -> float:
	var radius := 0.5
	var capsule := creature.collision_shape.shape as CapsuleShape3D if creature.collision_shape != null else null
	if capsule != null:
		radius = capsule.radius * creature.collision_shape.global_basis.get_scale().x
	return radius + Villager.BODY_RADIUS + ARM + (_weapon.reach if _weapon != null else 0.0)


## Empieza un golpe: de arriba abajo con lo contundente y las hachas, de lado con lo demás.
func _swing() -> void:
	var blunt := _weapon == null or _weapon.damage_kind == ItemData.DamageKind.BLUNT \
		or _weapon.tool_type == ItemData.ToolType.AXE
	var move: Dictionary = MeleeMoveset.VERTICAL if blunt else MeleeMoveset.HORIZONTAL
	_play(move.anim, 0.12, true)
	_anim_player.speed_scale = ATTACK_SPEED
	var window: Vector2 = move.hit
	_hit_at = (window.x + window.y) * 0.5 / ATTACK_SPEED
	_attack_left = float(move.end) / ATTACK_SPEED
	_pause_left = _rng.randf_range(ATTACK_PAUSE.x, ATTACK_PAUSE.y)
	_show_weapon()


## El golpe llega: si la fiera sigue a tiro y delante, le da en el cuerpo.
func _land_hit(up: Vector3) -> void:
	if not _alive(_target) or _target.hurtboxes.is_empty():
		return
	var to := _target.global_position - global_position
	var flat := to - up * to.dot(up)
	if flat.length() > _reach_to(_target) + 0.5 or _forward.angle_to(flat.normalized()) > deg_to_rad(70.0):
		return
	var dir := flat.normalized()
	var point := _target.get_lock_point()
	var damage := maxf(float(_weapon.damage) if _weapon != null else 0.0, FIST_DAMAGE) * DAMAGE_SCALE
	var poise := (_weapon.poise_damage if _weapon != null else 10.0) * DAMAGE_SCALE
	var info := DamageInfo.create(damage, self, point, dir, poise)
	info.kind = _weapon.damage_kind if _weapon != null and _weapon.damage > 0 else ItemData.DamageKind.BLUNT
	info.penetration = _weapon.armor_penetration if _weapon != null else 0.0
	info.knockback = 0.3
	if _target.hurtboxes[0].receive(info) > 0.0:
		CombatFx.blood(_target, point, dir, info.kind, info.amount)
		CombatFx.impact(self, point, info.kind, true)


func _show_weapon() -> void:
	_armed_left = ARMED_TIME
	if _tool != null:
		_tool.visible = not _bow_out


# --- Arco -----------------------------------------------------------------------------------------

## Si puede disparar: lleva arco y le quedan flechas.
func _can_shoot() -> bool:
	return gear.bow != null and gear.ammo_left(pack) > 0


## Si desde el pecho ve la fiera (nada del mundo entre medias).
func _clear_shot() -> bool:
	var from := global_position + up_direction * 1.4
	var query := PhysicsRayQueryParameters3D.create(from, _target.get_lock_point(), PhysicsLayers.WORLD,
		[get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Saca el arco (guarda lo de la mano) y empieza a tensar: saca la flecha, la encaja y tensa.
func _draw() -> void:
	_bow_out = true
	_armed_left = ARMED_TIME
	if _tool != null:
		_tool.visible = false
	_lower_guard()
	_play(ANIM_BOW_DRAW, 0.15, true)
	_anim_player.speed_scale = BOW_DRAW_SPEED
	var length := _anim_player.get_animation(ANIM_BOW_DRAW).length / BOW_DRAW_SPEED \
		if _anim_player.has_animation(ANIM_BOW_DRAW) else 1.0
	_draw_left = length + _rng.randf_range(BOW_HOLD.x, BOW_HOLD.y)
	# Mientras tensa, el movimiento no le cambia la animación (_animate).
	_attack_left = _draw_left + 0.05
	_hit_at = -1.0


## Deja de tensar (sin soltar la flecha).
func _cancel_draw() -> void:
	if _draw_left < 0.0:
		return
	_draw_left = -1.0
	_attack_left = 0.0
	_anim = &""


## Suelta la flecha hacia la fiera: adelantándose a lo que corre y a lo que cae la flecha, con algo de
## error. Gasta una flecha del morral.
func _loose(up: Vector3) -> void:
	_draw_left = -1.0
	var bow := gear.bow
	var ammo := gear.ammo()
	if bow == null or ammo == null or pack.get_item_count(ammo) <= 0 or not _alive(_target):
		_attack_left = 0.0
		return
	var from := gear.bow_hand() + _forward * 0.3
	var aim := _target.get_lock_point()
	var speed := maxf(float(bow.projectile_speed), 10.0)
	var flight := from.distance_to(aim) / speed
	aim += _target.velocity * flight
	flight = from.distance_to(aim) / speed
	aim += up * 0.5 * gravity * flight * flight
	var dir := (aim - from).normalized()
	var side := dir.cross(up).normalized()
	dir = dir.rotated(up, deg_to_rad(_rng.randf_range(-BOW_SPREAD, BOW_SPREAD)))
	if side != Vector3.ZERO:
		dir = dir.rotated(side, deg_to_rad(_rng.randf_range(-BOW_SPREAD, BOW_SPREAD) * 0.6))
	var projectile := CombatProjectile.new()
	projectile.kind = CombatProjectile.Kind.ARROW
	projectile.shooter = self
	projectile.item_data = ammo
	projectile.planet_node = _player.get("planet")
	projectile.damage = (float(bow.damage) + float(ammo.damage)) * DAMAGE_SCALE
	projectile.poise = bow.poise_damage * DAMAGE_SCALE
	projectile.damage_kind = bow.damage_kind
	projectile.penetration = maxf(bow.armor_penetration, ammo.armor_penetration)
	projectile.set_exclude([get_rid(), _hurtbox.get_rid()])
	get_tree().current_scene.add_child(projectile)
	projectile.launch(from, dir, speed)
	CombatFx.play(&"bow_release", from)
	pack.remove_item(ammo, 1)
	_play(ANIM_BOW_RECOIL, 0.05, true)
	_attack_left = _anim_player.get_animation(ANIM_BOW_RECOIL).length \
		if _anim_player.has_animation(ANIM_BOW_RECOIL) else 0.5
	_pause_left = _rng.randf_range(BOW_PAUSE.x, BOW_PAUSE.y)
	_armed_left = ARMED_TIME


## La pose de brazos (CombatPose) colgada de su esqueleto; la crea si aún no la tiene.
func combat_pose() -> CombatPose:
	if pose == null:
		pose = CombatPose.new()
		pose.name = "CombatPose"
		pose.frame_node = _model
		pose.aim_style = &"bow"
		# Con las animaciones del arquero (bow_draw, bow_recoil): el cuerpo lo pone el clip.
		pose.aim_arms_ik = false
		pose.after_pose = _after_pose
		(_model.get_node("Armature/Skeleton3D") as Skeleton3D).add_child(pose)
	return pose


## Con el arco tensándose o soltando: la pose del arco entra (y sale al guardarlo) y sigue el clip que
## suena, con el tronco hacia la fiera.
func _update_aim(delta: float) -> void:
	var clip := &""
	if _bow_out and (_anim == ANIM_BOW_DRAW or _anim == ANIM_BOW_RECOIL) and _anim_player.is_playing():
		clip = &"bow_draw" if _anim == ANIM_BOW_DRAW else &"bow_recoil"
	_aim = move_toward(_aim, 1.0 if clip != &"" else 0.0, delta * 6.0)
	if pose == null and _aim <= 0.0:
		return
	var p := combat_pose()
	p.aim_weight = smoothstep(0.0, 1.0, _aim)
	p.bow_rig.clip = clip
	p.bow_rig.time = _anim_player.current_animation_position if clip != &"" else 0.0
	if _alive(_target):
		p.aim_dir = (_target.get_lock_point() - gear.bow_hand()).normalized()
	else:
		p.aim_dir = _forward


func _after_pose(p: CombatPose) -> void:
	gear.place_bow(p, p.aim_weight)


# --- Escudo ---------------------------------------------------------------------------------------

## Alza el escudo cuando la fiera va a por él y empieza un golpe (tras reaccionar, y no siempre), y lo
## baja al rato de acabar. Sin escudo, con el arco, nadando o sin pelea, abajo.
func _update_guard(delta: float) -> void:
	_dodge_cool -= delta
	var fighting := _target != null and not _bow_out and _draw_left < 0.0 and not _swimming and _down_left <= 0.0 \
		and not _seated
	var item := _guard_item()
	if not fighting or item == null:
		_lower_guard()
		if fighting and _dodge_t < 0.0:
			_watch_dodge(delta)
		else:
			_guard_seen = false
			_dodge_wait = -1.0
		return
	if _threatened():
		_guard_calm = GUARD_DROP
		if not _guard_up and _guard_wait < 0.0 and not _guard_seen and _attack_left <= 0.0:
			_guard_seen = true
			if _rng.randf() >= GUARD_MISS:
				_guard_wait = _rng.randf_range(GUARD_REACT.x, GUARD_REACT.y)
	else:
		_guard_seen = false
		if _guard_up:
			_guard_calm -= delta
			if _guard_calm <= 0.0:
				_lower_guard()
	if _guard_wait >= 0.0:
		_guard_wait -= delta
		if _guard_wait < 0.0 and _attack_left <= 0.0 and _flinch_left <= 0.0:
			_raise_guard()
	# Alzarlo y encajar un golpe acaban en la pose de sostenerlo (el arma a dos manos va siempre en ella).
	if _guard_up and gear.guard.item == gear.shield and _anim != ANIM_SHIELD_HOLD and not _anim_player.is_playing():
		_play(ANIM_SHIELD_HOLD, 0.1)


## Con qué para ahora: el arma si es a dos manos y para golpes; si no, el escudo; o null.
func _guard_item() -> ItemData:
	if _weapon != null and _weapon.two_handed:
		return _weapon if _weapon.guard_reduction > 0.0 else null
	return gear.shield


## Sin con qué parar: si la fiera va a por él y empieza un golpe, tras reaccionar (y no siempre) esquiva.
func _watch_dodge(delta: float) -> void:
	if _threatened():
		if _dodge_wait < 0.0 and not _guard_seen and _attack_left <= 0.0 and _dodge_cool <= 0.0:
			_guard_seen = true
			if _rng.randf() >= DODGE_MISS:
				_dodge_wait = _rng.randf_range(GUARD_REACT.x, GUARD_REACT.y)
	else:
		_guard_seen = false
	if _dodge_wait >= 0.0:
		_dodge_wait -= delta
		if _dodge_wait < 0.0 and _attack_left <= 0.0 and _flinch_left <= 0.0:
			_start_dodge()


## Paso atrás (o en diagonal) lejos de la fiera, con la pose del jugador.
func _start_dodge() -> void:
	if not _alive(_target) or not gear.stamina.spend(DODGE_COST):
		return
	var away := -_tangent(_target.global_position - global_position)
	if away == Vector3.ZERO:
		away = -_forward
	_dodge_dir = away.rotated(up_direction, deg_to_rad(_rng.randf_range(-DODGE_SIDE, DODGE_SIDE))).normalized()
	_dodge_t = 0.0
	_attack_left = PlayerCombat.BACKSTEP_TIME
	_hit_at = -1.0
	_play(Villager.ANIM_IDLE, 0.08)
	var p := combat_pose()
	p.motion = BodyMotion.BACKSTEP
	p.motion_travel = BodyMotion.backstep_travel
	p.motion_push = (_model.global_basis.inverse() * _dodge_dir).normalized()
	p.motion_distance = PlayerCombat.BACKSTEP_DISTANCE
	p.motion_power = 1.0
	p.motion_left_first = not p.motion_left_first
	p.motion_x = 0.0
	CombatFx.play(&"dodge", global_position)


## Un paso de la esquiva: la velocidad del paso atrás del jugador (se apaga al final y llega a su
## distancia), sin que le den en sus primeras décimas. [hacia dónde, a qué velocidad].
func _dodging(delta: float) -> Array:
	_dodge_t += delta
	var x := clampf(_dodge_t / PlayerCombat.BACKSTEP_TIME, 0.0, 1.0)
	var frames := PlayerCombat.BACKSTEP_IFRAMES
	_hurtbox.set_enabled(not (_dodge_t >= frames.x and _dodge_t <= frames.y))
	if pose != null:
		pose.motion_x = x
	if x >= 1.0:
		_end_dodge()
		return [Vector3.ZERO, 0.0]
	var speed := PlayerCombat.BACKSTEP_DISTANCE / PlayerCombat.BACKSTEP_TIME * 1.3333 * (1.0 - x * x * x)
	return [_dodge_dir, speed]


func _end_dodge() -> void:
	if _dodge_t < 0.0:
		return
	_dodge_t = -1.0
	_dodge_cool = DODGE_COOL
	_hurtbox.set_enabled(true)
	if pose != null:
		pose.motion_x = -1.0


## Si la fiera con la que pelea va a por él y está empezando (o dando) un golpe a su alcance.
func _threatened() -> bool:
	if not _alive(_target) or _target.ai_controller == null or _target.ai_controller.target != self:
		return false
	var situation := _target.get_combat_situation()
	if situation != &"windup" and situation != &"active":
		return false
	return _target.global_position.distance_to(global_position) <= _reach_to(_target) + GUARD_RANGE


func _raise_guard() -> void:
	var item := _guard_item()
	if item == null:
		return
	_guard_up = true
	_guard_wait = -1.0
	gear.guard.item = item
	gear.guard.raise()
	if item == gear.shield:
		_play(ANIM_SHIELD_RAISE, 0.1, true)
		_anim_player.speed_scale = GUARD_RAISE_SPEED
	else:
		_play(ANIM_WEAPON_GUARD, 0.12, true)


func _lower_guard() -> void:
	_guard_wait = -1.0
	if not _guard_up:
		return
	_guard_up = false
	gear.guard.lower()
	gear.guard.item = gear.shield
	_anim = &""


## Ha parado un golpe con el escudo: suena, salta alguna chispa si es metal y lo encaja.
func _on_guard_blocked(info: DamageInfo, _cost: float) -> void:
	var item := gear.guard.item
	if item == null:
		return
	CombatFx.play(item.guard_sound, info.point, {"pitch": _rng.randf_range(0.94, 1.06)})
	if item.guard_sound != &"block_wood":
		CombatFx.sparks(self, info.point, -info.direction, 0.6)
	if _guard_up and item == gear.shield:
		_play(ANIM_SHIELD_HIT, 0.05, true)
		_anim_player.speed_scale = GUARD_HIT_SPEED
	elif _guard_up:
		# Con el arma: encaja el golpe volviendo a la guardia.
		_play(ANIM_WEAPON_GUARD, 0.05, true)


## Sin aguante para pararlo: el escudo cede (lo que pasa del golpe lo hace tambalearse, _on_hit).
func _on_guard_broken(info: DamageInfo) -> void:
	CombatFx.play(&"guard_break", info.point)
	_lower_guard()


# --- Agua -----------------------------------------------------------------------------------------

## Si está en el agua hasta nadar (como el jugador: el mar, los lagos y los ríos están a la altura del
## mar, con las olas que tiene aquí; no en un compartimento seco de un barco). Nadando, hasta que hace pie.
func _update_swim() -> void:
	var loader: Node3D = _player.get("planet")
	var core: Variant = loader.get("planet") if loader != null else null
	if core == null or not core.has_water:
		_set_swimming(false)
		return
	var center := loader.global_position
	var sea: float = core.radius - core.water_radius
	var r := global_position.distance_to(center)
	var sampler := _player.get("water_sampler") as WaterHeightSampler
	var reach := sea + (sampler.max_wave_height() if sampler != null else 0.0)
	if r > reach:
		_set_swimming(false)
		return
	var surface := sea
	if sampler != null:
		surface += sampler.get_height_at(global_position, float(_player.get("current_water_time")),
			loader.get("global_pos"))
	_water_r = surface
	_water_center = center
	var depth := surface - r
	var swim := depth >= SWIM_DEPTH
	if _swimming and not swim:
		# Flotando lleva los pies más arriba que SWIM_DEPTH: sigue nadando mientras no haga pie (el fondo
		# a menos de SWIM_LEAVE m bajo la superficie) y no haya salido del agua.
		var down := (global_position - center) / r
		var bottom := center + down * (surface - SWIM_LEAVE)
		var query := PhysicsRayQueryParameters3D.create(global_position + down * 0.2, bottom,
			PhysicsLayers.WORLD, [get_rid()])
		swim = depth > -0.3 and get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	_set_swimming(swim and not GridManager.is_point_in_dry_interior(global_position))


func _set_swimming(on: bool) -> void:
	if on == _swimming:
		return
	_swimming = on
	floor_snap_length = 0.0 if on else 0.4
	_anim = &""
	if on:
		_lower_guard()
		_cancel_draw()
		_bow_out = false
		_attack_left = 0.0
		_hit_at = -1.0
		work.interrupt()


## Si va nadando.
func is_swimming() -> bool:
	return _swimming


## Le han dado: un respingo (si no está a mitad de golpe), deja de hablar y se revuelve contra quien
## ha sido.
func _on_hit(info: DamageInfo, applied: float) -> void:
	_since_hit = 0.0
	_chatting = false
	# Trepando aguanta: no se suelta ni se revuelve.
	if _climbing:
		return
	# Sentado en su bancada aguanta: no se levanta a pelear (lo levanta una orden o caer malherido).
	if _seated:
		return
	if _target == null and info.source is NPCController and _alive(info.source as NPCController) \
			and mode != Mode.LEAVE and _retreat_left <= 0.0:
		_target = info.source as NPCController
		_show_weapon()
		_to_arms()
	# Lo parado con el escudo lo encaja (_on_guard_blocked); tensando el arco, un golpe le hace soltarlo.
	if applied > 0.0 and _draw_left >= 0.0:
		_cancel_draw()
	if applied > 0.0 and _attack_left <= 0.0 and health.health > 0.0 and info.guarded != Guard.Result.BLOCKED:
		_lower_guard()
		_flinch_left = FLINCH_TIME
		_play(ANIM_HIT, 0.05, true)


## Sin vida: cae y se queda en el suelo DOWN_TIME s (las fieras lo dejan: su vida está a cero).
func _on_down() -> void:
	stand_up()
	_end_climb(false)
	_down_left = DOWN_TIME
	_target = null
	_ordered = false
	_lower_guard()
	_cancel_draw()
	_bow_out = false
	_attack_left = 0.0
	_hit_at = -1.0
	_flinch_left = 0.0
	_chatting = false
	_hurtbox.set_enabled(false)
	_armed_left = 0.0
	if _tool != null:
		_tool.visible = false
	_play(ANIM_DOWN, 0.15)
	var hotbar: Node = _player.get("hotbar") if _player != null and is_instance_valid(_player) else null
	if hotbar != null:
		hotbar.notify(tr("VILLAGER_DOWN") % String(resident.get("name", "")))


func _lie(up: Vector3, delta: float) -> void:
	_down_left -= delta
	_move(Vector3.ZERO, 0.0, up, delta)
	_pose(up)
	if _down_left > 0.0:
		return
	health.revive()
	health.health = MAX_HEALTH * RISE_HEALTH
	health.health_changed.emit(health.health, health.max_health)
	_hurtbox.set_enabled(true)
	_since_hit = 0.0
	_idle = 0.0
	_play(Villager.ANIM_IDLE, 0.8)


## Fuera de pelea: se recupera poco a poco y, si le hace falta, come algo de lo que lleva.
func _recover(delta: float) -> void:
	if health.is_dead or health.health >= health.max_health or _since_hit < REGEN_AFTER \
			or (mode == Mode.SETTLE and meals.wanting()):
		return
	health.heal(REGEN * delta)
	_eat_left -= delta
	if _eat_left > 0.0 or health.get_health_ratio() >= EAT_BELOW:
		return
	_eat_left = EAT_EVERY
	for group in [&"cooked", &"remedy"]:
		for item in pack.get_all_items():
			if item == null or item.data.category != ItemData.Category.CONSUMABLE \
					or ItemTaxonomy.group_of(item.data) != group:
				continue
			pack.remove_item(item.data, 1)
			health.heal(HEAL_FOOD if group == &"cooked" else HEAL_REMEDY)
			return


# --- En la base -----------------------------------------------------------------------------------

## Un paso de su vida en la base: [hacia dónde, a qué velocidad].
func _live(delta: float) -> Array:
	# Lo han mandado volver a su base: va derecho a ella, trotando.
	if homing:
		var home := _terrain.global_transform * base
		if (home - global_position).slide(up_direction).length() > HOME_NEAR:
			_chore = Chore.STAND
			_chore_left = 0.0
			_travel = 0.0
			return [steer(home, HOME_NEAR * 0.8, delta), JOG_SPEED]
		homing = false
	# Acaba de comer o beber: se queda un rato allí.
	if _meal_left > 0.0:
		_meal_left -= delta
		return [Vector3.ZERO, 0.0]
	# Con hambre o sed, antes de nada al comedero o al bebedero (SettlerMeals.trip).
	if _chore != Chore.SLEEP and meals.trip != null:
		var meal := _go_eat(delta)
		if not meal.is_empty():
			return meal
	if _chore != Chore.SLEEP and work.on_duty(_hour()):
		_chore = Chore.STAND
		_chore_left = 0.0
		_look = Vector3.INF
		return work.step(delta)
	if _chore == Chore.WALK:
		var to := _terrain.global_transform * _spot - global_position
		var up := up_direction
		var spot := _terrain.global_transform * _spot
		# Si no llega ni por un camino (STUCK_TELEPORT s atascado tras los intentos), hace allí lo suyo.
		if (to - up * to.dot(up)).length() < ARRIVE or (_stuck > STUCK_TELEPORT and _path_tries >= PATH_TRIES):
			_stuck = 0.0
			_arrive()
			return [Vector3.ZERO, 0.0]
		return [steer(spot, ARRIVE, delta), WALK_SPEED]
	_chore_left -= delta
	var night := work.sleeps(_hour())
	if _chore == Chore.SLEEP:
		_bed_fit_left -= delta
		_sleep_routine.update(delta)
		if _sleep_routine.done():
			_wake()
			_decide()
		elif not night and _sleep_routine.asleep():
			_sleep_routine.get_up()
	elif night or _chore_left <= 0.0:
		_decide()
	if _chore == Chore.SIT and _look.is_finite():
		_face(_terrain.global_transform * _look - global_position, delta)
	return [Vector3.ZERO, 0.0]


## Un paso hacia el comedero o el bebedero (SettlerMeals.trip): [hacia dónde, a qué velocidad], o []
## si ya no va. Al llegar (o si en MEAL_GIVE_UP s no llega) come o bebe allí y se queda un rato de pie,
## de cara a él.
func _go_eat(delta: float) -> Array:
	var at := meals.trip
	if not is_instance_valid(at) or not at.is_inside_tree() or at.is_queued_for_deletion():
		meals.trip = null
		_meal_time = 0.0
		return []
	if _meal_time == 0.0:
		# Deja lo que tenía a medias (el golpe); al volver sigue con su trabajo.
		work.interrupt()
		_chore = Chore.STAND
		_chore_left = 0.0
	_meal_time += delta
	var to := (at.global_position - global_position).slide(up_direction)
	if to.length() > MEAL_REACH and _meal_time < MEAL_GIVE_UP:
		return [steer(at.global_position, MEAL_REACH * 0.8, delta), WALK_SPEED]
	_meal_time = 0.0
	_face(to, delta)
	meals.arrive()
	_rest(Chore.STAND, MEAL_TIME)
	_meal_left = MEAL_TIME
	return [Vector3.ZERO, 0.0]


## Lo siguiente, según la hora: de noche a dormir, al atardecer a la hoguera y si no, por la base.
func _decide() -> void:
	_look = Vector3.INF
	var h := _hour()
	var to_local := _terrain.global_transform.affine_inverse()
	var fire := _fire()
	if work.sleeps(h):
		_bed = _free_bed()
		if _bed != null:
			var foot := _bed.global_position + _bed.global_basis.z * SettlementVillage.BED_FOOT
			_walk_to(to_local * foot, Chore.SLEEP)
		elif fire != null:
			_walk_to(to_local * _ring_spot(fire), Chore.SLEEP)
		else:
			_walk_to(_roam_spot(), Chore.SLEEP)
		return
	var roll := _rng.randf()
	if fire != null and h >= Villager.EVENING_HOUR and roll < 0.7:
		_look = to_local * fire.global_position
		_walk_to(to_local * _ring_spot(fire), Chore.SIT)
	elif roll < 0.5:
		_walk_to(_roam_spot(), Chore.STAND)
	elif roll < 0.75:
		_rest(Chore.SIT, _rng.randf_range(Villager.SIT_TIME.x, Villager.SIT_TIME.y))
	else:
		_rest(Chore.STAND, _rng.randf_range(Villager.STAND_TIME.x, Villager.STAND_TIME.y))


func _walk_to(spot: Vector3, then: Chore) -> void:
	_chore = Chore.WALK
	_spot = spot
	_then = then
	_stuck = 0.0


func _arrive() -> void:
	match _then:
		Chore.SLEEP:
			_lie_down()
		Chore.SIT:
			_rest(Chore.SIT, _rng.randf_range(Villager.SIT_TIME.x, Villager.SIT_TIME.y))
		_:
			_rest(Chore.STAND, _rng.randf_range(Villager.STAND_TIME.x, Villager.STAND_TIME.y))


func _rest(chore: Chore, time: float) -> void:
	_chore = chore
	_chore_left = time


## Se tumba en su petate (si aún está) o donde está.
func _lie_down() -> void:
	_chore = Chore.SLEEP
	_shape.disabled = true
	velocity = Vector3.ZERO
	_sleep_routine.lie_down()
	_anim = &""
	_bed_fit_left = 0.0
	if _bed != null and is_instance_valid(_bed) and _bed.is_inside_tree():
		var up := (_bed.global_position - _terrain.global_position).normalized()
		global_position = _bed.global_position + up * Villager.BED_HEIGHT
		_forward = _tangent(_bed.global_basis.z)
		reset_physics_interpolation()


## Acostado: se apoya en el petate (o en el suelo) con la pose que se ve (Villager.bed_fit). Cambiando de
## pose, a cada una; dormido y quieto, de vez en cuando.
func _on_skeleton_updated() -> void:
	gear.place()
	if _chore != Chore.SLEEP:
		return
	if not _sleep_routine.settling():
		if _bed_fit_left > 0.0:
			return
		_bed_fit_left = Villager.BED_FIT_EVERY
	global_position += up_direction * Villager.bed_fit(_model, up_direction)


## Se levanta: de pie a los pies del petate.
func _wake() -> void:
	if _chore != Chore.SLEEP:
		return
	_sleep_routine.reset()
	_rest(Chore.STAND, 2.0)
	_shape.disabled = false
	if _bed != null and is_instance_valid(_bed) and _bed.is_inside_tree():
		var up := (_bed.global_position - _terrain.global_position).normalized()
		global_position = _bed.global_position + _bed.global_basis.z * SettlementVillage.BED_FOOT + up * 0.05
		reset_physics_interpolation()
	_bed = null


## A pelear: deja lo que hace en la base.
func _to_arms() -> void:
	_wake()
	_look = Vector3.INF
	if mode == Mode.SETTLE:
		_rest(Chore.STAND, 2.0)


func _leave_base() -> void:
	homing = false
	if mode == Mode.SETTLE and base.is_finite():
		return_base = base
		return_work = work.save_data()
	work.stop()
	_wake()
	_look = Vector3.INF
	_chore = Chore.STAND
	base = Vector3.INF


# --- Trabajo (SettlerWork) -----------------------------------------------------------------------

## Hacia dónde andar para llegar a menos de [reach] m (en el plano) de [dest] (mundo): en línea recta y,
## si así no se acerca, por un camino (GroundPath). Lo usan su vida en la base, su trabajo, seguir al
## jugador y la pelea. Con [moving], [dest] se mueve (el jugador, una fiera): no se mide si se acerca
## (yendo detrás no se acerca aunque ande bien) sino si anda lo que quiere (_stuck, de _unstick) o tiene
## una pared delante; y si se mueve, sigue con el camino que llevaba (lo saca de detrás de la pared) y
## luego va derecho. Nadando, siempre derecho.
func steer(dest: Vector3, reach: float, delta: float, moving := false) -> Vector3:
	var to_local := _terrain.global_transform.affine_inverse()
	var from_local := _terrain.global_transform
	var dest_local := to_local * dest
	var slack := maxf(2.0, (dest - global_position).length() * 0.3) if moving else 1.0
	if not _path_dest.is_finite() or _path_dest.distance_to(dest_local) > slack:
		if not moving or not _path_dest.is_finite():
			_path = PackedVector3Array()
		_path_dest = dest_local
		_path_tries = 0
		_steer_best = INF
		_steer_left = REPATH
	_close_doors()
	if _swimming:
		_path = PackedVector3Array()
		return _tangent(dest - global_position)
	var up := up_direction
	# El punto al que va: el siguiente del camino o, sin camino, el destino.
	var aim := dest
	while _path_index < _path.size():
		var point := from_local * _path[_path_index]
		if (point - global_position).slide(up).length() > WAYPOINT:
			aim = point
			break
		_path_index += 1
		_steer_best = INF
		_steer_left = REPATH
	if _path_index >= _path.size():
		_path = PackedVector3Array()
		_path_index = 0
	var distance := (aim - global_position).slide(up).length()
	_search_cool -= delta
	if moving and _path.is_empty():
		# Tras algo que se mueve: busca si no anda lo que quiere o ve una pared, y no muy seguido.
		_steer_best = INF
		var blocked := _stuck > CHASE_STUCK
		if not blocked:
			_look_left -= delta
			if _look_left <= 0.0:
				_look_left = LOOK_EVERY
				blocked = _blocked_ahead(aim, distance, up)
		_steer_left = 0.0 if blocked and _search_cool <= 0.0 else REPATH
	elif distance < _steer_best - PROGRESS:
		_steer_best = distance
		_steer_left = REPATH
	else:
		_steer_left -= delta
		if _steer_left <= -PATH_RETRY:
			_path_tries = 0
	# Con una pared o una ventana delante no espera a atascarse contra ella (solo la primera búsqueda:
	# las demás quedan para cuando de verdad no avance).
	if not moving and _path.is_empty() and _path_tries == 0 and _steer_left > 0.0:
		_look_left -= delta
		if _look_left <= 0.0:
			_look_left = LOOK_EVERY
			if _blocked_ahead(aim, distance, up):
				_steer_left = 0.0
	if _steer_left <= 0.0 and _path_tries < PATH_TRIES:
		_path_tries += 1
		_steer_left = REPATH * 2.0
		_steer_best = INF
		_search_cool = REPATH
		var found := GroundPath.find(self, global_position, dest, up, reach)
		_path = PackedVector3Array()
		for point in found:
			_path.append(to_local * point)
		_path_index = 1 if _path.size() > 1 else 0
	if not _path.is_empty():
		_open_doors(from_local * _path[_path_index])
		_ledge_drop = GroundPath.DROP + 0.2
	return _tangent(aim - global_position)


## Si en línea recta hacia [aim] (a [distance] m) tiene algo delante (no el suelo), a la altura de las
## rodillas o de la cabeza: una ventana deja libre una de las dos (el hueco), una puerta abierta las dos.
func _blocked_ahead(aim: Vector3, distance: float, up: Vector3) -> bool:
	var ahead := (aim - global_position).slide(up)
	if ahead.length_squared() < 0.01:
		return false
	var reach := ahead.normalized() * minf(distance, WALL_LOOK)
	var space := get_world_3d().direct_space_state
	for height in WALL_LOOK_HEIGHTS:
		var from := global_position + up * height
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + reach,
			PhysicsLayers.WORLD, [get_rid()]))
		# Una ladera que sube también da en el rayo; esa se sube andando (su normal mira hacia arriba).
		if not hit.is_empty() and absf((hit.normal as Vector3).dot(up)) < 0.5:
			return true
	return false


## Lo que le queda hasta [dest] (m): por el camino, si va por uno; si no, en línea recta.
func steer_remaining(dest: Vector3) -> float:
	var up := up_direction
	if _path.is_empty() or _path_index >= _path.size():
		return (dest - global_position).slide(up).length()
	var from_local := _terrain.global_transform
	var total := 0.0
	var last := global_position
	for i in range(_path_index, _path.size()):
		var point := from_local * _path[i]
		total += (point - last).slide(up).length()
		last = point
	return total + (dest - last).slide(up).length()


## Abre la puerta cerrada que haya entre él y [next] (el siguiente punto del camino), si está cerca.
func _open_doors(next: Vector3) -> void:
	for node in get_tree().get_nodes_in_group(WoodenDoor.GROUP):
		var door := node as WoodenDoor
		if door == null or door.open_side != 0 or door.global_position.distance_to(global_position) > DOOR_OPEN + 1.5:
			continue
		var size := GroundPath.door_size(door)
		var middle := door.global_transform * Vector3(0.0, minf(size.y * 0.5, 1.0), 0.0)
		var on_way := Geometry3D.get_closest_point_to_segment(middle, global_position, next).distance_to(middle)
		if on_way < size.x * 0.5 + 0.4 and middle.distance_to(global_position) < DOOR_OPEN + size.x * 0.5:
			door.toggle(global_position)
			if not _opened_doors.has(door):
				_opened_doors.append(door)


## Cierra las que abrió al quedar lejos de ellas.
func _close_doors() -> void:
	for i in range(_opened_doors.size() - 1, -1, -1):
		var door := _opened_doors[i]
		if not is_instance_valid(door):
			_opened_doors.remove_at(i)
		elif door.global_position.distance_to(global_position) > DOOR_CLOSE:
			if door.open_side != 0:
				door.toggle(global_position)
			_opened_doors.remove_at(i)


## Pone [data] en la mano, a la vista.
func hold_work_tool(data: ItemData) -> void:
	_bow_out = false
	if data != _weapon or _tool == null:
		_weapon = data
		_tool = Villager.hold(_model, data.scene_path)
	_armed_left = ARMED_TIME
	if _tool != null:
		_tool.visible = true


## Un golpe de trabajo: [anim] a [speed]; mientras, no se cambia de animación (set_busy).
func play_work(anim: StringName, speed: float) -> void:
	_play(anim, 0.12, true)
	_anim_player.speed_scale = speed


## Si tiene el clip [anim] (p. ej. los empalmados de AnimSplice).
func has_anim(anim: StringName) -> bool:
	return _anim_player.has_animation(anim)


## Ocupado [time] s en un golpe: el movimiento no le cambia la animación.
func set_busy(time: float) -> void:
	_attack_left = time
	_hit_at = -1.0


## Un aviso en la barra del jugador.
func notify(text: String) -> void:
	var hotbar: Node = _player.get("hotbar") if _player != null and is_instance_valid(_player) else null
	if hotbar != null:
		hotbar.notify(text)


## Su árbol ha caído (TreeFelling._fell).
func on_felled(falling: FallingTree) -> void:
	work.on_felled(falling)


## Cada paso: los árboles que caen ahora (FallingTree.HAZARD). De cada uno decide una vez si se da
## cuenta (hear_chance; al que lo tala no le hace falta: ya se aparta). Si se ha dado cuenta y está en su
## camino, se aparta (dodge_fall); si no está pero va a meterse (donde estará en LOOK_AHEAD s), se para
## fuera hasta que caiga (_hold_for).
func _watch_falls() -> void:
	var falling := get_tree().get_nodes_in_group(FallingTree.HAZARD)
	if falling.is_empty():
		if not _heard.is_empty():
			_heard.clear()
		_hold_for = null
		return
	if _hold_for != null and (not is_instance_valid(_hold_for) or not _hold_for.is_in_group(FallingTree.HAZARD)):
		_hold_for = null
	if _flee.is_finite():
		return
	for node in falling:
		var tree := node as FallingTree
		if tree == null or tree._chopper == self:
			continue
		var id := tree.get_instance_id()
		if not _heard.has(id):
			_heard[id] = _rng.randf() < hear_chance(global_position.distance_to(tree.hazard_a), _chore == Chore.SLEEP)
		if not _heard[id]:
			continue
		if dodge_fall(tree.hazard_a, tree.hazard_b, tree.hazard_half):
			_hold_for = null
			return
		var ahead := global_position + velocity.slide(up_direction) * LOOK_AHEAD
		if in_fall_path(tree.hazard_a, tree.hazard_b, tree.hazard_half, ahead):
			_hold_for = tree
			return


## Lo probable que es oír caer un árbol a [distance] m (dormido, [asleep], la mitad).
static func hear_chance(distance: float, asleep: bool) -> float:
	var chance := HEAR_SURE_CHANCE if distance <= HEAR_SURE \
		else remap(minf(distance, HEAR_RANGE), HEAR_SURE, HEAR_RANGE, HEAR_SURE_CHANCE, 0.0)
	return chance * (0.5 if asleep else 1.0)


## Si [at] está en el camino del árbol que cae de [a] a [b] con [half] m a cada lado (no detrás del
## tocón ni más allá de la punta con su copa).
func in_fall_path(a: Vector3, b: Vector3, half: float, at: Vector3) -> bool:
	var up := up_direction
	var axis := (b - a).slide(up)
	var length := axis.length()
	if length < 0.1:
		return false
	var dir := axis / length
	var rel := (at - a).slide(up)
	var t := rel.dot(dir)
	if t < -half * 0.5 or t > length + half:
		return false
	return (rel - dir * t).length() <= half + Villager.BODY_RADIUS + FLEE_MARGIN


## Si está en el camino del árbol que cae (in_fall_path), echa a correr para salirse. Falso si no
## estaba en su camino.
func dodge_fall(a: Vector3, b: Vector3, half: float) -> bool:
	var up := up_direction
	var axis := (b - a).slide(up)
	var length := axis.length()
	if length < 0.1:
		return false
	var dir := axis / length
	var rel := (global_position - a).slide(up)
	var t := rel.dot(dir)
	# Detrás del tocón no le cae; más allá de la punta (con su copa), tampoco.
	if t < -half * 0.5 or t > length + half:
		return false
	var side := rel - dir * t
	var reach := half + Villager.BODY_RADIUS + FLEE_MARGIN
	if side.length() > reach:
		return false
	var away := side.normalized() if side.length() > 0.05 else dir.cross(up).normalized() * (1.0 if _rng.randf() < 0.5 else -1.0)
	# Por lo más corto: de lado o, cerca de la base, detrás del tocón.
	var sideways := reach - side.length()
	var backwards := t + half * 0.5 + Villager.BODY_RADIUS
	var spot := a + dir * clampf(t, 0.0, length) + away * (reach + FLEE_EXTRA)
	if backwards < sideways:
		spot = a + side - dir * (half * 0.5 + Villager.BODY_RADIUS + FLEE_EXTRA)
	_flee = _terrain.global_transform.affine_inverse() * spot
	_flee_wait = _rng.randf_range(FLEE_REACT.x, FLEE_REACT.y)
	_flee_left = FLEE_TIME
	return true


## Reacciona al árbol que cae: lo deja todo (sentado, dormido, el golpe de trabajo a medias, la pelea)
## y sale ya a la carrera, sin ir acelerando.
func _start_flee(up: Vector3) -> void:
	stand_up()
	_wake()
	_chore = Chore.STAND
	work.interrupt()
	_lower_guard()
	_cancel_draw()
	_attack_left = 0.0
	_hit_at = -1.0
	_flinch_left = 0.0
	_target = null
	_ordered = false
	_chatting = false
	var heading := _tangent(_terrain.global_transform * _flee - global_position)
	velocity = heading * SPRINT_SPEED + up * velocity.dot(up)
	_anim = &""


## Un paso corriendo a apartarse: derecho y a la carrera (no hay tiempo para buscar camino).
func _run_from_tree(delta: float) -> Array:
	_flee_left -= delta
	var spot := _terrain.global_transform * _flee
	var to := (spot - global_position).slide(up_direction)
	if to.length() < 0.4 or _flee_left <= 0.0:
		_flee = Vector3.INF
		return [Vector3.ZERO, 0.0]
	return [_tangent(to), SPRINT_SPEED]


## Le cae un árbol encima (FallingTree): muere. Suelta lo que lleva y se va al rato.
func crush() -> void:
	if dead:
		return
	dead = true
	_end_climb(false)
	work.stop()
	_wake()
	_lower_guard()
	_cancel_draw()
	_bow_out = false
	_target = null
	_chatting = false
	_attack_left = 0.0
	_down_left = 0.0
	_hurtbox.set_enabled(false)
	health.health = 0.0
	health.health_changed.emit(health.health, health.max_health)
	_armed_left = 0.0
	if _tool != null:
		_tool.visible = false
	_gone_left = GONE_TIME
	_play(ANIM_DOWN, 0.1)
	var up := up_direction
	for item in pack.get_all_items():
		if item != null:
			DroppedItem.spawn_at(get_parent(), item.data, item.quantity, global_position + up * 0.8, -up)
	pack.clear()
	notify(tr("SETTLER_CRUSHED") % String(resident.get("name", "")))


## La hora solar de la base (sin sol, mediodía).
func _hour() -> float:
	var h := Seasons.solar_hour(base)
	return 12.0 if is_nan(h) else h


## Si tiene dónde dormir: el petate en que duerme o uno libre cerca de su base (si no, en el suelo).
func has_bed() -> bool:
	if _bed != null and is_instance_valid(_bed) and _bed.is_inside_tree():
		return true
	return base.is_finite() and _free_bed() != null


## El petate más cercano a la base que no use otro compañero, o null.
func _free_bed() -> Bedroll:
	var center := _terrain.global_transform * base
	var taken := {}
	for node in get_tree().get_nodes_in_group(GROUP):
		var other := node as Companion
		if other != null and other != self and other._bed != null:
			taken[other._bed] = true
	var best: Bedroll
	var best_distance := BASE_RADIUS
	for node in get_tree().get_nodes_in_group(Bedroll.GROUP):
		var bed := node as Bedroll
		if bed == null or not bed.is_inside_tree() or bed.is_queued_for_deletion() or taken.has(bed):
			continue
		var d := bed.global_position.distance_to(center)
		if d < best_distance:
			best = bed
			best_distance = d
	return best


## La hoguera encendida más cercana a la base, o null.
func _fire() -> Campfire:
	var center := _terrain.global_transform * base
	var best: Campfire
	var best_distance := BASE_RADIUS
	for node in get_tree().get_nodes_in_group(Campfire.GROUP):
		var fire := node as Campfire
		if fire == null or not fire.lit or not fire.is_inside_tree():
			continue
		var d := fire.global_position.distance_to(center)
		if d < best_distance:
			best = fire
			best_distance = d
	return best


## Un sitio alrededor de [fire] (mundo).
func _ring_spot(fire: Campfire) -> Vector3:
	var up := (fire.global_position - _terrain.global_position).normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
	return fire.global_position + side.rotated(up, _rng.randf() * TAU) * _rng.randf_range(FIRE_RING.x, FIRE_RING.y)


## Un sitio de la base para pasear (marco del terreno).
func _roam_spot() -> Vector3:
	var up := base.normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
	return base + side.rotated(up, _rng.randf() * TAU) * ROAM * sqrt(_rng.randf())


## La herramienta de su oficio (SettlementPopulation: "job"), o null.
func _job_tool() -> ItemData:
	var job: Dictionary = resident.get("job", {})
	return ItemCatalog.get_item(StringName(job.tool)) if job.has("tool") else null


## Si [data] sirve para golpear con la derecha: un arma o una herramienta con daño que no se dispara.
static func _strikes_with(data: ItemData) -> bool:
	if data == null or data.damage <= 0 or data.is_left_handed() or data.ammo_id != &"":
		return false
	if data.category == ItemData.Category.WEAPON:
		return data.weapon_type != ItemData.WeaponType.CANNON
	return data.category == ItemData.Category.TOOL and data.tool_type != ItemData.ToolType.TORCH \
		and data.tool_type != ItemData.ToolType.FISHING_ROD


## [v] sobre el plano tangente aquí, unitario, o cero.
func _tangent(v: Vector3) -> Vector3:
	var up := (global_position - _terrain.global_position).normalized() if _terrain != null else Vector3.UP
	var t := v - up * v.dot(up)
	return t.normalized() if t.length_squared() > 1e-8 else Vector3.ZERO


## El que el jugador tiene delante en [at] mirando hacia [look] (como Villager.find), o null.
static func find(tree: SceneTree, at: Vector3, look: Vector3, reach := 2.6) -> Companion:
	return Villager.nearest(tree, GROUP, at, look, reach) as Companion


# --- En una bancada -------------------------------------------------------------------------------

## A sentarse en [b] (RowingBench): espera allí sentado (Mode.WAIT) hasta que se le diga que siga.
## Va andando y se sienta; si no llega en BOARD_TIME s, aparece sentado. Falso si no puede.
func board(b: RowingBench) -> bool:
	if b == null or dead or _down_left > 0.0 or mode == Mode.LEAVE or not b.is_free_for(self):
		return false
	if b == bench and _on_bench:
		return true
	stand_up()
	_leave_base()
	_target = null
	_ordered = false
	_chatting = false
	_goto = Vector3.INF
	mode = Mode.WAIT
	_idle = 0.0
	bench = b
	_on_bench = true
	b.occupant = self
	b.seated = false
	_board_left = BOARD_TIME
	_stuck = 0.0
	_path_dest = Vector3.INF
	return true


## Si va sentado en una bancada.
func is_seated() -> bool:
	return _seated


## Si va sentado a un remo.
func is_rowing() -> bool:
	return _seated and is_instance_valid(bench) and bench.has_oar()


## La bancada que tiene (sentado o yendo a ella), o null.
func seat() -> RowingBench:
	return bench if _on_bench and is_instance_valid(bench) else null


## Al cargar: se sentará en la bancada [id] (entity_id) en cuanto aparezca, si aparece pronto.
## Mientras la busca va sin colisión y quieto: se guardó sentado, con la cápsula metida en la
## cubierta, y un CharacterBody solapado con el casco lo empuja como un muro y lo lanza por el aire.
func sit_on_load(id: String) -> void:
	_pending_bench = id
	_pending_left = PENDING_BENCH_TIME
	_shape.disabled = true
	velocity = Vector3.ZERO


## Se levanta de su bancada (o deja de ir a ella) y queda de pie delante de ella.
func stand_up() -> void:
	if _pending_bench != "":
		_pending_bench = ""
		_shape.disabled = _seated
	if not _on_bench:
		return
	var b := bench if is_instance_valid(bench) else null
	bench = null
	_on_bench = false
	if b != null and b.occupant == self:
		b.occupant = null
		b.seated = false
	if not _seated:
		return
	_seated = false
	if _rowing_pose != null:
		_rowing_pose.active = false
		_rowing_pose.bench = null
	_sit_time = -1.0
	_shape.disabled = false
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	set_process(false)
	velocity = Vector3.ZERO
	if b != null and b.is_inside_tree():
		global_position = b.global_transform * RowingBench.STAND
		_forward = _tangent(-b.global_basis.z)
	_pose((global_position - _terrain.global_position).normalized())
	reset_physics_interpolation()
	_play(Villager.ANIM_IDLE, 0.3)


func _find_pending_bench(delta: float) -> void:
	var b := RowingBench.find(get_tree(), _pending_bench)
	if b != null and b.is_free_for(self) and b.is_inside_tree():
		_pending_bench = ""
		if board(b):
			_sit(false)
		else:
			_shape.disabled = false
		return
	_pending_left -= delta
	if _pending_left <= 0.0:
		_pending_bench = ""
		_shape.disabled = false


## Un paso hacia su bancada: [hacia dónde, a qué velocidad]. Al llegar (o al acabarse el tiempo) se sienta.
func _board(up: Vector3, delta: float) -> Array:
	_board_left -= delta
	var to := bench.global_position - global_position
	var flat := to.slide(up).length()
	if (flat < SEAT_REACH and absf(to.dot(up)) < 1.2) or _board_left <= 0.0:
		_sit(flat < SEAT_REACH * 2.0)
		return [Vector3.ZERO, 0.0]
	return [steer(bench.global_position, SEAT_REACH * 0.5, delta), WALK_SPEED if flat < JOG_FROM else JOG_SPEED]


## Un paso hacia el sitio al que va (go_to): [hacia dónde, a qué velocidad]. Al llegar (o al acabarse
## el tiempo) se queda allí esperando.
func _go(up: Vector3, delta: float) -> Array:
	_goto_left -= delta
	var spot := _terrain.global_transform * _goto
	var flat := (spot - global_position).slide(up).length()
	if flat < GOTO_REACH or _goto_left <= 0.0:
		_arrive_spot(false)
		return [Vector3.ZERO, 0.0]
	var heading := steer(spot, GOTO_REACH * 0.8, delta)
	var party := _party()
	if party != null:
		var push := party.apart_from(self, up)
		if push != Vector3.ZERO:
			heading = _tangent(heading + push * 0.5)
	return [heading, WALK_SPEED if flat < JOG_FROM else JOG_SPEED]


## Ya está (o, con [jump], aparece allí: lejos de la vista del jugador): espera en el sitio.
func _arrive_spot(jump: bool) -> void:
	if jump:
		var spot := _terrain.global_transform * _goto
		global_position = spot + (spot - _terrain.global_position).normalized() * 0.1
		reset_physics_interpolation()
	_goto = Vector3.INF
	_idle = 0.0
	_moving = false


## Se sienta en su bancada; con [walked], sentándose desde donde está (la del trono), y si no, de golpe.
func _sit(walked: bool) -> void:
	_seated = true
	bench.seated = true
	_target = null
	_lower_guard()
	_cancel_draw()
	_bow_out = false
	_moving = false
	_shape.disabled = true
	velocity = Vector3.ZERO
	_armed_left = 0.0
	if _tool != null:
		_tool.visible = false
	# Las caderas, en el asiento: se mide con la pose sentada puesta (como el jugador en el trono).
	_anim_player.speed_scale = 1.0
	_anim_player.play(ANIM_SEATED, 0.0)
	_anim_player.advance(0.0)
	var facing := Basis(Vector3.UP, PI)
	_seat_pose = Transform3D(facing, RowingBench.SEAT - facing * _hips_in_body())
	if _rowing_pose == null:
		_rowing_pose = RowingPoseScript.new()
		_rowing_pose.frame_node = self
		_model.get_node("Armature/Skeleton3D").add_child(_rowing_pose)
	_rowing_pose.bench = bench
	_rowing_pose.active = false
	_stand_pose = bench.global_transform.orthonormalized().affine_inverse() * global_transform
	_anim = &""
	if walked and _anim_player.has_animation(ANIM_SIT_DOWN):
		_play(ANIM_SIT_DOWN, 0.15)
		_sit_length = maxf(_anim_player.get_animation(ANIM_SIT_DOWN).length, 0.1)
		_sit_time = 0.0
	else:
		_play(ANIM_SEATED, 0.0)
		_sit_time = -1.0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_process(true)
	_process(0.0)


## Dónde quedan las caderas en su marco, con la pose que tiene ahora.
func _hips_in_body() -> Vector3:
	var skeleton := _model.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	var bone := skeleton.find_bone(HIPS) if skeleton != null else -1
	if bone < 0:
		return Vector3(0.0, 0.55, 0.0)
	var world := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
	return global_transform.affine_inverse() * world


## Sentado va pegado a la bancada en cada fotograma (con la pose interpolada del barco: en el paso
## de física iría un paso por detrás y resbalaría sobre el asiento al navegar).
func _process(delta: float) -> void:
	if not _seated or not is_instance_valid(bench) or not bench.is_inside_tree():
		return
	var frame := bench.get_global_transform_interpolated().orthonormalized()
	if _sit_time >= 0.0:
		_sit_time += delta
		var s := smoothstep(0.0, 1.0, clampf(_sit_time / _sit_length, 0.0, 1.0))
		global_transform = frame * _stand_pose.interpolate_with(_seat_pose, s)
		if _sit_time >= _sit_length:
			_sit_time = -1.0
			_play(ANIM_SEATED, 0.3)
		return
	global_transform = frame * _seat_pose
	_rowing_pose.active = bench.has_oar()
	_forward = _tangent(global_basis.z)
	if _chatting:
		return
	var body := bench.ship()
	var oars := body.oars() if body != null else null
	if oars != null and oars.direction != 0 and bench.is_rowing() and _anim_player.has_animation(ANIM_ROW):
		_play(ANIM_ROW, 0.3)
		_anim_player.speed_scale = 0.0
		var length := _anim_player.get_animation(ANIM_ROW).length
		_anim_player.seek(fposmod(oars.phase() + ROW_PHASE, 1.0) * length, true)
	elif _anim != ANIM_SEATED:
		_play(ANIM_SEATED, 0.3)
