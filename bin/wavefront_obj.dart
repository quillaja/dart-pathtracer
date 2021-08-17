import 'dart:io';

import 'package:vector_math/vector_math.dart';

void main() {
  const filename = 'test3.obj';
  final obj = ObjData.parseFile(filename);
}

// grammar
// http://www.martinreddy.net/gfx/3d/OBJ.spec
//
// # - comment line
//
// v - vertex, 3+ floats (usually 3)
// vt - vertex texture coord, 1-3 floats (usually 2)
// vn - vertex normal, 3 floats (may not be unit vectors)
//
// f - face, 3+ vertex info indices (v/vt/vn, v//vn, v/vt, v)
//      indices start at 1 (not 0).
//      indices can be negative to indicate 'relative' indices (eg -1 = 1st previously defined vert).
//      vertex format must be consistent per line (?)
//
// o - object name, (optional) 1 string used to name the entire object in the file.
//       has no default value.
// g - group name, (optional) 1+ strings, default = "default".
//       if multiple groups, following elements belong to all groups.
//
// mtllib - material file, 1+ path to .mtl file
// usemtl - use material (name from mtllib) for following elements.

class ObjData {
  // geometry data
  List<Vector3> vertices = [];
  List<Vector3> normals = [];
  List<Vector3> uvs = [];

  // object and group data
  String name = '';
  List<String> materialLib = [];
  Map<String, GroupData> groups = {};

  // comments in file
  List<String> comments = [];

  // Errors encountered while processing the file.
  List<Exception> errors = [];

  // state date while parsing
  String currentMaterial = '';
  List<String> _currentGroups = [];

  List<String> get currentGroups => _currentGroups;
  void set currentGroups(List<String> newNames) {
    _currentGroups = newNames;
    for (final name in newNames) groups.putIfAbsent(name, () => GroupData(name));
  }

  ObjData.parseFile(String filename) {
    final lines = File(filename).readAsLinesSync();

    currentGroups = ['default'];
    final whitespace = RegExp(r'\s+');
    var lineNumber = 1;
    for (var line in lines) {
      // clean and split the line
      line = line.trim().toLowerCase();
      final parts = line.split(whitespace);

      // attempt to process the line
      try {
        if (parts.length >= 1 && parts.first != '') {
          final processor = lineProcessors[parts[0]];
          if (processor == null) throw UnsupportedException(lineNumber, parts[0]);

          processor(parts.sublist(1), this);
        }
      } on UnsupportedException catch (e) {
        errors.add(e);
      } on Exception catch (e) {
        errors.add(ParseException(lineNumber, e.toString()));
      }

      lineNumber++;
    }

    // remove 'default' group if unused
    if (groups['default']!.faces.length == 0) groups.remove('default');

    // state data for 'cleanliness'
    currentGroups = [];
    currentMaterial = '';
  }
}

class ParseException implements Exception {
  int line;
  String message;

  ParseException(this.line, this.message);

  @override
  String toString() => '$line: $message}';
}

class UnsupportedException implements Exception {
  int line;
  String statement;

  UnsupportedException(this.line, this.statement);

  @override
  String toString() => '$line: unsupported statement "$statement"';
}

class GroupData {
  String name;
  List<Face> faces = [];

  GroupData(this.name);

  String toString() => '$name (${faces.length} faces)';
}

class Face {
  List<FaceIndex> indices = []; // will usually be length 3
  String material;

  Face([this.material = '']);

  String toString() => '${indices.join(' ')} $material'.trim();
}

class FaceIndex {
  int v = 0;
  int vt = 0;
  int vn = 0;

  FaceIndex.fromString(String f) {
    // TODO: better error checking
    final parts = f.split('/');
    if (parts.length > 2) vn = int.parse(parts[2]);
    if (parts.length > 1) vt = int.tryParse(parts[1]) ?? 0;
    if (parts.length > 0) v = int.parse(parts[0]);
  }

  void makeIndicesNotWeird(ObjData obj) {
    convertRelativeIndices(obj);
    subtractOne();
  }

  void convertRelativeIndices(ObjData obj) {
    if (v < 0) v = obj.vertices.length + v + 1;
    if (vt < 0) vt = obj.uvs.length + vt + 1;
    if (vn < 0) vn = obj.normals.length + vn + 1;
  }

  void subtractOne() {
    v--;
    vt--;
    vn--;
  }

  String toString() {
    var s = StringBuffer(v);
    if (vt >= 0 || vn >= 0) {
      s.write('/');
      if (vt >= 0) s.write(vt);
      if (vn >= 0) {
        s.write('/');
        s.write(vn);
      }
    }
    return s.toString();
  }
}

typedef LineProcessor = void Function(List<String>, ObjData);

final lineProcessors = <String, LineProcessor>{
  '#': (List<String> parts, ObjData obj) {
    final comment = parts.join(' ').trim();
    if (comment != '') obj.comments.add(comment);
  },
  'o': (List<String> parts, ObjData obj) {
    if (parts.length > 0) obj.name = parts[0];
  },
  'g': (List<String> parts, ObjData obj) {
    obj.currentGroups = parts;
  },
  'mtllib': (List<String> parts, ObjData obj) {
    obj.materialLib.addAll(parts);
  },
  'usemtl': (List<String> parts, ObjData obj) {
    obj.currentMaterial = parts[0];
  },
  'v': (List<String> parts, ObjData obj) {
    if (parts.length != 3) throw Exception('expected 3 numbers. found ${parts.length}');

    var v = Vector3.zero();
    v.x = double.parse(parts[0]);
    v.y = double.parse(parts[1]);
    v.z = double.parse(parts[2]);
    obj.vertices.add(v);
  },
  'vt': (List<String> parts, ObjData obj) {
    if (parts.length < 1 || parts.length > 3)
      throw Exception('expected 1-3 numbers. found ${parts.length}');

    var vt = Vector3.zero();
    vt.x = double.parse(parts[0]);
    vt.y = parts.length >= 2 ? double.parse(parts[1]) : 0;
    vt.z = parts.length >= 3 ? double.parse(parts[2]) : 0;

    obj.uvs.add(vt);
  },
  'vn': (List<String> parts, ObjData obj) {
    if (parts.length != 3) throw Exception('expected 3 numbers. found ${parts.length}');

    var vn = Vector3.zero();
    vn.x = double.parse(parts[0]);
    vn.y = double.parse(parts[1]);
    vn.z = double.parse(parts[2]);
    obj.normals.add(vn);
  },
  'f': (List<String> parts, ObjData obj) {
    if (parts.length < 3) throw Exception('expected 3 or more index groups. found ${parts.length}');

    // parse each vertex index group, and add it to the face
    final f = Face(obj.currentMaterial);
    for (final p in parts) {
      final i = FaceIndex.fromString(p);
      i.makeIndicesNotWeird(obj);
      f.indices.add(i);
    }

    // add the face to all currently 'active' groups
    for (final groupName in obj.currentGroups) obj.groups[groupName]!.faces.add(f);
  },
};
