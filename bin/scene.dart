import 'camera.dart';
import 'geometry.dart';
import 'package:vector_math/vector_math.dart' hide Ray, Sphere;

class Scene {
  List<Geometry> objects;

  Scene(this.objects);

  Hit intersect(Ray r) {
    var hits = objects
        .map((o) => o.intersect(r)) // intersect all objects
        .where((h) => h.t > 0.0); // filter out hits behind ray (negative t)

    if (hits.isEmpty) return Hit.none;
    return hits.reduce((m, h) => h.t < m.t ? h : m); // find minium t
  }
}

void render(Scene s, Camera c, int samplesPerPixel) {
  // const samplesPerPixel = 8;

  var pixels = c.film.pixels();
  for (var px in pixels) {
    var r = c.getRay(px);
    var accumlatedLight = Vector3.zero();
    for (int i = 0; i < samplesPerPixel; i++) {
      accumlatedLight += trace(r, s);
    }
    if (accumlatedLight.isNaN) print('nan light $accumlatedLight');
    accumlatedLight.scale(1.0 / samplesPerPixel.toDouble());
    c.film.setAt(px.x.toInt(), px.y.toInt(), accumlatedLight);
  }
}

Vector3 trace(Ray r, Scene s) {
  const maxDepth = 4;
  final ambient = Vector3.zero(); //(0.1, 0.1, 0.1);

  final stack = <Interaction>[];
  for (int d = 0; d < maxDepth; d++) {
    var h = s.intersect(r);
    if (h == Hit.none) break; // early exit

    var si = h.object!.surface(h);
    stack.add(si);

    r.origin = h.point!;
    r.direction = si.outgoingDir;
  }
  // if (stack.length > 0) print(stack.length);

  var light = ambient.clone();
  for (var si in stack.reversed) {
    var f = si.mat.transfer(si.incomingDir, si.outgoingDir);
    var e = si.mat.emission();

    f.multiply(light);
    light += e + f * dot3(si.outgoingDir, si.normal);
  }

  return light;
}
