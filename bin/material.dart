import 'package:image/image.dart';
import 'package:vector_math/vector_math.dart' hide Ray, Sphere;
import 'dart:math';

import 'camera.dart';
import 'geometry.dart';

abstract class Material {
  /// sample() will use the normal and incomingDir to update the Interaction's
  /// outgoingDir, pdf, transfer, and emission members.
  void sample(Interaction si);
}

class MirrorMaterial extends Material {
  Vector3 baseColor;

  MirrorMaterial(this.baseColor);

  Vector3 emission() => Vector3.zero();

  Vector3 transfer(Interaction si) => baseColor.clone() / dot3(si.outgoingDir, si.normal);

  Vector3 getOutgoingDir(Vector3 incomingDir, Vector3 normal) {
    return reflect(incomingDir, normal);
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

  Vector3 emission() => Vector3.zero();

  Vector3 transfer(Interaction si) {
    final cosTerm = dot3(si.outgoingDir, si.normal);
    if (isSolid) return baseColor.clone() / cosTerm;

    final F = FrDielectric(si.incomingDir, si.normal, etaExternal, etaInternal);
    final p = Random().nextDouble();
    if (p < F) {
      // reflect
      return (baseColor.clone()) / cosTerm;
    } else {
      // refract
      final T = (1.0 - F);
      return (baseColor.clone()) / cosTerm;
    }
  }

  Vector3 getOutgoingDir(Vector3 incomingDir, Vector3 normal) {
    if (isSolid) return reflect(incomingDir, normal);

    final F = FrDielectric(incomingDir, normal, etaExternal, etaInternal);
    final p = Random().nextDouble();
    if (p < F) {
      // reflect
      return reflect(incomingDir, normal);
    } else {
      // refract
      return refract(incomingDir, normal, etaExternal, etaInternal);
    }
  }
}

class DiffuseMaterial extends Material {
  Vector3 baseColor = Vector3(1, 1, 1); // white
  Vector3 emitLight = Vector3.zero(); // no emission
  Texture tex = Texture();

  DiffuseMaterial(this.baseColor, [Texture? tex]) : tex = tex ?? Texture();
  DiffuseMaterial.emitter(this.emitLight);

  Vector3 emission() => emitLight.clone();
  Vector3 transfer(Interaction si) => baseColor.clone()..multiply(tex.at(si.texCoords));

  Vector3 getOutgoingDir(Vector3 incomingDir, Vector3 normal) {
    return cosineSampleHemisphere(normal);
  }
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
    cosThetaI = dot3(n, wo);
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
Vector2 concentricSampleDisk() {
  // <<Map uniform random numbers to [-1,1] >>
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
