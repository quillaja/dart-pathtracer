import 'dart:io';
import 'dart:math';

import 'package:image/image.dart';
import 'package:vector_math/vector_math.dart' hide Ray, Sphere, Plane;

import 'camera.dart';
import 'geometry.dart';
import 'material.dart';
import 'scene.dart';
import 'wavefront_obj.dart';

class Axis {
  static final Vector3 x = Vector3(1, 0, 0);
  static final Vector3 y = Vector3(0, 1, 0);
  static final Vector3 z = Vector3(0, 0, 1);
}

void main(List<String> arguments) async {
  final textureImage = decodePng(File('colorful_grid.png').readAsBytesSync())!;
  final teapotData = ObjData.parseFile('teapot.obj');

  const wallRadius = 5000.0;
  var s = Scene([
    // left object(s)
    // Sphere(Matrix4.compose(Vector3(-2, -1, 1), Quaternion.identity(), Vector3.all(1)),
    //     MirrorMaterial(Vector3(0.95, 0.95, 0.95))), // basic mirror
    // SpecularMaterial(Vector3.all(1), false, 1.0, 1.5)), // glass

    // Plane(
    //     Matrix4.compose(
    //         Vector3(-4, 0, 0),
    //         Quaternion.axisAngle(Vector3(0, 1, -0.4)..normalize(), 3 * pi / 4 - 2 * pi),
    //         Vector3.all(1)),
    // MixMaterial([
    // DiffuseMaterial(Vector3.all(0.95), GridTexture(4, 1e-2)),
    // SpecularMaterial(Vector3.all(0.95), false, 1, 3),
    // DiffuseMaterial(Vector3.all(0.95), ImageTexture(textureImage)),
    // MirrorMaterial(Vector3.all(0.95)),
    // ]),
    // DiffuseMaterial.emitter(Vector3.all(5)),
    // RectExtent(Vector2(7, 5))),
    // CircExtent(1, 4)),

    // right object(s)
    // Cylinder(
    // Matrix4.compose(Vector3(-1, -1, -2), Quaternion.axisAngle(Axis.x, 0), Vector3(1, 1, 1)),
    // DiffuseMaterial(Vector3.all(0.95), ImageTexture(textureImage))),
    // MirrorMaterial(Vector3.all(0.95))),
    // Sphere(Matrix4.translation(Vector3(-1, -2, -2)),
    // DiffuseMaterial(Vector3(0.95, 0.95, 0.95), ImageTexture(textureImage))), // texture
    // DiffuseMaterial(Vector3(0.95, 0.95, 0.95), GridTexture(4, 1e-2))), // texture
    // Sphere(
    //     Matrix4.compose(Vector3(-1, -1, -2),
    //         Quaternion.axisAngle(Vector3(0, 1, 0)..normalize(), pi), Vector3.all(1)),
    //     SpecularMaterial(Vector3(0.95, 0.95, 0.95), false, 1.0, 1.5)), // glass
    // DiffuseMaterial(Vector3(0.95, 0.95, 0.95), ImageTexture(textureImage))),

    // cube
    // TriangleMesh.cube(
    //     Matrix4.compose(
    //         Vector3(1, -1, 0),
    //         Quaternion.axisAngle(Axis.z, -pi / 24) * Quaternion.axisAngle(Axis.y, pi / 3),
    //         Vector3.all(1)),
    //     DiffuseMaterial(Vector3.all(0.95), ImageTexture(textureImage))),

    // teapot
    TriangleMesh.fromObjData(
        Matrix4.compose(
            Vector3(0, 0, 0), Quaternion.axisAngle(Axis.y, -pi / 2), Vector3.all(1.0 / 8.0)),
        // DiffuseMaterial(Vector3.all(0.90), ImageTexture(textureImage)),
        MirrorMaterial(Vector3.all(0.95)),
        teapotData),

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
    // DiffuseMaterial(Vector3(0.7, 0.7, 0.7))),

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
        // DiffuseMaterial(Vector3(0.1, 0.95, 0.1))),
        MirrorMaterial(Vector3.all(0.9))),

    // behind camera wall (light gray) +X
    Sphere(
        Matrix4.compose(
            Vector3(wallRadius + 10, 0, 0), Quaternion.identity(), Vector3.all(wallRadius)),
        DiffuseMaterial(Vector3(0.7, 0.7, 0.7))),

    // light behind camera
    // Plane(
    //     Matrix4.compose(
    //         Vector3(4, 2, 0),
    //         Quaternion.axisAngle(Vector3(0, 1, 0), -pi / 2) *
    //             Quaternion.axisAngle(Vector3(0, 0, 1), -pi / 6),
    //         Vector3.all(1)),
    //     DiffuseMaterial.emitter(Vector3.all(5)),
    //     CircExtent(0, 3)),
  ]);

  final width = arguments.length >= 1 ? int.parse(arguments[0]) : 400;
  final height = arguments.length >= 2 ? int.parse(arguments[1]) : 300;
  final samplesPerPixel = arguments.length >= 3 ? int.parse(arguments[2]) : 16;
  final filename = arguments.length >= 4 ? arguments[3] : 'image.png';

  var film = Film(width, height);
  var cam = Camera(Vector3(3, 2, 0), Vector3.zero(), Vector3(0, 1, 0), pi / 4.0, film);

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
