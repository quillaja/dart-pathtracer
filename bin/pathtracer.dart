import 'dart:io';
import 'dart:math';

import 'package:image/image.dart';
import 'package:vector_math/vector_math.dart' hide Ray, Sphere;

import 'camera.dart';
import 'geometry.dart';
import 'material.dart';
import 'scene.dart';

void main(List<String> arguments) async {
  final textureImage = decodePng(File('colorful_grid.png').readAsBytesSync())!;

  const wallRadius = 5000.0;
  var s = Scene([
    // upper ball
    Sphere(Matrix4.compose(Vector3(-2, -1, 1), Quaternion.identity(), Vector3.all(1)),
        MirrorMaterial(Vector3(0.95, 0.95, 0.95))), // basic mirror
    // SpecularMaterial(Vector3(0.95, 0.95, 0.95), false, 1.0, 1.5)), // glass

    // lower ball
    Sphere(Matrix4.translation(Vector3(-1, -2, -2)),
        SpecularMaterial(Vector3.all(1), false, 1.0, 1.5)), // glass
    // DiffuseMaterial(Vector3(0.95, 0.95, 0.95), ImageTexture(textureImage))), // texture
    // Sphere(
    //     Matrix4.compose(Vector3(-1, -2, -2),
    //         Quaternion.axisAngle(Vector3(0, 1, 0)..normalize(), pi), Vector3.all(1)),
    //     DiffuseMaterial(Vector3(0.95, 0.95, 0.95), ImageTexture(textureImage))),

    // large white top light
    Sphere(
        Matrix4.compose(
            Vector3(0, wallRadius + 10, 0), Quaternion.identity(), Vector3.all(wallRadius)),
        DiffuseMaterial.emitter(Vector3.all(2.5))),

    // Floor (light gray) -Y
    Sphere(
        Matrix4.compose(
            Vector3(0, -(wallRadius + 3), 0), Quaternion.identity(), Vector3.all(wallRadius)),
        DiffuseMaterial(Vector3(0.7, 0.7, 0.7), ImageTexture(textureImage))),

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

    // behind camera wall (light gray) +X
    Sphere(
        Matrix4.compose(
            Vector3(wallRadius + 10, 0, 0), Quaternion.identity(), Vector3.all(wallRadius)),
        DiffuseMaterial(Vector3(0.7, 0.7, 0.7))),
  ]);

  final width = arguments.length >= 1 ? int.parse(arguments[0]) : 200;
  final height = arguments.length >= 2 ? int.parse(arguments[1]) : 200;
  final samplesPerPixel = arguments.length >= 3 ? int.parse(arguments[2]) : 16;
  final filename = arguments.length >= 4 ? arguments[3] : 'image.png';

  var film = Film(width, height);
  var cam = Camera(Vector3(3, 2, 0), Vector3.zero(), Vector3(0, 1, 0), pi / 2.0, film);

  final start = DateTime.now();
  await renderParallel(s, cam, samplesPerPixel);
  // render(s, cam, samplesPerPixel);
  final took = DateTime.now().difference(start);
  print('took ${fmtHMS(took)}');

  var img = film.develop();
  drawString(img, arial_14, 2, 2, '$width x $height @ $samplesPerPixel spp');
  // drawString(img, arial_14, 2, 18, 'in ${fmtHMS(took)}');
  File(filename).writeAsBytesSync(encodePng(img));
}
