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
  Material mat;
  Vector2 texCoords;

  Interaction(this.normal, this.incomingDir, this.outgoingDir, this.mat, this.texCoords);
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
    final discriminant = b * b - 4.0 * a * c;

    if (discriminant < 0.0) return Hit.none;

    // local hit location
    final tLocal = (-b - sqrt(discriminant)) / (2.0 * a);
    final pLocal = rLocal.origin + rLocal.direction * tLocal;
    // world hit location
    final p = modelWorld.transformed3(pLocal);
    final t = dot3((p - r.origin), r.direction);

    return Hit(t, r, this);
  }

  Interaction surface(Hit h) {
    // normal
    final localNormal = worldModel.transformed3(h.point!).normalized();
    final worldNormal = transformDirection(modelWorld, localNormal);
    // texture coords (cylindrical)
    final u = atan2(localNormal.x, localNormal.z) / (2 * pi) + 0.5;
    final v = localNormal.y * 0.5 + 0.5;
    // ray directions
    final incomingDir = -h.r!.direction;
    final outgoingDir = mat.getOutgoingDir(incomingDir, worldNormal);
    return Interaction(worldNormal, incomingDir, outgoingDir, mat, Vector2(u, v));
  }
}
