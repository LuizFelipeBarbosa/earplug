import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_text.dart';

class ExploreAvatarStack extends StatelessWidget {
  const ExploreAvatarStack({
    super.key,
    required this.people,
    this.size = 24,
    this.max = 3,
  });

  final List<SocialUserCard> people;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    final count = people.length > max ? max : people.length;
    final overflow = people.length - count;
    final slots = count + (overflow > 0 ? 1 : 0);
    return SizedBox(
      width: size + (slots - 1) * size * .66,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < count; i++)
            Positioned(
              left: i * size * .66,
              child: EpFanAvatar(
                name: people[i].name,
                imageUrl: people[i].avatarUrl,
                size: size,
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: count * size * .66,
              child: Container(
                width: size,
                height: size,
                color: context.epColors.panel,
                alignment: Alignment.center,
                child: EpMonoText('+$overflow', size: size * .42),
              ),
            ),
        ],
      ),
    );
  }
}
