class_name MarineFaunaProfile extends AmbientFaunaProfile

## Zero permits coast and open sea. Positive values require a shore distance map.
@export var min_offshore_distance: float = 0.0
@export var min_swim_depth: float = 4.0
@export var max_swim_depth: float = 16.0
## Maximum upright extent above/below the origin, including animated fins.
## Horizontal length still uses clearance; long animals need not dive by their length.
@export var vertical_clearance: float = 1.0
## Where the voxel data around the body is not loaded at full detail (far from the
## player), check the seabed against the planetary heightmap instead of rejecting.
## Needed by bodies larger than the region the terrain keeps editable.
@export var use_bathymetry: bool = false
## Extra water under the body when relying on the coarse heightmap.
@export var bathymetry_margin: float = 6.0

@export_group("Attack")
## Boats whose hull centre comes this close are charged and bitten. Zero never attacks.
@export var attack_radius: float = 0.0
## Energy of each bite against the hull, as spent by DynamicGridBody.apply_damage_at.
@export var bite_energy: float = 15000.0
## Radius of the hole a bite tears, in metres.
@export var bite_radius: float = 1.2
## Swimming speed while charging and retreating, relative to the cruise speed.
@export var charge_speed_factor: float = 1.8
## Distance from the hull to reach before turning for another charge.
@export var retreat_distance: float = 45.0
