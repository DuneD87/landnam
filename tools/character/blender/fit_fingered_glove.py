"""Fit a sculpted glove from its authored wrist and four landmarks per digit.

Weights are painted in the original mesh topology. Only then is each finger
brought from the sculpt's relaxed pose onto the player's rest phalanges.
"""
import heapq

import numpy as np

from fit_meshy_armor import (BONE_PREFIX, coords, edges_of, normalized, rotation_between,
                             set_coords, smoothstep, strongest_weights)


def digit_field(points, joints):
    """Nearest segment, distance to the finger centre and distance along it."""
    segments = np.diff(joints, axis=0)
    lengths = np.linalg.norm(segments, axis=1)
    directions = segments / lengths[:, None]
    along = ((points[:, None] - joints[:-1]) * directions).sum(axis=2)
    clamped = np.clip(along, 0, lengths)
    delta = points[:, None] - joints[:-1] - directions * clamped[:, :, None]
    squared = (delta ** 2).sum(axis=2)
    nearest = squared.argmin(axis=1)
    rows = np.arange(len(points))
    # Allow points on the palm to fall behind the root knuckle.
    progress = clamped[rows, nearest]
    progress[nearest == 0] = along[nearest == 0, 0]
    return np.sqrt(squared[rows, nearest]), progress + np.r_[0, lengths.cumsum()][nearest], lengths


def surface_distances(neighbours, seeds):
    """Distance along leather, so adjacent but disconnected fingers stay independent."""
    distances = np.full(len(neighbours), np.inf)
    queue = [(0.0, int(i)) for i in seeds]
    distances[seeds] = 0
    heapq.heapify(queue)
    while queue:
        d, i = heapq.heappop(queue)
        if d != distances[i]:
            continue
        for j, step in neighbours[i]:
            new = d + step
            if new < distances[j]:
                distances[j] = new
                heapq.heappush(queue, (new, j))
    return distances


## depth_map(): how far (m) the glove stands off the skin's back and palm,
## and how much thinner than sculpted it may be made (a scale under 1).
DEPTH_CLEARANCE = 0.003
DEPTH_LEAST = 1.0
## Fingers' width over the sculpt's, mapped onto the scan's phalanges.
FINGER_WIDTH = 1.04


def depth_map(glove, skin):
    """The scale and offset (a, b: a * u + b) that take the glove's extent
    from back to palm (`glove`, its points' offsets across) onto the skin's
    (`skin`), DEPTH_CLEARANCE off it; the 2nd to 98th percentiles, so a
    rivet or a fold does not count."""
    g0, g1 = np.percentile(glove, [2, 98])
    s0, s1 = np.percentile(skin, [2, 98])
    s0, s1 = s0 - DEPTH_CLEARANCE, s1 + DEPTH_CLEARANCE
    a = max((s1 - s0) / max(g1 - g0, 1e-4), DEPTH_LEAST)
    return a, (s0 + s1) * 0.5 - a * (g0 + g1) * 0.5


def finger_depth(p, body, side, digit, joints, targets, member, basis, scale, palm, turn):
    """depth_map() for a whole finger, its phalanges' together (each its
    own would shift them apart at the knuckles): the glove's points on it
    (`member` of it) and the scan's skin on its bones, both across each
    phalanx from back to palm."""
    glove, skin = [], []
    lengths = np.linalg.norm(np.diff(joints, axis=0), axis=1)
    for j in range(3):
        old_axis = normalized(basis @ (joints[j + 1] - joints[j]))
        new_axis = normalized(targets[j + 1] - targets[j])
        rotation = turn(old_axis, new_axis)
        normal = rotation @ palm
        normal = normalized(normal - new_axis * (normal @ new_axis))
        offset = (p - joints[j]) @ basis.T * scale
        along = offset @ old_axis
        on = (member > 0.5) & (along > 0.0) & (along < lengths[j] * scale)
        glove.append(((offset[on] - np.outer(along[on], old_axis)) @ rotation.T) @ normal)
        bone = body.index[BONE_PREFIX + f"{side}Hand{digit}{j + 1}"]
        skin.append((body.points[body.top == bone] - targets[j]) @ normal)
    glove, skin = np.concatenate(glove), np.concatenate(skin)
    return depth_map(glove, skin) if len(glove) > 10 and len(skin) > 10 else (1.0, 0.0)


