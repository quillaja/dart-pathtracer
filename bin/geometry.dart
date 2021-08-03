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

  Interaction(this.normal, this.incomingDir, this.outgoingDir, this.mat);
}

class Ray {
  Vector3 origin;
  Vector3 direction;

  Ray(this.origin, this.direction);

  Ray transform(Matrix4 tmatrix) {
    return Ray(
        tmatrix.transformed3(origin),
        // tmatrix
        //     .transformed(Vector4.zero()
        //       ..xyz = origin.xyz.clone()
        //       ..w = 1)
        //     .xyz,
        tmatrix
            .transformed(Vector4.zero()
              ..xyz = direction.xyz.clone()
              ..w = 0)
            .xyz
          ..normalize());
  }
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
    final normal = worldModel.transformed3(h.point!).normalized();
    final incomingDir = -h.r!.direction;
    final outgoingDir = mat.getOutgoingDir(incomingDir, normal);
    return Interaction(normal, incomingDir, outgoingDir, mat);
  }
}
