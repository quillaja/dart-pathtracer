import 'package:image/image.dart';
import 'package:vector_math/vector_math.dart' hide Ray, Sphere;
import 'dart:math';

import 'camera.dart';
import 'geometry.dart';

abstract class Material {
  /// sample() will use the normal and incomingDir to update the Interaction's
  /// outgoingDir, pdf, transfer, and emission members.
  void sample(Interaction si, Random rng);
}

class MirrorMaterial extends Material {
  Vector3 baseColor;

  MirrorMaterial(this.baseColor);

  void sample(Interaction si, Random rng) {
    // flipping normal doesn't *seem* to matter for reflect(), but i'll do
    // it to be certain things are correct.
    si.outgoingDir = reflect(si.incomingDir, flipNormal(si.normal, si.incomingDir));
    si.emission = Vector3.zero();
    si.transfer = baseColor.clone() / dot3(si.outgoingDir, si.normal);
    si.pdf = 1.0;
  }
}

class SpecularMaterial extends Material {
  Vector3 baseColor;
  bool isSolid;
  double etaExternal;
  double etaInternal;

  SpecularMaterial(
      [Vector3? baseColor, bool isSolid = true, double etaExternal = 1.0, double etaInternal = 1.0])
      : baseColor = baseColor ?? Vector3.all(1),
        isSolid = isSolid,
        etaExternal = etaExternal,
        etaInternal = etaInternal;

  void sample(Interaction si, Random rng) {
    // treat solid specular as 'mirror'
    if (isSolid) {
      final m = MirrorMaterial(baseColor);
      m.sample(si, rng);
      return;
    }

    si.emission = Vector3.zero(); // this material can never be an emitter.

    final F = FrDielectric(si.incomingDir, si.normal, etaExternal, etaInternal);
    final p = rng.nextDouble();
    if (p < F) {
      // reflect
      si.outgoingDir = reflect(si.incomingDir, flipNormal(si.normal, si.incomingDir));
      si.pdf = F;
      si.transfer = (baseColor.clone() * F) / dot3(si.outgoingDir, si.normal);
      return;
    } else {
      // refract
      final T = 1.0 - F;
      si.outgoingDir = refract(si.incomingDir, si.normal, etaExternal, etaInternal);
      si.pdf = T;
      si.transfer = (baseColor.clone() * T) / dot3(si.outgoingDir, si.normal);
      return;
    }
  }
}

class DiffuseMaterial extends Material {
  Vector3 baseColor = Vector3(1, 1, 1); // white
  Vector3 emitLight = Vector3.zero(); // no emission
  Texture tex = Texture();

  DiffuseMaterial(this.baseColor, [Texture? tex]) : tex = tex ?? Texture();
  DiffuseMaterial.emitter(this.emitLight);

  void sample(Interaction si, Random rng) {
    // flip normal to match the incoming light direction, or the resulting
    // outgoing direction will be on the incorrect side of the surface.
    si.outgoingDir = cosineSampleHemisphere(flipNormal(si.normal, si.incomingDir), rng);
    si.transfer = baseColor.clone()..multiply(tex.at(si.texCoords));
    si.emission = emitLight.clone();
    si.pdf = dot3(si.outgoingDir, si.normal) / pi; // TODO: hmmm
  }
}

class MixMaterial extends Material {
  final List<Material> mats;

  MixMaterial(this.mats);

  void sample(Interaction si, Random rng) => mats[rng.nextInt(mats.length)].sample(si, rng);
}

class Texture {
  Vector3 at(Vector2 texCoord) => Vector3(1, 1, 1);
}

class GridTexture extends Texture {
  double _lines;
  double _halfWidth;
  Vector3 color;

  GridTexture(int lines, double lineWidthAsPorportion, [Vector3? lineColor])
      : _lines = lines.toDouble(),
        _halfWidth = lineWidthAsPorportion / 2.0,
        color = lineColor ?? Vector3.zero() {}

  Vector3 at(Vector2 texCoord) {
    final x = texCoord.x * _lines;
    final y = texCoord.y * _lines;
    final delta = _halfWidth * _lines;
    for (var i = 0.0; i <= _lines; i++) {
      if ((i - delta <= x && x <= i + delta) || (i - delta <= y && y <= i + delta))
        return color.clone();
    }
    return Vector3(1, 1, 1);
  }
}

