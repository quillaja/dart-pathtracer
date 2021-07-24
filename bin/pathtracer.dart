import 'dart:io';
import 'dart:math';

import 'package:image/image.dart';
import 'package:vector_math/vector_math.dart' hide Ray, Sphere;

import 'camera.dart';
import 'geometry.dart';
import 'material.dart';
import 'scene.dart';

void main(List<String> arguments) {
  var s = Scene([
    Sphere(Matrix4.identity(), MirrorMaterial(Vector3(0.1, 0.1, 1))),
    Sphere(Matrix4.translation(Vector3(-1, 0, -2)), MirrorMaterial(Vector3(1, 0.1, 0.1))),
    Sphere(Matrix4.compose(Vector3(0, 1000 + 10, 0), Quaternion.identity(), Vector3.all(1000)),
        DiffuseMaterial.emitter(Vector3(1, 1, 1) * 100))
  ]);

  var film = Film(200, 200);
  var cam = Camera(Vector3(3, 0, 0), Vector3.zero(), Vector3(0, 1, 0), pi / 2.0, film);

  render(s, cam, 512);

  var img = film.develop();
  File('image.png').writeAsBytesSync(encodePng(img));

  // var s1 = Sphere(Matrix4.identity(), DiffuseMaterial(Vector3(1, 1, 1)));
  // var s2 = Sphere(Matrix4.translation(Vector3(-1, 0, 0)), DiffuseMaterial(Vector3(1, 1, 1)));
  // var r = cam.getRay(Vector2(0, 0));
  // print(r.origin);
  // print(r.direction);
  // var h = Scene([s1, s2]).intersect(r);
  // print(h.t);
  // print(h.point);
}
