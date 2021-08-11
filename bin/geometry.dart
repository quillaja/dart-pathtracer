import 'package:vector_math/vector_math.dart' hide Ray, Sphere, Plane;
import 'material.dart';
import 'dart:math';

class Hit {
  double t;
  Ray? r;
  Vector3? point;
  Geometry? object;

  Hit(this.t, [this.r, this.object]) {
    this.point = r == null ? null : r!.origin + r!.direction * t;
  }

  static final none = Hit(double.infinity);
}

class Interaction {
  Vector3 normal;
  Vector3 incomingDir;
  Vector3 outgoingDir;
  double pdf;
  Vector3 transfer;
  Vector3 emission;
  Vector2 texCoords;

  Interaction(this.normal, this.incomingDir, this.texCoords)
      : outgoingDir = Vector3.zero(),
        pdf = 0.0,
        transfer = Vector3.zero(),
        emission = Vector3.zero();
}

class Ray {
  Vector3 origin;
  Vector3 direction;

  Ray(this.origin, this.direction);

  Ray transform(Matrix4 tmatrix) =>
      Ray(tmatrix.transformed3(origin), transformDirection(tmatrix, direction));

  Ray clone() => Ray(origin.clone(), direction.clone());
}

Vector3 transformDirection(Matrix4 mat, Vector3 dir) {
  return mat.transformed(Vector4(dir.x, dir.y, dir.z, 0)).xyz..normalize();
}

/// solves quadratic equation using fancy methods that supposedly reduce floating
/// point error. Returns a vector with x=minimum t and y=maximum t, or null
/// if no (real) solution is found.
Vector2? quadratic(double a, double b, double c) {
  // <<Find quadratic discriminant>>
  double discrim = b * b - 4 * a * c;
  if (discrim < 0) return null;
  double rootDiscrim = sqrt(discrim);

  // <<Compute quadratic t values>>
  var t = Vector2.zero();
  double q;
  if (b < 0)
    q = -.5 * (b - rootDiscrim);
  else
    q = -.5 * (b + rootDiscrim);

  t.x = q / a;
  t.y = c / q;
  if (t.x > t.y) {
    final temp = t.x;
    t.x = t.y;
    t.y = temp;
  }
  return t;
}

abstract class Geometry {
  // from world coord system to model coord system
  Matrix4 worldModel = Matrix4.identity();
  // from model coord system to world coord system
  Matrix4 modelWorld = Matrix4.identity();

  Hit intersect(Ray r);
  Interaction surface(Hit h, Random rng);
}

class Sphere extends Geometry {
  Material mat;

  Sphere(Matrix4 modelWorld, Material material) : mat = material {
    this.modelWorld = modelWorld;
    this.worldModel = modelWorld.clone()..invert();
  }

  Hit intersect(Ray r) {
    final rLocal = r.transform(worldModel);

    final oc = rLocal.origin;
    final a = 1.0; //dot3(rLocal.direction, rLocal.direction);
    final b = 2.0 * dot3(oc, rLocal.direction);
    final c = dot3(oc, oc) - 1.0;

    final tVals = quadratic(a, b, c);
    if (tVals == null) return Hit.none;
    var tLocal = tVals.x;
    if (tLocal <= 0.0) {
      tLocal = tVals.y;
    }
    final pLocal = rLocal.origin + rLocal.direction * tLocal;

    // world hit location
    final p = modelWorld.transformed3(pLocal);
    final t = dot3((p - r.origin), r.direction);

    return Hit(t, r, this);
  }

  Interaction surface(Hit h, Random rng) {
    // normal
    final localNormal = worldModel.transformed3(h.point!)..normalize();
    var worldNormal = transformDirection(modelWorld, localNormal);
    // texture coords (cylindrical)
    final u = (atan2(localNormal.x, localNormal.z) + pi) / (2 * pi);
    final v = localNormal.y * 0.5 + 0.5;
    // ray directions
    final incomingDir = -h.r!.direction;

    final si = Interaction(worldNormal, incomingDir, Vector2(u, v));
    mat.sample(si, rng);
    return si;
  }
}

/// Plane is by default a 2d 1x1 square on the x-y plane, with center at the origin
/// and with a face normal towards the positive z axis.
class Plane extends Geometry {
  Material mat;
  Extent extent;

  Plane(Matrix4 modelWorld, Material mat, [Extent? extent])
      : mat = mat,
        extent = extent ?? RectExtent(Vector2.all(1)) {
    this.modelWorld = modelWorld;
    this.worldModel = modelWorld.clone()..invert();
  }

