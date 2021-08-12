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

/// renders the scene from camera's point of view.
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
      accumlatedLight += trace(r, s, Random());
    }
    accumlatedLight.scale(1.0 / samplesPerPixel.toDouble());
    c.film.setAt(px.x.toInt(), px.y.toInt(), accumlatedLight);
  }
  print('');
}

/// traces a single ray.
Vector3 trace(Ray r, Scene s, Random rng) {
  const maxDepth = 8;
  final ambient = Vector3.zero(); //(0.1, 0.1, 0.1);

  var workingRay = r.clone();
  final stack = <Interaction>[];
  for (int d = 0; d < maxDepth; d++) {
    // find intersection
    var h = s.intersect(workingRay);
    if (h == Hit.none) break; // early exit

    // get surface interaction data about the hit
    var si = h.object!.surface(h, rng);
    stack.add(si);
    if (si.emission != Vector3.zero()) break;

    // set working ray to next ray
    workingRay.direction = si.outgoingDir.clone();
    workingRay.origin = h.point! + workingRay.direction * 1e-3; // less than 1e-3 causes banding...
    // NOTE: in above, had to 'advance' the origin of the next ray a small bit along
    // the new direction. Without this, some weird black (no hit?) banding appeared
    // on the giant spheres making up the walls of the scene. I assume due to accumulated
    // floating point error/inaccuracy causing rays that hit the floor to 'enter'
    // the floor and get 'stuck' inside.
    // see: https://www.pbr-book.org/3ed-2018/Shapes/Managing_Rounding_Error
  }

  var light = ambient.clone();
  for (var si in stack.reversed) {
    // light transport equation: Lo = Le + ∫ f(p,wo,wi)* Li(p,wi) * |cos(Θi)| dw
    si.transfer.multiply(light * dot3(si.outgoingDir, si.normal).abs());
    light = si.emission + si.transfer;
  }

  return light;
}

// parallel rendering ///////////////////////////////////////
// Per-pixel work chunks: This is slower than single threaded rendering... =(
// Maybe i have to make larger chunks of work.
// Region work chunks: works much better.

/// A region on the final image. Currently they're always divided vertically,
/// and regions are the full width of the image.
class Region {
  int id;
  int yStart;
  int yEnd;
  int width;

  Region(this.id, this.yStart, this.yEnd, this.width);
}

/// Data required to render each region.
class RegionJob {
  Region r;
  int samplesPerPixel;
  Scene s;
  RayGenerator rayGenerator;

  RegionJob(this.r, this.samplesPerPixel, this.s, this.rayGenerator);
}

/// A progress update from a worker.
class RegionProgress {
  int id;
  double progress;
  Duration left;
  RegionProgress(this.id, this.progress, this.left);

  static final int col1 = 6;
  static final int col2 = 10;
  static final int col3 = 12;

  static String header() =>
      'region'.padLeft(col1) + 'done'.padLeft(col2 + 1) + 'h:m:s left'.padLeft(col3);

  String toString() =>
      '${id.toString().padLeft(col1)}${(progress * 100).toStringAsFixed(1).padLeft(col2)}%${fmtHMS(left).padLeft(col3)}';
}

/// The render results.
class RegionResult {
  Region r;
  List<Vector3> colors;

  RegionResult(this.r, this.colors);
}

/// A function that orchestrates parallel rendering by creating a worker pool,
/// jobs, and then combining the results.
Future<void> renderParallel(Scene s, Camera c, int samplesPerPixel) async {
  const workers = 6;
  const regions = workers * 2;

  // create jobs
  final regionHeight = c.film.height ~/ regions;
  final leftoverHeight = c.film.height % regions;
  final jobs = <RegionJob>[];
  for (var i = 0; i < regions; i++) {
    var r = Region(i, i * regionHeight, (i + 1) * regionHeight, c.film.width);
    jobs.add(RegionJob(r, samplesPerPixel, s, c.getRayGenerator()));
  }
  if (leftoverHeight > 0) {
    jobs.add(RegionJob(
        Region(jobs.length, jobs.last.r.yEnd, jobs.last.r.yEnd + leftoverHeight, c.film.width),
        samplesPerPixel,
        s,
        c.getRayGenerator()));
  }

  // start worker pool
  var pool = WorkerPool<RegionJob>(workers, regionWorkFunction);
  await pool.start();
  pool.addAll(jobs);
  final progress = <int, RegionProgress>{
    for (var j in jobs) j.r.id: RegionProgress(j.r.id, 0, Duration.zero)
  };

  // listen on results stream
  print('Processing ${jobs.length} regions.');
  print(RegionProgress.header());
  await for (var result in pool.results) {
    if (result is RegionProgress) {
      progress[result.id] = result;
      for (var k in progress.keys) print('${progress[k]}');
      stdout.write('\x1b[${progress.length}A');
    } else if (result is RegionResult) {
      final r = result.r;
      final colors = result.colors;

      var index = 0;
      for (var y = r.yStart; y < r.yEnd; y++) {
        for (var x = 0; x < r.width; x++) {
          c.film.setAt(x, y, colors[index++]);
        }
      }

      pool.done(); // signal that a job was completed
    }
  }
  pool.stop();
  print('\x1b[${progress.length}B');
}

/// Performs the work of actually rendering regions queued up in 'input'.
/// Results are sent back via 'output'.
Future<void> regionWorkFunction(ReceivePort input, SendPort output) async {
  final rng = Random(DateTime.now().microsecondsSinceEpoch);
  await for (var data in input) {
    data = data as RegionJob;
    final r = data.r;
    final samplesPerPixel = data.samplesPerPixel;
    final s = data.s;
    final rayGenerator = data.rayGenerator;

    final result = RegionResult(r, <Vector3>[]);

    final start = DateTime.now();
    for (double y = r.yStart.toDouble(); y < r.yEnd; y++) {
      for (double x = 0.0; x < r.width; x++) {
        var accumlatedLight = Vector3.zero();
        for (int i = 0; i < samplesPerPixel; i++) {
          // jitter in ray origin
          final dx = rng.nextDouble() - 0.5;
          final dy = rng.nextDouble() - 0.5;
          final jitterpx = Vector2(x + dx, y + dy);
          // get ray and trace
          var r = rayGenerator.getRay(jitterpx);
          accumlatedLight += trace(r, s, rng);
        }
        accumlatedLight.scale(1.0 / samplesPerPixel.toDouble());
        result.colors.add(accumlatedLight);
      }

      // figure out estimate for %done and remaining time
      final rowsDone = (1 + y - r.yStart);
      final took = DateTime.now().difference(start);
      final usPerRow = took.inMicroseconds.toDouble() / rowsDone;
      final left = Duration(microseconds: (usPerRow * (r.yEnd - y - 1)).toInt());
      final done = rowsDone / (r.yEnd - r.yStart).toDouble();
      // send progress update
      output.send(RegionProgress(r.id, done, left));
    }
    // send region's rendered result
    output.send(result);
  }
}
