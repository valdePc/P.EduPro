import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

typedef StudentPhotoLoader = Future<Uint8List?> Function(String path);

/// New registration photos use an authenticated download, never a bearer URL.
class StudentPhotoAvatar extends StatefulWidget {
  const StudentPhotoAvatar({
    super.key,
    required this.studentPath,
    this.photoPath = '',
    this.legacyUrl = '',
    this.radius = 30,
    this.loadPhoto,
  });

  final String studentPath;
  final String photoPath;
  final String legacyUrl;
  final double radius;
  final StudentPhotoLoader? loadPhoto;

  @override
  State<StudentPhotoAvatar> createState() => _StudentPhotoAvatarState();
}

class _StudentPhotoAvatarState extends State<StudentPhotoAvatar> {
  Future<Uint8List?>? _photo;

  static Future<Uint8List?> _download(String path) =>
      FirebaseStorage.instance.ref(path).getData(5 * 1024 * 1024);

  void _load() {
    final path = widget.photoPath;
    final expected = '${widget.studentPath}/profile.';
    final valid =
        RegExp(
          r'^schools/[A-Za-z0-9_-]+/alumnos/[A-Za-z0-9_-]+$',
        ).hasMatch(widget.studentPath) &&
        (path == '${expected}jpg' || path == '${expected}png');
    _photo = valid && widget.legacyUrl.isEmpty
        ? Future.sync(() => (widget.loadPhoto ?? _download)(path))
        : null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StudentPhotoAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studentPath != widget.studentPath ||
        oldWidget.photoPath != widget.photoPath ||
        oldWidget.legacyUrl != widget.legacyUrl ||
        oldWidget.loadPhoto != widget.loadPhoto) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _photo,
    builder: (context, snapshot) {
      ImageProvider? image;
      if (snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError &&
          snapshot.data?.isNotEmpty == true) {
        image = MemoryImage(snapshot.data!);
      } else if (Uri.tryParse(widget.legacyUrl)?.scheme == 'https') {
        image = NetworkImage(widget.legacyUrl);
      }
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: Colors.white,
        backgroundImage: image,
        child:
            image == null
                ? Icon(
                  Icons.person,
                  size: widget.radius + 4,
                  color: Colors.grey.shade700,
                )
                : null,
      );
    },
  );
}
