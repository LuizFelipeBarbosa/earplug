import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../band_media_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class BandEditScreen extends StatelessWidget {
  const BandEditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final band = app.myBand;
    if (band == null) return const SizedBox.shrink();
    final videos = context.watch<BandMediaController>().videosFor(app.bandId);

    return ListView(
      padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, tabBarClearance),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('PUBLIC PROFILE', style: epDisplay(size: 18)),
            GestureDetector(
              onTap: () => app.openBand(app.bandId),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  border: Border.all(color: Ep.whiteA(.22)),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text('PREVIEW AS FAN ›',
                    style: epText(size: 10, weight: FontWeight.w800, letterSpacing: .8)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: Ep.blue.withValues(alpha: .14),
            border: Border.all(color: Ep.blue.withValues(alpha: .5)),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
              "You're editing the real thing — what you see here is exactly what fans see.",
              style: epText(size: 11.5, color: Ep.linkSoft, height: 1.45)),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            BandAvatar(band, size: 64, radius: 13, fontSize: 22),
            const SizedBox(width: 13),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(band.name.toUpperCase(), style: epDisplay(size: 18)),
                GestureDetector(
                  onTap: app.openBandMedia,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('CHANGE PHOTO',
                        style: epText(
                            size: 11,
                            weight: FontWeight.w800,
                            letterSpacing: .5,
                            color: Ep.link)),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        const SectionLabel('BIO'),
        const SizedBox(height: 6),
        TextFormField(
          key: ValueKey('bio-${app.bandId}'),
          initialValue: app.bioFor(app.bandId),
          onChanged: app.setBandBio,
          style: epText(size: 13, height: 1.5),
          minLines: 3,
          maxLines: 5,
          decoration: epInputDecoration(''),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SectionLabel('VIDEOS'),
            Row(
              children: [
                GestureDetector(
                  onTap: app.openBandMedia,
                  child: Text('+ UPLOAD CLIP',
                      style: epText(
                          size: 11,
                          weight: FontWeight.w900,
                          letterSpacing: .6,
                          color: Ep.link)),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: app.openBandMedia,
                  child: Text('MANAGE ›',
                      style: epText(
                          size: 10.5,
                          weight: FontWeight.w800,
                          letterSpacing: .6,
                          color: Ep.inkA(.55))),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final v in videos) ...[
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Ep.card,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                  color: v.pinned ? Ep.blue.withValues(alpha: .55) : Ep.whiteA(.1)),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A20),
                    border: Border.all(color: Ep.whiteA(.12)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: PlayTriangle(size: 9, color: Ep.whiteA(.8)),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: epText(size: 12.5, weight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('${v.viewsLabel} · ${v.lenLabel}',
                          style: epText(size: 10.5, color: Ep.inkA(.5))),
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
