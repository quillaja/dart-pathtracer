import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'camera.dart';
import 'geometry.dart';
import 'package:vector_math/vector_math.dart' hide Ray, Sphere;

import 'workerpool.dart';

// format a Duration to HH:MM:SS.
String fmtHMS(Duration d) => d.toString().split('.').first;

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

  var renderStart = DateTime.now();
  for (var i = 0; i < pixels.length; i++) {
    // status info
    final complete = (i.toDouble() / pixels.length.toDouble()) * 100.0;
    final timeTaken = DateTime.now().difference(renderStart);
    final timeLeft =
        Duration(microseconds: timeTaken.inMicroseconds ~/ (i + 1) * (pixels.length - i));
    stdout.write(
        '\r${complete.toStringAsFixed(1)}% complete. Approx time left: ${fmtHMS(timeLeft)}.');

    // the work
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
    // find intersection
    var h = s.intersect(workingRay);
    if (h == Hit.none) break; // early exit

    // get surface interaction data about the hit
    var si = h.object!.surface(h);
    stack.add(si);
    if (si.emission != Vector3.zero()) break;

    // set working ray to next ray
    workingRay.direction = si.outgoingDir.clone();
    workingRay.origin =
        h.point!.clone() + workingRay.direction * 1e-3; // less than 1e-3 causes banding...
    // NOTE: in above, had to 'advance' the origin of the next ray a small bit along
    // the new direction. Without this, some weird black (no hit?) banding appeared
    // on the giant spheres making up the walls of the scene. I assume due to accumulated
    // floating point error/inaccuracy causing rays that hit the floor to 'enter'
    // the floor and get 'stuck' inside.
    // see: https://www.pbr-book.org/3ed-2018/Shapes/Managing_Rounding_Error
  }

  var light = ambient.clone();
  for (var si in stack.reversed) {
    // light transport equation: Lo = Le + ∫ f(p,wo,wi)* Li(p,wi) * cos(Θi) dw
    si.transfer.multiply(light * dot3(si.outgoingDir, si.normal));
    light = si.emission + si.transfer;
  }

  return light;
}

// parallel rendering ///////////////////////////////////////
// This is slower than single threaded rendering... =(
// Maybe i have to make larger chunks of work.

class PixelJob {
  Vector2 px;
  Scene s;
  Camera c;
  int samplesPerPixel;

  PixelJob(this.px, this.s, this.c, this.samplesPerPixel);
}

class PixelResult {
  Vector2 px;
  Vector3 pxColor;

  PixelResult(this.px, this.pxColor);
}

Future<void> renderParallel(Scene s, Camera c, int samplesPerPixel) async {
  var pool = WorkerPool<PixelJob>(7, pixelWorkFunction);

  var pixels = c.film.pixels();
  var jobs = pixels.map((px) => PixelJob(px, s, c, samplesPerPixel)).toList(growable: false);
  // var jobs = (i, n) => pixels.map((px) => PixelJob(px, s, c, samplesPerPixel)).skip(i).take(n);
  await pool.start();
  var i = 0;
  final startNum = 7 * 2;
  print(startNum);
  for (; i < startNum;) pool.add(jobs[i++]);
  print(pool.jobs);

  print('start result listening loop');
  // var renderStart = DateTime.now();
  await for (var result in pool.results) {
    result = result as PixelResult;
    final x = result.px.x.toInt();
    final y = result.px.y.toInt();
    final color = result.pxColor;
    c.film.setAt(x, y, color);

    pool.add(jobs[i++]);
    pool.done();

    // final numCompleted = pixels.length - pool.jobs;
    // final timeTaken = DateTime.now().difference(renderStart);
    // final timeLeft = Duration(microseconds: timeTaken.inMicroseconds ~/ numCompleted * pool.jobs);
    final percentComplete = (i.toDouble() / jobs.length.toDouble()) * 100.0;
    stdout.write('\r$i ${pool.jobs} ${percentComplete.toStringAsFixed(2)}% complete.');
  }
  pool.stop();
  print('');
}

Future<void> pixelWorkFunction(ReceivePort input, SendPort output) async {
  final rng = Random(DateTime.now().microsecondsSinceEpoch);
  await for (var data in input) {
    data = data as PixelJob;
    final px = data.px;
    final samplesPerPixel = data.samplesPerPixel;
    final s = data.s;
    final c = data.c;

    var accumlatedLight = Vector3.zero();
    for (int i = 0; i < samplesPerPixel; i++) {
      // jitter in ray origin
      final dx = rng.nextDouble() - 0.5;
      final dy = rng.nextDouble() - 0.5;
      final jitterpx = Vector2(px.x + dx, px.y + dy);
      // get ray and trace
      var r = c.getRay(jitterpx);
      accumlatedLight += trace(r, s);
    }
    accumlatedLight.scale(1.0 / samplesPerPixel.toDouble());

    output.send(PixelResult(px, accumlatedLight));
  }
}
