import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import 'models/scan_result.dart';

/// One scan stored by [RoomPlanScanLibrary].
class SavedRoomScan {
  const SavedRoomScan({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.scanResult,
    this.pdfFile,
    this.modelFile,
  });

  /// Stable identifier used by the library's load, rename, and delete methods.
  final String id;

  /// User-provided room name.
  final String name;

  /// Date the library entry was first saved.
  final DateTime createdAt;

  /// Structured scan geometry and metadata.
  final ScanResult scanResult;

  /// Persistent copy of the floor-plan PDF, if one was saved.
  final File? pdfFile;

  /// Persistent copy of the USDZ model, if one was saved.
  final File? modelFile;
}

/// Saves scans and their output files in app-managed persistent storage.
///
/// Each entry contains a JSON record and optional copies of its PDF and USDZ.
/// The default location is the app support directory. Pass [directory] to use
/// an app-controlled location or a temporary directory in tests.
class RoomPlanScanLibrary {
  RoomPlanScanLibrary({Directory? directory}) : _providedDirectory = directory;

  static const _formatVersion = 1;
  final Directory? _providedDirectory;

  /// Saves a new scan and copies any provided outputs into the library.
  ///
  /// The USDZ is copied immediately so it is no longer dependent on the
  /// operating system's temporary-directory retention. A fresh ID is
  /// generated for every save.
  Future<SavedRoomScan> save({
    required String name,
    required ScanResult scanResult,
    File? pdfFile,
    File? modelFile,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A scan name is required.');
    }

    final id = _newId();
    final directory = await _entryDirectory(id);
    await directory.create(recursive: true);
    final createdAt = DateTime.now().toUtc();
    File? savedPdf;
    File? savedModel;

    try {
      if (pdfFile != null) {
        savedPdf = await _copyOutput(pdfFile, directory, 'floor-plan.pdf');
      }
      if (modelFile != null) {
        savedModel = await _copyOutput(modelFile, directory, 'room-model.usdz');
      }
      await _writeRecord(
        directory,
        id: id,
        name: cleanName,
        createdAt: createdAt,
        scanResult: scanResult,
        pdfName: savedPdf?.uri.pathSegments.last,
        modelName: savedModel?.uri.pathSegments.last,
      );
    } catch (_) {
      if (await directory.exists()) await directory.delete(recursive: true);
      rethrow;
    }

    return SavedRoomScan(
      id: id,
      name: cleanName,
      createdAt: createdAt,
      scanResult: scanResult,
      pdfFile: savedPdf,
      modelFile: savedModel,
    );
  }

  /// Copies a standalone output, such as a merged multi-room USDZ, into
  /// persistent app storage and returns its durable file path.
  Future<File> persistOutput(File source, {required String fileName}) async {
    final cleanName = fileName.trim();
    if (cleanName.isEmpty ||
        cleanName.contains('/') ||
        cleanName.contains('\\')) {
      throw ArgumentError.value(fileName, 'fileName', 'Use a plain file name.');
    }
    final root = await _rootDirectory();
    final exports = Directory('${root.path}/exports');
    await exports.create(recursive: true);
    final target = File('${exports.path}/${_newId()}-$cleanName');
    if (!await source.exists() || await source.length() == 0) {
      throw FileSystemException(
        'Cannot save a missing or empty output.',
        source.path,
      );
    }
    return source.copy(target.path);
  }

