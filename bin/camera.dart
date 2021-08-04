import 'package:vector_math/vector_math.dart' hide Sphere, Ray;
import 'package:image/image.dart';
import 'geometry.dart';
import 'dart:math';

class Film {
  final int width;
  final int height;
  final List<double> _red;
  final List<double> _green;
  final List<double> _blue;

  Film(int width, int height)
      : width = width,
        height = height,
        _red = List<double>.filled(width * height, 0),
        _green = List<double>.filled(width * height, 0),
        _blue = List<double>.filled(width * height, 0);

  int get length => width * height;

  int _index(int x, int y) => y * width + x;

  Vector3 getAt(int x, int y) =>
      Vector3(_red[_index(x, y)], _green[_index(x, y)], _blue[_index(x, y)]);

  void setAt(int x, int y, Vector3 c) {
    final i = _index(x, y);
    _red[i] = c.x;
    _green[i] = c.y;
    _blue[i] = c.z;
  }

  List<Vector2> pixels() => [
        for (double y = 0; y < height; y++)
          for (double x = 0; x < width; x++) Vector2(x, y)
      ];

  Image develop() {
    final img = Image(width, height);
    // final extremes = _extrema();
    // print(extremes);

    for (int y = 0; y < img.height; y++)
      for (int x = 0; x < img.width; x++) {
        final i = _index(x, y);
        // final colorVec = Vector3(
        //     normalize(_red[i], extremes.x, extremes.y),
        //     normalize(_green[i], extremes.x, extremes.y),
        //     normalize(_blue[i], extremes.x, extremes.y));
        final colorVec = Vector3(_red[i], _green[i], _blue[i]);
        img.setPixel(x, y, v3Color(colorVec));
      }

    return img;
  }

  Vector2 _extrema() {
    var low = double.infinity;
    var high = double.negativeInfinity;
    for (int i = 0; i < _red.length; i++) {
      var r = _red[i];
      var g = _green[i];
      var b = _blue[i];
      // if (r.isNaN || g.isNaN || b.isNaN) print('Nan $i');
      low = min(low, min(r, min(g, b)));
      high = max(high, max(r, max(g, b)));
    }
    // if (low.isInfinite || high.isInfinite) print('inf $low, $high');
    // if (low.isNaN || high.isNaN) print('nan $low, $high');
    return Vector2(low, high);
  }
}

double normalize(double x, double min, double max) => (x - min) / (max - min);
double clamp(double x, double min_, double max_) => max(min_, min(x, max_));

int v3Color(Vector3 color) {
  return 0xff000000 | //alpha
      clamp(color.b * 255, 0, 255).toInt() << 2 * 8 |
      clamp(color.g * 255, 0, 255).toInt() << 1 * 8 |
      clamp(color.r * 255, 0, 255).toInt() << 0 * 8;
}

class Camera {
  final Vector3 position;
  final Vector3 lookAt;
  final Vector3 up;
  final double fov;
  Matrix4 viewproj = Matrix4.identity();

  final Film film;

  Camera(Vector3 position, Vector3 lookAt, Vector3 up, double fov, Film film)
      : position = position,
        lookAt = lookAt,
        up = up,
        fov = fov,
        film = film {
    var view = makeViewMatrix(position, lookAt, up);
    var proj = makePerspectiveMatrix(fov, film.width / film.height, 1e-3, 1e3);
    viewproj = proj * view;
  }

  Ray getRay(Vector2 pixel) {
    // var nearWorld = Vector3.zero();
    var farWorld = Vector3.zero();
    // film.height-y provides inversion of image plane from opengl (origin in left bottom)
    // to 'normal images' (origin in left top)
    // unproject(viewproj, 0, film.width, 0, film.height, pixel.x, film.height - pixel.y, 0.0, nearWorld);
    unproject(
        viewproj, 0, film.width, 0, film.height, pixel.x, film.height - pixel.y, 1.0, farWorld);
    var d = (farWorld - position)..normalize();
    return Ray(position, d);
  }
}
