import 'package:vector_math/vector_math.dart' hide Ray, Sphere;
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
  Interaction surface(Hit h);
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
    /* // this part is replaced by quadratic() and the couple lines after.
    final discriminant = b * b - 4.0 * a * c;

    if (discriminant < 0.0) return Hit.none;

    // local hit location
    var tLocalMin = (-b + sqrt(discriminant)) / (2.0 * a);
    var tLocalMax = (-b - sqrt(discriminant)) / (2.0 * a);
    if (tLocalMin > tLocalMax) {
      // swap if necessary
      final temp = tLocalMin;
      tLocalMin = tLocalMax;
      tLocalMax = temp;
    }
    */
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

  Interaction surface(Hit h) {
    // normal
    final localNormal = worldModel.transformed3(h.point!)..normalize();
    final worldNormal = transformDirection(modelWorld, localNormal);
    // texture coords (cylindrical)
    final u = atan2(localNormal.x, localNormal.z) / (2 * pi) + 0.5;
    final v = localNormal.y * 0.5 + 0.5;
    // ray directions
    final incomingDir = -h.r!.direction;

    final si = Interaction(worldNormal, incomingDir, Vector2(u, v));
    mat.sample(si);
    return si;
  }
}
