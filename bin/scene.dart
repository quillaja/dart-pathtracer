import 'dart:io';
import 'dart:math';

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
  var pixels = c.film.pixels();
  for (var i = 0; i < pixels.length; i++) {
    final complete = (i.toDouble() / pixels.length.toDouble() * 100.0).toStringAsFixed(1);
    stdout.write('\r$complete% complete.');

    final px = pixels[i];
    var accumlatedLight = Vector3.zero();
    for (int i = 0; i < samplesPerPixel; i++) {
      // jitter in ray origin
      final dx = Random().nextDouble() - 0.5;
      final dy = Random().nextDouble() - 0.5;
      final jitterpx = Vector2(px.x + dx, px.y + dy);
      // get ray and trace
      var r = c.getRay(jitterpx);
      accumlatedLight += trace(r, s);
    }
    accumlatedLight.scale(1.0 / samplesPerPixel.toDouble());
    c.film.setAt(px.x.toInt(), px.y.toInt(), accumlatedLight);
  }
  print('');
}

Vector3 trace(Ray r, Scene s) {
  const maxDepth = 8;
  final ambient = Vector3.zero(); //(0.1, 0.1, 0.1);

  var workingRay = r.clone();
  final stack = <Interaction>[];
  for (int d = 0; d < maxDepth; d++) {
    var h = s.intersect(workingRay);
    if (h == Hit.none) break; // early exit

    var si = h.object!.surface(h);
    stack.add(si);
    if (si.mat.emission() != Vector3.zero()) break;

    workingRay.origin = h.point!.clone() + workingRay.direction * 0.001;
    workingRay.direction = si.outgoingDir.clone();
  }
  // if (stack.length > 0) print(stack.length);

  var light = ambient.clone();
  for (var si in stack.reversed) {
    var f = si.mat.transfer(si.incomingDir, si.normal, si.outgoingDir);
    var e = si.mat.emission();

    // light transport equation: Lo = Le + ∫ f(p,wo,wi)* Li(p,wi) * cos(Θi) dw
    f.multiply(light);
    light = e + f * dot3(si.outgoingDir, si.normal);
  }

  return light;
}