  Hit intersect(Ray r) {
    final rLocal = r.transform(worldModel);

    // check if ray is pointing away from the plane (either from above or below)
    var cosRayPlane = dot3(rLocal.direction, Vector3(0, 0, 1));
    if ((rLocal.origin.z > 0 && cosRayPlane >= 0) || (rLocal.origin.z < 0 && cosRayPlane <= 0))
      return Hit.none;

    // since plane is at z=0, we need to find the t at which the ray's z component is 0;
    final tLocal = cosRayPlane != 0 ? (rLocal.origin.z / cosRayPlane).abs() : 0.0;
    final pLocal = rLocal.origin + rLocal.direction * tLocal;

    // check plane extents
    if (!extent.contains(pLocal.xy)) return Hit.none;

    // world point and t
    final p = modelWorld.transformed3(pLocal);
    final t = dot3((p - r.origin), r.direction);

    return Hit(t, r, this);
  }

  Interaction surface(Hit h, Random rng) {
    final worldNormal = transformDirection(modelWorld, Vector3(0, 0, 1));
    final incomingDir = -h.r!.direction;
    // texture coords
    final pLocal = worldModel.transformed3(h.point!);
    final uv = extent.uv(pLocal.xy);

    final si = Interaction(worldNormal, incomingDir, uv);
    mat.sample(si, rng);
    return si;
  }
}

abstract class Extent {
  bool contains(Vector2 p);
  Vector2 uv(Vector2 p);
}

class RectExtent extends Extent {
  final Vector2 width;
  RectExtent(this.width);
  bool contains(Vector2 p) =>
      (-width.x / 2 <= p.x && p.x <= width.x / 2) && (-width.y / 2 <= p.y && p.y <= width.y / 2);
  Vector2 uv(Vector2 p) => (p + width / 2.0)..divide(width);
}

class CircExtent extends Extent {
  final double innerRadius;
  final double outerRadius;
  CircExtent(this.innerRadius, this.outerRadius);
  bool contains(Vector2 p) => innerRadius <= p.length && p.length <= outerRadius;
  Vector2 uv(Vector2 p) => Vector2((atan2(p.y, p.x) + pi) / (2.0 * pi),
      1.0 - ((p.length - innerRadius) / (outerRadius - innerRadius)));
}

/// A cylinder with radius of 1, height of 1, and center at origin.
class Cylinder extends Geometry {
  final Material mat;

  Cylinder(Matrix4 modelWorld, this.mat) {
    this.modelWorld = modelWorld;
    this.worldModel = modelWorld.clone()..invert();
  }

  Hit intersect(Ray r) {
    final rLocal = r.transform(worldModel);
    final a = rLocal.direction.x * rLocal.direction.x + rLocal.direction.y * rLocal.direction.y;
    final b = 2.0 * (rLocal.direction.x * rLocal.origin.x + rLocal.direction.y * rLocal.origin.y);
    final c = rLocal.origin.x * rLocal.origin.x + rLocal.origin.y * rLocal.origin.y - 1.0;

    final tVals = quadratic(a, b, c);
    if (tVals == null) return Hit.none;
    var tLocal = tVals.x;
    if (tLocal <= 0) tLocal = tVals.y;
    var pLocal = rLocal.origin + rLocal.direction * tLocal;

    // check intersection z-height
    if (pLocal.z < -0.5 || pLocal.z > 0.5) {
      if (tLocal == tVals.y) return Hit.none; // if far hit outsize z-bounds, done
      tLocal = tVals.y; // bad-z-hit is near point, so try far hit point instead
      pLocal = rLocal.origin + rLocal.direction * tLocal;
      if (pLocal.z < -0.5 || pLocal.z > 0.5) return Hit.none; // far hit also beyond z-bounds. done
    }

    final p = modelWorld.transformed3(pLocal);
    final t = dot3((p - r.origin), r.direction);

    return Hit(t, r, this);
  }

  Interaction surface(Hit h, Random rng) {
    // point and normal
    final pLocal = worldModel.transformed3(h.point!);
    final localNormal = Vector3(pLocal.x, pLocal.y, 0)..normalize();
    final worldNormal = transformDirection(modelWorld, localNormal);
    // texCoord
    final u = (atan2(pLocal.y, pLocal.x) + pi) / (2 * pi);
    final v = pLocal.z + 0.5; // pLocal.z should be in [-0.5, 0.5]

    final incomingDir = -h.r!.direction;
    final si = Interaction(worldNormal, incomingDir, Vector2(u, v));
    mat.sample(si, rng);
    return si;
  }
}