def place(obj, body, side, landmarks):
    p = coords(obj)
    wrist = np.array(landmarks["wrist"])
    src = {digit: np.array(joints) for digit, joints in landmarks["digits"].items()}
    names = list(src)
    dest_wrist = body.joint(side + "Hand")
    dest = {d: np.array([body.joint(f"{side}Hand{d}{j}") for j in range(1, 5)]) for d in names}
    along = normalized(dest["Middle"][0] - dest_wrist)
    width = dest["Index"][0] - dest["Pinky"][0]
    width = normalized(width - along * (along @ width))
    palm = np.cross(along, width) * (1 if side == "Left" else -1)
    # In the sculpt fingers point to -X, the thumb to +Z and the palm to -Y.
    basis = np.stack([-along, -palm, width], axis=1)
    scale = np.linalg.norm(dest["Middle"][0] - dest_wrist) / np.linalg.norm(src["Middle"][0] - wrist)
    rest = (p - wrist) @ basis.T * scale + dest_wrist
    wrist_blend = smoothstep(wrist[0] - 0.15, wrist[0] + 0.15, p[:, 0])
    to_elbow = normalized(body.joint(side + "ForeArm") - dest_wrist)
    cuff_rotation = rotation_between(-along, to_elbow)
    cuff = (rest - dest_wrist) @ cuff_rotation.T + dest_wrist

    fields = [digit_field(p, src[d]) for d in names]
    distance = np.stack([f[0] for f in fields], axis=1)
    closest = np.argsort(distance, axis=1)
    confident = np.take_along_axis(distance, closest[:, 1:2], axis=1)[:, 0] - distance.min(axis=1) > 0.032
    neighbours = [[] for _ in p]
    for a, b in edges_of(obj):
        length = np.linalg.norm(p[a] - p[b])
        neighbours[a].append((b, length))
        neighbours[b].append((a, length))
    geodesic = []
    for i, (_, progress, _) in enumerate(fields):
        seeds = np.flatnonzero(confident & (closest[:, 0] == i) & (progress > 0.015) & (distance[:, i] < 0.16))
        geodesic.append(surface_distances(neighbours, seeds))
    geodesic = np.stack(geodesic, axis=1)
    # Loose ties and rivets need no finger weights. At the web, blend the
    # two roots across a short strip, never across the gap between fingers.
    reach = 0.13
    geo_min = geodesic.min(axis=1)
    membership = np.zeros_like(geodesic)
    valid = geo_min < reach * 2
    membership[valid] = 1 - smoothstep(0, reach, geodesic[valid] - geo_min[valid, None])
    membership /= np.maximum(1.0, membership.sum(axis=1))[:, None]
    membership *= (1 - smoothstep(reach, reach * 2, geo_min))[:, None]

    # The back of the hand and the palm where the scan's are: a hand is
    # thicker from back to palm than the one a glove is sculpted round, and
    # the scan's joints are not halfway through it.
    on_hand = (membership.sum(axis=1) < 0.2) & (wrist_blend < 0.5)
    hand_skin = body.points[body.top == body.index[BONE_PREFIX + side + "Hand"]]
    a, b = depth_map((rest[on_hand] - dest_wrist) @ palm, (hand_skin - dest_wrist) @ palm)
    depth = (rest - dest_wrist) @ palm
    rest += np.outer((a * depth + b - depth) * (1.0 - wrist_blend), palm)
    weights = np.zeros((len(p), len(body.names)))
    placed = np.zeros_like(rest)
    total_finger = np.zeros(len(p))
    depths = {digit: finger_depth(p, body, side, digit, src[digit], dest[digit], membership[:, i], basis,
                                  scale, palm, rotation_between)
              for i, digit in enumerate(names)}
    for i, digit in enumerate(names):
        joints = src[digit]
        targets = dest[digit].copy()
        targets[-1] += 0.005 * normalized(targets[-1] - targets[-2])
        lengths = fields[i][2]
        segments = np.diff(joints, axis=0) / lengths[:, None]
        # Each knuckle bends across a plane bisecting its adjacent phalanges.
        # This keeps the weights continuous around the outside of a curved
        # finger, where a projection onto the nearest segment jumps.
        axes = [segments[0], normalized(segments[0] + segments[1]),
                normalized(segments[1] + segments[2])]
        gates = []
        for joint, axis, band in zip(joints, axes, [0.122, 0.085, 0.073]):
            blend = smoothstep(-band, band, (p - joint) @ axis)
            gates.append(np.minimum(gates[-1], blend) if gates else blend)
        for j in range(3):
            share = membership[:, i] * (gates[j] - gates[j + 1] if j < 2 else gates[j])
            bone = body.index[BONE_PREFIX + f"{side}Hand{digit}{j + 1}"]
            weights[:, bone] = share
            old_axis = normalized(basis @ (joints[j + 1] - joints[j]))
            new_axis = normalized(targets[j + 1] - targets[j])
            rotation = rotation_between(old_axis, new_axis)
            offset = (p - joints[j]) @ basis.T * scale
            projection = offset @ old_axis
            radial = offset - np.outer(projection, old_axis)
            # Register the two joint endpoints exactly, keeping the thickness
            # of the leather independent of phalanx length; from back to
            # palm as thick as the scan's phalanx (depth_map()).
            length_ratio = np.linalg.norm(targets[j + 1] - targets[j]) / (lengths[j] * scale)
            radial = radial @ rotation.T
            normal = rotation @ palm
            normal = normalized(normal - new_axis * (normal @ new_axis))
            depth = radial @ normal
            a, b = depths[digit]
            radial = (radial - np.outer(depth, normal)) * FINGER_WIDTH + np.outer(a * depth + b, normal)
            target = targets[j] + radial + np.outer(projection * length_ratio, new_axis)
            placed += share[:, None] * target
            total_finger += share
    hand = (1 - total_finger) * (1 - wrist_blend)
    forearm = (1 - total_finger) * wrist_blend
    weights[:, body.index[BONE_PREFIX + side + "Hand"]] = hand
    weights[:, body.index[BONE_PREFIX + side + "ForeArm"]] = forearm
    placed += hand[:, None] * rest + forearm[:, None] * cuff
    set_coords(obj, placed)
    if np.linalg.det(basis) < 0:
        obj.data.flip_normals()
    # Fair transitions along the sewn surface. Euclidean averaging would
    # let neighbouring fingers pull one another when making a fist.
    edges = edges_of(obj)
    a, b = np.concatenate([edges, edges[:, ::-1]]).T
    inverse_length = 1 / np.maximum(0.0015, np.linalg.norm(placed[a] - placed[b], axis=1))
    degree = np.maximum(1, np.bincount(a, weights=inverse_length, minlength=len(p)))
    for _ in range(18):
        summed = np.zeros_like(weights)
        np.add.at(summed, a, inverse_length[:, None] * weights[b])
        weights += 0.55 * (summed / degree[:, None] - weights)
    bones, values = strongest_weights(weights)
    for index in np.unique(bones[values > 0]):
        group = obj.vertex_groups.new(name=body.names[index])
        for v, k in zip(*np.where((bones == index) & (values > 0))):
            group.add([int(v)], values[v, k], "REPLACE")


def read_weights(obj, body):
    weights = np.zeros((len(obj.data.vertices), len(body.names)))
    for v in obj.data.vertices:
        for influence in v.groups:
            bone = body.index[obj.vertex_groups[influence.group].name]
            weights[v.index, bone] = influence.weight
    return strongest_weights(weights)
