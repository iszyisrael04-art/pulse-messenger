import 'package:flutter/material.dart';

import 'repository.dart' hide Row;

class PulseAvatar extends StatefulWidget {
  const PulseAvatar({
    super.key,
    required this.repo,
    required this.path,
    required this.name,
    this.radius = 24,
  });

  final PulseRepository repo;
  final String? path;
  final String name;
  final double radius;

  @override
  State<PulseAvatar> createState() => _PulseAvatarState();
}

class _PulseAvatarState extends State<PulseAvatar> {
  Future<String?>? future;

  @override
  void initState() {
    super.initState();
    future = widget.repo.avatar(widget.path);
  }

  @override
  void didUpdateWidget(PulseAvatar old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      future = widget.repo.avatar(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: future,
    builder: (_, snapshot) => CircleAvatar(
      radius: widget.radius,
      backgroundImage: snapshot.data == null
          ? null
          : NetworkImage(snapshot.data!),
      child: snapshot.data != null
          ? null
          : Text(
              widget.name.isEmpty
                  ? 'P'
                  : widget.name.characters.first.toUpperCase(),
            ),
    ),
  );
}
