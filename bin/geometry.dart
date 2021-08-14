import 'package:vector_math/vector_math.dart' hide Ray, Sphere, Plane;
import 'material.dart';
import 'dart:math';

class Hit {
  double t;
  Vector3? point;
  Vector3? incomingDir;
  Vector3? normal;
  Vector2? uv;
  Geometry? object;

  Hit(this.t, [this.point, this.incomingDir, this.normal, this.uv, this.object]);

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

    // texture coords (cylindrical)
    final localNormal = pLocal..normalized();
    final u = (atan2(localNormal.x, localNormal.z) + pi) / (2 * pi);
    final v = localNormal.y * 0.5 + 0.5;

    final worldNormal = transformDirection(modelWorld, localNormal);

    return Hit(t, p, -r.direction, worldNormal, Vector2(u, v), this);
  }

  Interaction surface(Hit h, Random rng) {
    final si = Interaction(h.normal!, h.incomingDir!, h.uv!);
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

    // texture coords
    final uv = extent.uv(pLocal.xy);
    // normal
    final worldNormal = transformDirection(modelWorld, Vector3(0, 0, 1));

    return Hit(t, p, -r.direction, worldNormal, uv, this);
  }

  Interaction surface(Hit h, Random rng) {
    final si = Interaction(h.normal!, h.incomingDir!, h.uv!);
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

    // world point and t
    final p = modelWorld.transformed3(pLocal);
    final t = dot3((p - r.origin), r.direction);

    // texCoord
    final u = (atan2(pLocal.y, pLocal.x) + pi) / (2 * pi);
    final v = pLocal.z + 0.5; // pLocal.z should be in [-0.5, 0.5]
    // normal
    final worldNormal = transformDirection(modelWorld, Vector3(pLocal.x, pLocal.y, 0)..normalize());

    return Hit(t, p, -r.direction, worldNormal, Vector2(u, v), this);
  }

  Interaction surface(Hit h, Random rng) {
    final si = Interaction(h.normal!, h.incomingDir!, h.uv!);
    mat.sample(si, rng);
    return si;
  }
}

/// find max dimension of vector. result is index in [0,2].
/// https://www.pbr-book.org/3ed-2018/Geometry_and_Transformations/Vectors#Vector3::MaxDimension
int MaxDimension(Vector3 v) => (v.x > v.y) ? ((v.x > v.z) ? 0 : 2) : ((v.y > v.z) ? 1 : 2);

/// rearrange vector components.
/// https://www.pbr-book.org/3ed-2018/Geometry_and_Transformations/Points#Point3::Permute
Vector3 Permute(Vector3 v, int x, int y, int z) => Vector3(v[x], v[y], v[z]);

/// returns 3 barycentric weights and 1 t-value as Vector4(b0, b1, b1, t).
/// returns null if no intersection.
/// https://www.pbr-book.org/3ed-2018/Shapes/Triangle_Meshes#fragment-Performray--triangleintersectiontest-0
Vector4? rayTriangleIntersection(Ray ray, Vector3 p0, Vector3 p1, Vector3 p2) {
  // <<Transform triangle vertices to ray coordinate space>>
  //  <<Translate vertices based on ray origin>>
  Vector3 p0t = p0 - ray.origin;
  Vector3 p1t = p1 - ray.origin;
  Vector3 p2t = p2 - ray.origin;
  //  <<Permute components of triangle vertices and ray direction>>
  int kz = MaxDimension(ray.direction.clone()..absolute());
  int kx = kz + 1;
  if (kx == 3) kx = 0;
  int ky = kx + 1;
  if (ky == 3) ky = 0;
  Vector3 d = Permute(ray.direction, kx, ky, kz);
  p0t = Permute(p0t, kx, ky, kz);
  p1t = Permute(p1t, kx, ky, kz);
  p2t = Permute(p2t, kx, ky, kz);
  //  <<Apply shear transformation to translated vertex positions>>
  double Sx = -d.x / d.z;
  double Sy = -d.y / d.z;
  double Sz = 1.0 / d.z;
  p0t.x += Sx * p0t.z;
  p0t.y += Sy * p0t.z;
  p1t.x += Sx * p1t.z;
  p1t.y += Sy * p1t.z;
  p2t.x += Sx * p2t.z;
  p2t.y += Sy * p2t.z;

  // <<Compute edge function coefficients e0, e1, and e2>>
  double e0 = p1t.x * p2t.y - p1t.y * p2t.x;
  double e1 = p2t.x * p0t.y - p2t.y * p0t.x;
  double e2 = p0t.x * p1t.y - p0t.y * p1t.x;

  // <<Perform triangle edge and determinant tests>>
  if ((e0 < 0 || e1 < 0 || e2 < 0) && (e0 > 0 || e1 > 0 || e2 > 0)) return null;
  double det = e0 + e1 + e2;
  if (det == 0) return null;

  // <<Compute scaled hit distance to triangle and test against ray  range>>
  p0t.z *= Sz;
  p1t.z *= Sz;
  p2t.z *= Sz;
  double tScaled = e0 * p0t.z + e1 * p1t.z + e2 * p2t.z;
  if (det < 0 && tScaled >= 0)
    return null;
  else if (det > 0 && tScaled <= 0) return null;

  // <<Compute barycentric coordinates and  value for triangle intersection>>
  double invDet = 1 / det;
  double b0 = e0 * invDet;
  double b1 = e1 * invDet;
  double b2 = e2 * invDet;
  double t = tScaled * invDet;

  return Vector4(b0, b1, b2, t);
}