class ImageTexture extends Texture {
  Image image;
  Interpolation _interpolation;

  ImageTexture(this.image, [Interpolation interpolation = Interpolation.linear])
      : _interpolation = interpolation;

  Vector3 at(Vector2 texCoord) => colorV3(image.getPixelInterpolate(
      texCoord.x * image.width, (1.0 - texCoord.y) * image.height, _interpolation));
}

Vector3 flipNormal(Vector3 n, Vector3 wo) {
  final cosTheta = dot3(n, wo);
  if (cosTheta < 0) return -n;

  return n.clone();
}

/// wo is a direction from 'base' of n (ie the point where the ray hit).
/// both wo and n should be normalized.
/// assumes (i think) that wo and n are in same hemisphere.
Vector3 reflect(Vector3 wo, Vector3 n) => -wo + n * dot3(wo, n) * 2.0;

/// wo is a (world) direction from the 'base' of n.
/// normal is a (world) normal.
/// etaExternal and etaInternal are the indices of refraction for the inside
///   and outside of the object.
/// does not assume wi and normal are in the same hemisphere.
Vector3 refract(Vector3 wo, Vector3 normal, double etaExternal, double etaInternal) {
  var n = normal.clone();
  var eta = etaExternal / etaInternal;
  var cosThetaI = dot3(n, wo);
  if (cosThetaI < 0) {
    // ray is exiting, so need to 'flip' things.
    n.negate();
    cosThetaI = -cosThetaI; // dot3(n, wo);
    eta = etaInternal / etaExternal;
  }

  var sin2ThetaI = max(0.0, 1.0 - cosThetaI * cosThetaI);
  var sin2ThetaT = eta * eta * sin2ThetaI;

  // Handle total internal reflection for transmission
  if (sin2ThetaT >= 1) return reflect(wo, n);

  var cosThetaT = sqrt(1 - sin2ThetaT);

  return -wo * eta + n * (eta * cosThetaI - cosThetaT);
}

/// use fresnel to compute portion of ray that contributes to reflection.
double FrDielectric(Vector3 wo, Vector3 normal, double etaExternal, double etaInternal) {
  var cosThetaI = dot3(wo, normal);
  if (cosThetaI < 0) {
    // ray is exiting, so need to 'flip', things.
    final temp = etaExternal;
    etaExternal = etaInternal;
    etaInternal = temp;
    cosThetaI = -cosThetaI;
  }

  // <<Compute cosThetaT using Snell’s law>>
  var sinThetaI = sqrt(max(0.0, 1 - cosThetaI * cosThetaI));
  double sinThetaT = etaExternal / etaInternal * sinThetaI;
  // <<Handle total internal reflection>>
  double cosThetaT = sqrt(max(0.0, 1 - sinThetaT * sinThetaT));

  double Rparl = ((etaInternal * cosThetaI) - (etaExternal * cosThetaT)) /
      ((etaInternal * cosThetaI) + (etaExternal * cosThetaT));
  double Rperp = ((etaExternal * cosThetaI) - (etaInternal * cosThetaT)) /
      ((etaExternal * cosThetaI) + (etaInternal * cosThetaT));
  return (Rparl * Rparl + Rperp * Rperp) / 2;
}

/// TODO: uses Random()
Vector2 concentricSampleDisk(Random rng) {
  // <<Map uniform random numbers to [-1,1] >>
  final uOffset = Vector2(rng.nextDouble() * 2 - 1, rng.nextDouble() * 2 - 1);

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

// sample a random direction on the hemisphere about normal.
Vector3 cosineSampleHemisphere(Vector3 normal, Random rng) {
  // Make an orthogonal basis whose third vector is along `direction'
  Vector3 b3 = normal;
  Vector3 different = b3.x.abs() < 0.5 ? Vector3(1.0, 0.0, 0.0) : Vector3(0.0, 1.0, 0.0);
  Vector3 b1 = b3.cross(different).normalized();
  Vector3 b2 = b1.cross(b3);

  var d = concentricSampleDisk(rng);
  var z = sqrt(max(0.0, 1.0 - d.x * d.x - d.y * d.y));
  return (b1 * d.x + b2 * d.y + b3 * z); //.normalized();
}