  /// Lists valid saved scans, newest first.
  Future<List<SavedRoomScan>> listScans() async {
    final root = await _rootDirectory();
    if (!await root.exists()) return const [];
    final scans = <SavedRoomScan>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final scan = await _readEntry(entity);
      if (scan != null) scans.add(scan);
    }
    scans.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return scans;
  }

  /// Loads one saved scan by ID, or returns null if it no longer exists.
  Future<SavedRoomScan?> load(String id) async =>
      _readEntry(await _entryDirectory(_validateId(id)));

  /// Changes the display name of a saved scan.
  Future<SavedRoomScan> rename(String id, String name) async {
    final safeId = _validateId(id);
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A scan name is required.');
    }
    final directory = await _entryDirectory(safeId);
    final record = await _readRecord(directory);
    if (record == null) throw StateError('Saved scan $safeId was not found.');
    record['name'] = cleanName;
    await _writeJsonAtomically(File('${directory.path}/scan.json'), record);
    final renamed = await _readEntry(directory);
    if (renamed == null) {
      throw StateError('Saved scan $safeId could not be read.');
    }
    return renamed;
  }

  /// Deletes a saved scan and its copied output files.
  Future<void> delete(String id) async {
    final directory = await _entryDirectory(_validateId(id));
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  /// Encodes a scan record as portable JSON without embedding PDF/USDZ bytes.
  Future<String> exportJson(String id) async {
    final safeId = _validateId(id);
    final directory = await _entryDirectory(safeId);
    final record = await _readRecord(directory);
    if (record == null) throw StateError('Saved scan $safeId was not found.');
    return const JsonEncoder.withIndent('  ').convert(record);
  }

  /// Imports JSON created by [exportJson] as a new library entry.
  ///
  /// Output files are not embedded in JSON and therefore are not restored.
  Future<SavedRoomScan> importJson(String source) async {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> ||
        decoded['formatVersion'] != _formatVersion ||
        decoded['scanResult'] is! Map<String, dynamic>) {
      throw const FormatException('Unsupported or invalid room scan JSON.');
    }
    final name = decoded['name']?.toString().trim() ?? '';
    if (name.isEmpty) throw const FormatException('The scan name is missing.');
    final scan = ScanResult.fromJson(
      Map<String, dynamic>.from(decoded['scanResult'] as Map),
    );
    return save(name: name, scanResult: scan);
  }

  Future<Directory> _rootDirectory() async {
    final supplied = _providedDirectory;
    if (supplied != null) {
      return Directory('${supplied.path}/ios_roomplan_scans');
    }
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/ios_roomplan_scans');
  }

  Future<Directory> _entryDirectory(String id) async =>
      Directory('${(await _rootDirectory()).path}/$id');

  String _newId() {
    final random = Random.secure();
    final suffix = List.generate(
      8,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    return '${DateTime.now().microsecondsSinceEpoch}-$suffix';
  }

  String _validateId(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'Invalid saved scan ID.');
    }
    return id;
  }

  Future<File> _copyOutput(
    File source,
    Directory destination,
    String name,
  ) async {
    if (!await source.exists() || await source.length() == 0) {
      throw FileSystemException(
        'Cannot save a missing or empty scan output.',
        source.path,
      );
    }
    final target = File('${destination.path}/$name');
    await source.copy(target.path);
    return target;
  }

  Future<void> _writeRecord(
    Directory directory, {
    required String id,
    required String name,
    required DateTime createdAt,
    required ScanResult scanResult,
    String? pdfName,
    String? modelName,
  }) async {
    await _writeJsonAtomically(File('${directory.path}/scan.json'), {
      'formatVersion': _formatVersion,
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'scanResult': scanResult.toJson(),
      if (pdfName != null) 'pdfFile': pdfName,
      if (modelName != null) 'modelFile': modelName,
    });
  }

  Future<void> _writeJsonAtomically(
    File file,
    Map<String, dynamic> value,
  ) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<Map<String, dynamic>?> _readRecord(Directory directory) async {
    final file = File('${directory.path}/scan.json');
    if (!await file.exists()) return null;
    final value = jsonDecode(await file.readAsString());
    return value is Map<String, dynamic> ? value : null;
  }

  Future<SavedRoomScan?> _readEntry(Directory directory) async {
    try {
      final record = await _readRecord(directory);
      if (record == null ||
          record['formatVersion'] != _formatVersion ||
          record['scanResult'] is! Map<String, dynamic>) {
        return null;
      }
      final id = record['id']?.toString() ?? '';
      if (id.isEmpty ||
          directory.path.split(Platform.pathSeparator).last != id) {
        return null;
      }
      final createdAt = DateTime.tryParse(
        record['createdAt']?.toString() ?? '',
      );
      if (createdAt == null) return null;
      File? output(String key, String expectedName) {
        final name = record[key]?.toString();
        if (name != expectedName) return null;
        return File('${directory.path}/$name');
      }

      final pdf = output('pdfFile', 'floor-plan.pdf');
      final model = output('modelFile', 'room-model.usdz');
      return SavedRoomScan(
        id: id,
        name: record['name']?.toString() ?? 'Room scan',
        createdAt: createdAt,
        scanResult: ScanResult.fromJson(
          Map<String, dynamic>.from(record['scanResult'] as Map),
        ),
        pdfFile: pdf != null && await pdf.exists() ? pdf : null,
        modelFile: model != null && await model.exists() ? model : null,
      );
    } on Object {
      return null;
    }
  }
}