class Vert {
  int p;
  int n;
  int uv;
  Vert(this.p, this.n, this.uv);
}

class TriangleMesh extends Geometry {
  final Material mat;
  List<Vert> triangles = <Vert>[];
  List<Vector3> points = <Vector3>[];
  List<Vector3> normals = <Vector3>[];
  List<Vector2> uvs = <Vector2>[];

  TriangleMesh(Matrix4 modelWorld, this.triangles, this.points, this.normals, this.uvs, this.mat) {
    this.modelWorld = modelWorld;
    this.worldModel = modelWorld.clone()..invert();
  }

  Hit intersect(Ray r) {
    // ray to model space, then test the ray against each triangle.
    final rLocal = r.transform(worldModel);
    var tLocal = double.infinity;
    var minb = Vector4.zero();
    var mini = -1;
    for (var i = 0; i < triangles.length; i += 3) {
      final b = rayTriangleIntersection(
          rLocal, points[triangles[i].p], points[triangles[i + 1].p], points[triangles[i + 2].p]);
      if (b != null && b.w < tLocal) {
        tLocal = b.w;
        minb = b;
        mini = i;
      }
    }
    if (tLocal == double.infinity) return Hit.none;

    // there was a hit.
    // use barycentric coords to find point, normal, uv by performing a
    // weighted average of the corresponding attributes from each vertex.
    final pLocal = points[triangles[mini].p] * minb.x +
        points[triangles[mini + 1].p] * minb.y +
        points[triangles[mini + 2].p] * minb.z;
    final localNormal = normals[triangles[mini].n] * minb.x +
        normals[triangles[mini + 1].n] * minb.y +
        normals[triangles[mini + 2].n] * minb.z;
    final uv = uvs[triangles[mini].uv] * minb.x +
        uvs[triangles[mini + 1].uv] * minb.y +
        uvs[triangles[mini + 2].uv] * minb.z;

    // world point, t, and normal
    final p = modelWorld.transformed3(pLocal);
    final t = dot3((p - r.origin), r.direction);
    final worldNormal = transformDirection(modelWorld, localNormal);

    return Hit(t, p, -r.direction, worldNormal, uv, this);
  }

  Interaction surface(Hit h, Random rng) {
    final si = Interaction(h.normal!, h.incomingDir!, h.uv!);
    mat.sample(si, rng);
    return si;
  }

  TriangleMesh.cube(Matrix4 modelWorld, this.mat) {
    this.modelWorld = modelWorld;
    this.worldModel = modelWorld.clone()..invert();

    this.points = [
      Vector3(0, 0, 0),
      Vector3(1, 0, 0),
      Vector3(0, 1, 0),
      Vector3(1, 1, 0),
      Vector3(0, 0, 1), //4
      Vector3(1, 0, 1),
      Vector3(0, 1, 1),
      Vector3(1, 1, 1),
    ];
    this.points.forEach((p) => p.sub(Vector3.all(0.5))); // translate center to origin

    this.normals = <Vector3>[
      Vector3(1, 0, 0),
      Vector3(0, 1, 0),
      Vector3(0, 0, 1),
      Vector3(-1, 0, 0),
      Vector3(0, -1, 0),
      Vector3(0, 0, -1),
    ];

    this.uvs = [
      Vector2(0, 0),
      Vector2(1, 0),
      Vector2(0, 1),
      Vector2(1, 1),
    ];

    this.triangles = [
      // -z face
      Vert(0, 5, 1),
      Vert(1, 5, 0),
      Vert(2, 5, 3),

      Vert(2, 5, 3),
      Vert(1, 5, 0),
      Vert(3, 5, 2),

      // +z face
      Vert(5, 2, 1),
      Vert(4, 2, 0),
      Vert(7, 2, 3),

      Vert(7, 2, 3),
      Vert(4, 2, 0),
      Vert(6, 2, 2),

      // -y face
      Vert(0, 4, 0),
      Vert(4, 4, 1),
      Vert(1, 4, 2),

      Vert(1, 4, 2),
      Vert(4, 4, 1),
      Vert(5, 4, 3),

      // +y face
      Vert(2, 1, 2),
      Vert(3, 1, 3),
      Vert(6, 1, 0),

      Vert(3, 1, 3),
      Vert(6, 1, 0),
      Vert(7, 1, 1),

      // -x face
      Vert(0, 3, 0),
      Vert(2, 3, 2),
      Vert(6, 3, 3),

      Vert(4, 3, 1),
      Vert(0, 3, 0),
      Vert(6, 3, 3),

      // +x face
      Vert(5, 0, 0),
      Vert(1, 0, 1),
      Vert(7, 0, 2),

      Vert(3, 0, 3),
      Vert(1, 0, 1),
      Vert(7, 0, 2),
    ];
  }
}
