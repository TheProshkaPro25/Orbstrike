"""Fit the CC0 Vivi neutral face to Vita. Run from the Godot project root."""
import json
import struct
import subprocess
from pathlib import Path

import numpy as np

WORK = Path("build/vita-faces-nov19")
ROOT = Path("assets/avatars/vrm")


class Avatar:
    def __init__(self, name):
        raw = (ROOT / f"{name}.vrm").read_bytes()
        length = struct.unpack_from("<I", raw, 12)[0]
        self.doc = json.loads(raw[20:20 + length])
        self.data = raw[28 + length:]
        self.face = next(m["primitives"] for m in self.doc["meshes"] if "Face" in m["name"])

    def array(self, index):
        acc = self.doc["accessors"][index]
        view = self.doc["bufferViews"][acc["bufferView"]]
        assert "byteStride" not in view
        dtype = {5126: "<f4", 5123: "<u2", 5125: "<u4"}[acc["componentType"]]
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[acc["type"]]
        return np.frombuffer(self.data, dtype, acc["count"] * width,
                             view.get("byteOffset", 0) + acc.get("byteOffset", 0)).reshape(-1, width)

    def attr(self, primitive, key):
        return self.array(primitive["attributes"][key])


def fit():
    vita, vivi = Avatar("Vita"), Avatar("Vivi")
    face = vita.face[0]
    x = vita.attr(face, "POSITION").astype(float)
    y = vivi.attr(vivi.face[0], "POSITION").astype(float)
    assert x.shape == y.shape == (2339, 3)
    for p, q in zip(vita.face, vivi.face, strict=True):
        assert np.array_equal(vita.array(p["indices"]), vivi.array(q["indices"]))
        assert np.array_equal(vita.attr(p, "TEXCOORD_0"), vivi.attr(q, "TEXCOORD_0"))
        assert np.array_equal(vita.attr(p, "POSITION"), x)
        assert np.array_equal(vivi.attr(q, "POSITION"), y)

    body = next(m for m in vita.doc["meshes"] if "Body" in m["name"])
    body_points = np.unique(np.vstack([vita.attr(p, "POSITION")[vita.array(p["indices"]).ravel()]
                                       for p in body["primitives"]]), axis=0)
    body_points = body_points[body_points[:, 1] >= x[:, 1].min() - .015]
    distance = np.min(np.linalg.norm(x[:, None] - body_points, axis=2), axis=1)
    seam = distance < .00001
    assert seam.sum() == 44
    # Rigid orientation and uniform scale from the coincident body boundary.
    # Unique anchors avoid weighting a UV split twice.
    _, ids = np.unique(x[seam], axis=0, return_index=True)
    base, donor = x[seam][ids], y[seam][ids]
    a, b = base - base.mean(0), donor - donor.mean(0)
    u, singular, vt = np.linalg.svd(b.T @ a)
    rotation = u @ vt
    assert np.linalg.det(rotation) > .999
    scale = singular.sum() / np.sum(b * b)
    fitted = (y - donor.mean(0)) @ rotation * scale + base.mean(0)
    # All layers share one continuous mask around the skull and neck openings.
    t = np.clip((distance - .00001) / .016, 0, 1)
    w = (t * t * (3 - 2 * t))[:, None]
    delta = (fitted - x) * w
    normals = vivi.attr(vivi.face[0], "NORMAL") @ rotation
    neutral = vita.attr(face, "NORMAL")
    normals = neutral + w * (normals - neutral)
    normals /= np.linalg.norm(normals, axis=1)[:, None]
    # At full blink the lid margins and eye layers must coincide as on stock Vita.
    # Fade the inverse identity offset into nearby skin using the same mask for
    # coincident vertices across material boundaries.
    eye_layers = [p for p in vita.face if any(part in vita.doc["materials"][p["material"]]["name"]
                  for part in ("EyeWhite", "FaceEyeline", "FaceEyelash", "EyeIris", "EyeHighlight", "EyeExtra"))]
    eye_ids = np.unique(np.concatenate([vita.array(p["indices"]).ravel() for p in eye_layers]))
    eye_distance = np.min(np.linalg.norm(x[:, None] - x[eye_ids], axis=2), axis=1)
    t = np.clip((eye_distance - .004) / .012, 0, 1)
    blink_delta = -delta * (1 - t * t * (3 - 2 * t))[:, None]
    # VRM0 importer turns Unity's front toward +Z with a half-turn about Y.
    axis = [-1, 1, -1]
    WORK.mkdir(parents=True, exist_ok=True)
    with (WORK / "vivi.bin").open("wb") as output:
        for p in vita.face:
            ids = np.unique(vita.array(p["indices"]))
            output.write(struct.pack("<I", len(ids)))
            np.hstack((x[ids] * axis, delta[ids] * axis, normals[ids] * axis,
                       blink_delta[ids] * axis)).astype("<f4").tofile(output)
            print(vita.doc["materials"][p["material"]]["name"],
                  "peak mm", round(np.linalg.norm(delta[ids], axis=1).max() * 1000, 3))
    print("similarity scale", scale, "pinned vertices", seam.sum(),
          "max seam displacement", abs(delta[seam]).max())
    subprocess.run(["godot", "--headless", "--max-fps", "60", "--path", ".", "-s",
                    "tools/avatars/pack_vivi_face.gd"], check=True)


if __name__ == "__main__":
    fit()
