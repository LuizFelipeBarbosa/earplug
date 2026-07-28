import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class BandCreateScreen extends StatelessWidget {
  const BandCreateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Column(
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 10),
          decoration:
              BoxDecoration(border: Border(bottom: BorderSide(color: Ep.whiteA(.09)))),
          child: Row(
            children: [
              CircleIconButton(onTap: app.back),
              const SizedBox(width: 10),
              Text('START A BAND', style: epDisplay(size: 16)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 60),
            children: app.nbStep == 1 ? _step1(context, app) : _step2(context, app),
          ),
        ),
      ],
    );
  }

  List<Widget> _step1(BuildContext context, AppState app) {
    return [
      Row(
        children: [
          GestureDetector(
            onTap: () => app.say('Photo upload placeholder (demo)'),
            child: SizedBox(
              width: 74,
              height: 74,
              child: DashedBox(
                padding: EdgeInsets.zero,
                child: Center(
                  child: Text('+', style: epText(size: 24, color: Ep.inkA(.5))),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text('Band photo.\nBlurry basement shots welcome.',
              style: epText(size: 11.5, color: Ep.inkA(.5), height: 1.5)),
        ],
      ),
      const SizedBox(height: 16),
      const SectionLabel('BAND NAME'),
      const SizedBox(height: 6),
      TextFormField(
        initialValue: app.nbName,
        onChanged: app.setNbName,
        style: epText(size: 14),
        decoration: epInputDecoration('e.g. Static Bloom'),
      ),
      const SizedBox(height: 16),
      const SectionLabel('GENRES'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          for (final t in const [
            'punk', 'hardcore', 'garage', 'noise', 'post-punk', 'shoegaze', 'surf', 'thrash'
          ])
            EpChip(
                label: t, active: app.nbGenres.contains(t), onTap: () => app.toggleNbGenre(t)),
        ],
      ),
      const SizedBox(height: 16),
      const SectionLabel('SHORT BIO'),
      const SizedBox(height: 6),
      TextFormField(
        initialValue: app.nbBio,
        onChanged: app.setNbBio,
        style: epText(size: 13.5, height: 1.5),
        minLines: 3,
        maxLines: 4,
        decoration:
            epInputDecoration('Two sentences. What do you sound like, where do you play?'),
      ),
      const SizedBox(height: 20),
      EpButton(
        'NEXT — INVITE MEMBERS ›',
        fontSize: 13,
        kind: app.nbName.trim().isEmpty ? EpButtonKind.disabled : EpButtonKind.filled,
        onTap: app.nbNext,
      ),
    ];
  }

  List<Widget> _step2(BuildContext context, AppState app) {
    return [
      Text.rich(
        TextSpan(
          style: epText(size: 12.5, color: Ep.inkA(.55), height: 1.5),
          children: [
            const TextSpan(text: 'Invite by username — when they accept, '),
            TextSpan(text: app.nbName, style: epText(size: 12.5, weight: FontWeight.w800)),
            const TextSpan(
                text: ' shows up in their view switcher too. '
                    'Roles stay simple: admin (you) and members.'),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _InviteField(app: app),
      const SizedBox(height: 8),
      for (final invite in app.nbInvites) ...[
        EpCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          radius: 11,
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Ep.whiteA(.12), shape: BoxShape.circle),
                child: Text(invite.replaceFirst('@', '')[0].toUpperCase(),
                    style: epText(size: 11, weight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(invite, style: epText(size: 13, weight: FontWeight.w700))),
              Text('INVITED · MEMBER',
                  style: epText(
                      size: 10, weight: FontWeight.w800, letterSpacing: .8, color: Ep.inkA(.45))),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
      GestureDetector(
        onTap: () => app.say('Invite link copied.'),
        child: DashedBox(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('earplug.app/join/${app.nbSlug}',
                  style: epText(size: 12, weight: FontWeight.w700, color: Ep.inkA(.7))),
              Text('COPY LINK',
                  style: epText(
                      size: 10.5, weight: FontWeight.w900, letterSpacing: .8, color: Ep.link)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      EpButton('CREATE ${app.nbName.toUpperCase()}', onTap: app.createBand),
    ];
  }
}

class _InviteField extends StatefulWidget {
  final AppState app;

  const _InviteField({required this.app});

  @override
  State<_InviteField> createState() => _InviteFieldState();
}

class _InviteFieldState extends State<_InviteField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    widget.app.addNbInvite(_controller.text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            onSubmitted: (_) => _add(),
            style: epText(size: 14),
            decoration: epInputDecoration('@username'),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _add,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: BoxDecoration(
              color: Ep.blue,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text('ADD',
                style: epText(
                    size: 12, weight: FontWeight.w900, letterSpacing: .8, color: Colors.white)),
          ),
        ),
      ],
    );
  }
}
