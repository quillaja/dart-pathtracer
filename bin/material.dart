import 'package:vector_math/vector_math.dart' hide Ray, Sphere;
import 'dart:math';

abstract class Material {
  Vector3 emission();
  // eg on 'diffuse' materials, will return the 'base color'
  Vector3 transfer(Vector3 incomingDir, Vector3 outgoingDir);
  // eg on 'diffuse' materials, will return a random direction on the hemisphere,
  // for specular, will produce 'mirror' reflection, etc.
  Vector3 getOutgoingDir(Vector3 incomingDir, Vector3 normal);
}

class MirrorMaterial extends Material {
  final Vector3 baseColor;

  MirrorMaterial(this.baseColor);

  Vector3 emission() => Vector3.zero();

  Vector3 transfer(Vector3 incomingDir, Vector3 outgoingDir) => baseColor;

  Vector3 getOutgoingDir(Vector3 incomingDir, Vector3 normal) {
    return reflect(incomingDir, normal);
  }
}

class DiffuseMaterial extends Material {
  Vector3 baseColor = Vector3(1, 1, 1); // white
  Vector3 emitLight = Vector3.zero(); // no emission

  DiffuseMaterial(this.baseColor);
  DiffuseMaterial.emitter(this.emitLight);

  Vector3 emission() => emitLight;
  Vector3 transfer(Vector3 incomingDir, Vector3 outgoingDir) => baseColor;

  Vector3 getOutgoingDir(Vector3 incomingDir, Vector3 normal) {
    return cosineSampleHemisphere(normal);
  }
}

// wo is a direction from 'base' of n (ie the point where the ray hit).
// both wo and n should be normalized.
Vector3 reflect(Vector3 wo, Vector3 n) => -wo + n * dot3(wo, n) * 2.0;

Vector3 refract(Vector3 wi, Vector3 n, double eta) {
  var cosThetaI = dot3(n, wi);
  var sin2ThetaI = max(0.0, 1.0 - cosThetaI * cosThetaI);
  var sin2ThetaT = eta * eta * sin2ThetaI;
  // Handle total internal reflection for transmission
  if (sin2ThetaT >= 1) return Vector3.zero(); // TODO: return direction for internal reflection

  var cosThetaT = sqrt(1 - sin2ThetaT);

  return -wi * eta + n * (eta * cosThetaI - cosThetaT);
}

/// TODO: uses Random()
Vector2 concentricSampleDisk() {
  // <<Map uniform random numbers to >>
  final uOffset = Vector2(Random().nextDouble() * 2 - 1, Random().nextDouble() * 2 - 1);

  // <<Handle degeneracy at the origin>>
  if (uOffset.x == 0 && uOffset.y == 0) return Vector2.zero();

  // <<Apply concentric mapping to point>>
  double theta, r;
  if (uOffset.x.abs() > uOffset.y.abs()) {
    r = uOffset.x;
    theta = (pi / 4.0) * (uOffset.y / uOffset.x);
  } else {
    r = uOffset.y;
    theta = (pi / 2.0) - (pi / 4.0) * (uOffset.x / uOffset.y);
  }
  return Vector2(cos(theta), sin(theta)) * r;
}

Vector3 cosineSampleHemisphere(Vector3 normal) {
  // Make an orthogonal basis whose third vector is along `direction'
  Vector3 b3 = normal;
  Vector3 different = b3.x.abs() < 0.5 ? Vector3(1.0, 0.0, 0.0) : Vector3(0.0, 1.0, 0.0);
  Vector3 b1 = b3.cross(different).normalized();
  Vector3 b2 = b1.cross(b3);

  var d = concentricSampleDisk();
  var z = sqrt(max(0.0, 1.0 - d.x * d.x - d.y * d.y));
  return (b1 * d.x + b2 * d.y + b3 * z); //.normalized();
}
