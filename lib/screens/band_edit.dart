import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../band_media_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_bits.dart';

class BandEditScreen extends StatelessWidget {
  const BandEditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final band = app.myBand;
    if (band == null) return const SizedBox.shrink();
    final videos = context.watch<BandMediaController>().videosFor(app.bandId);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        headerTopPad(context),
        16,
        tabBarClearance,
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PUBLIC PROFILE',
              style: Theme.of(context).textTheme.epPageHeading,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => app.openBand(app.bandId),
              child: const Text('PREVIEW AS FAN'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        EpCard(
          variant: EpCardVariant.selected,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          child: Text(
            "You're editing the public profile. Fans see these changes too.",
            style: Theme.of(
              context,
            ).textTheme.epCaption.copyWith(color: Ep.contentPrimary),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            BandAvatar(band, size: 64, radius: 13, fontSize: 22),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    band.name.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: epDisplay(size: 18),
                  ),
                  TextAction(
                    'CHANGE PHOTO',
                    onTap: app.openBandMedia,
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: ValueKey('linkYt-${app.bandId}'),
          initialValue: app.linkYtFor(app.bandId),
          onChanged: app.setLinkYt,
          style: epText(size: 12),
          decoration: epInputDecoration('youtube.com/@yourband'),
        ),
        const SizedBox(height: 14),
        const SectionLabel('ABOUT THE BAND'),
        const SizedBox(height: 6),
        TextFormField(
          key: ValueKey('bio-${app.bandId}'),
          initialValue: app.bioFor(app.bandId),
          onChanged: app.setBandBio,
          style: epText(size: 13, height: 1.5),
          minLines: 3,
          maxLines: 5,
          decoration: epInputDecoration('Add a short bio'),
        ),
        const SizedBox(height: 14),
        const SectionLabel('LINKS'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey('linkIg-${app.bandId}'),
                initialValue: app.linkIgFor(app.bandId),
                onChanged: app.setLinkIg,
                style: epText(size: 12),
                decoration: epInputDecoration('@instagram'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                key: ValueKey('linkBc-${app.bandId}'),
                initialValue: app.linkBcFor(app.bandId),
                onChanged: app.setLinkBc,
                style: epText(size: 12),
                decoration: epInputDecoration('bandcamp'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('MUSIC CLIPS'),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                TextAction(
                  '+ POST A MUSIC CLIP',
                  onTap: app.openBandMedia,
                  padding: EdgeInsets.zero,
                ),
                TextAction(
                  'MANAGE',
                  onTap: app.openBandMedia,
                  color: Ep.contentSecondary,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final v in videos) ...[
          EpCard(
            variant: v.pinned ? EpCardVariant.selected : EpCardVariant.standard,
            padding: const EdgeInsets.all(9),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Ep.surfaceRaised,
                    border: Border.all(color: Ep.border),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const PlayTriangle(size: 9, color: Ep.contentPrimary),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: epText(size: 12.5, weight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${v.viewsLabel} · ${v.lenLabel}',
                        style: epText(size: 10.5, color: Ep.contentSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
