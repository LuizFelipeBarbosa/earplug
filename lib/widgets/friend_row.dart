import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import 'common.dart';
import 'ep_rows.dart';

/// An [EpEntityRow] for one friend, loading their card once on mount and
/// showing a placeholder title until it resolves.
class FriendRow extends StatefulWidget {
  const FriendRow({
    super.key,
    required this.userId,
    required this.rowKey,
    required this.sub,
  });

  final String userId;

  /// Lands on the row itself, so lists can find a friend by their id.
  final Key rowKey;
  final String sub;

  @override
  State<FriendRow> createState() => _FriendRowState();
}

class _FriendRowState extends State<FriendRow> {
  late final Future<SocialUserDetail?> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().loadUserCard(widget.userId);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SocialUserDetail?>(
    future: _future,
    builder: (context, snapshot) {
      final detail = snapshot.data;
      return EpEntityRow(
        key: widget.rowKey,
        leading: EpFanAvatar(
          name: detail?.name,
          imageUrl: detail?.avatarUrl,
          size: 40,
        ),
        title: detail?.name ?? '...',
        sub: widget.sub,
      );
    },
  );
}
