import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_bits.dart';

class ReviewComposeScreen extends StatefulWidget {
  const ReviewComposeScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  State<ReviewComposeScreen> createState() => _ReviewComposeScreenState();
}

class _ReviewComposeScreenState extends State<ReviewComposeScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _selectedCategories = <String>{};
  Booking? _booking;
  bool _loading = true;
  bool _submitting = false;
  int _rating = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final booking = await context.read<AppState>().loadBooking(
      widget.bookingId,
    );
    if (!mounted) return;
    setState(() {
      _booking = booking;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || _rating < 1 || _rating > 5) return;
    final app = context.read<AppState>();
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await app.submitReview(
        bookingId: widget.bookingId,
        rating: _rating,
        categories: _selectedCategories.toList(),
        text: _text.text,
      );
      if (!mounted) return;
      app.say(result.visible ? 'Review published' : 'Review submitted');
      app.back();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is StateError
            ? error.message
            : 'Something went wrong. Please retry.';
      });
      revealFormFeedback(this, _scroll);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final booking = _booking;

    return Scaffold(
      backgroundColor: context.epColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: ListView(
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(
                16,
                headerTopPad(context),
                16,
                tabBarClearance + 112 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Row(
                  children: [
                    CircleIconButton(onTap: app.back),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'REVIEW',
                        style: Theme.of(context).textTheme.epPageHeading,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (booking == null)
                  Text(
                    'BOOKING NOT FOUND',
                    style: epText(color: context.epColors.contentSecondary),
                  )
                else ...[
                  Text(
                    '${booking.opportunityTitle} · '
                    '${booking.viewerSide == BookingSide.artist ? booking.organizationName : booking.bandName} · '
                    '${Gig.dateShortFor(booking.startsAt.millisecondsSinceEpoch)}',
                    style: Theme.of(context).textTheme.epBody,
                  ),
                  const SectionBar(label: 'RATING'),
                  Row(
                    children: [
                      for (var rating = 1; rating <= 5; rating++)
                        IconButton(
                          key: ValueKey('review-rating-$rating'),
                          tooltip: '$rating ${rating == 1 ? 'star' : 'stars'}',
                          iconSize: 32,
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          color: context.epColors.accent,
                          onPressed: _submitting
                              ? null
                              : () => setState(() {
                                  _rating = rating;
                                  _error = null;
                                }),
                          icon: Icon(
                            rating <= _rating ? Icons.star : Icons.star_border,
                          ),
                        ),
                    ],
                  ),
                  const SectionBar(label: 'CATEGORIES'),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final category in reviewCategories)
                        EpChip(
                          key: ValueKey('review-cat-$category'),
                          label: category.toUpperCase(),
                          active: _selectedCategories.contains(category),
                          onTap: _submitting
                              ? null
                              : () => setState(() {
                                  if (!_selectedCategories.add(category)) {
                                    _selectedCategories.remove(category);
                                  }
                                  _error = null;
                                }),
                        ),
                    ],
                  ),
                  const SectionBar(label: 'REVIEW'),
                  EpLabeledField(
                    fieldKey: const ValueKey('review-text'),
                    label: 'REVIEW',
                    hint: 'How was working together?',
                    controller: _text,
                    enabled: !_submitting,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: 1000,
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Reviews are double-blind: neither side sees the other's until both are in or 14 days pass.",
                    style: Theme.of(context).textTheme.epCaption,
                  ),
                  const SizedBox(height: 16),
                  InlineFormFeedback(
                    key: const ValueKey('review-feedback'),
                    error: _error,
                  ),
                ],
              ],
            ),
          ),
          if (!_loading && booking != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 67,
              child: StickyActionBar(
                key: const ValueKey('review-submit'),
                primaryLabel: 'SUBMIT REVIEW',
                onPrimary: !_submitting && _rating >= 1 && _rating <= 5
                    ? _submit
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}
