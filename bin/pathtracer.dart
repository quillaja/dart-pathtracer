import 'dart:io';
import 'dart:math';

import 'package:image/image.dart';
import 'package:vector_math/vector_math.dart' hide Ray, Sphere;

import 'camera.dart';
import 'geometry.dart';
import 'material.dart';
import 'scene.dart';

void main(List<String> arguments) {
  const wallRadius = 5000.0;
  var s = Scene([
    // upper ball
    Sphere(Matrix4.translation(Vector3(0, 0, 1)), MirrorMaterial(Vector3(0.95, 0.95, 0.95))),
    //lower ball
    Sphere(Matrix4.translation(Vector3(-1, -2, -2)), DiffuseMaterial(Vector3(0.95, 0.95, 0.95))),

    // large white top light
    Sphere(
        Matrix4.compose(
            Vector3(0, wallRadius + 10, 0), Quaternion.identity(), Vector3.all(wallRadius)),
        DiffuseMaterial.emitter(Vector3(1, 1, 1) * 2)),

    // Floor (white) -Y
    Sphere(
        Matrix4.compose(
            Vector3(0, -(wallRadius + 3), 0), Quaternion.identity(), Vector3.all(wallRadius)),
        DiffuseMaterial(Vector3(0.7, 0.7, 0.7))),
    // Left wall (blueish) +Z
    Sphere(
        Matrix4.compose(
            Vector3(0, 0, wallRadius + 10), Quaternion.identity(), Vector3.all(wallRadius)),
        DiffuseMaterial(Vector3(0.1, 0.1, 0.95))),
    // Right wall (reddish) -Z
    Sphere(
        Matrix4.compose(
            Vector3(0, 0, -(wallRadius + 10)), Quaternion.identity(), Vector3.all(wallRadius)),
        DiffuseMaterial(Vector3(0.95, 0.1, 0.1))),
    // back wall (greenish) -X
    Sphere(
        Matrix4.compose(
            Vector3(-(wallRadius + 10), 0, 0), Quaternion.identity(), Vector3.all(wallRadius)),
        DiffuseMaterial(Vector3(0.1, 0.95, 0.1))),
  ]);

  const width = 400;
  const height = 300;
  const samplesPerPixel = 32;

  var film = Film(width, height);
  var cam = Camera(Vector3(3, 1, 0), Vector3.zero(), Vector3(0, 1, 0), pi / 2.0, film);

  final start = DateTime.now();
  render(s, cam, samplesPerPixel);
  final took = DateTime.now().difference(start);
  print('took $took');

  var img = film.develop();
  drawString(img, arial_14, 2, 2, '$width x $height @ $samplesPerPixel spp');
  File('image.png').writeAsBytesSync(encodePng(img));
}
