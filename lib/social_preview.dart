import 'dart:io';
import 'package:flutter/material.dart';
import 'photo_studio.dart';
import 'video_studio.dart';
export 'studio_model.dart';

class SocialSelectionPreview extends StatelessWidget {
  const SocialSelectionPreview({
    super.key,
    required this.file,
    required this.video,
  });
  final File file;
  final bool video;
  @override
  Widget build(BuildContext context) =>
      video ? PulseVideoStudio(file: file) : PulsePhotoStudio(file: file);
}
