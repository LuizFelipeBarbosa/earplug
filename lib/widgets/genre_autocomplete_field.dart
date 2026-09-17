import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../genres.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_text.dart';
import 'form_bits.dart';

class GenreAutocompleteField extends StatefulWidget {
  const GenreAutocompleteField({
    super.key,
    required this.selected,
    required this.onChanged,
    this.max = 3,
    this.suggestions = kGenres,
    this.keyPrefix = 'edit-genres',
    this.required = true,
  });

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final int max;
  final List<String> suggestions;
  final String keyPrefix;
  final bool required;

  @override
  State<GenreAutocompleteField> createState() => _GenreAutocompleteFieldState();
}

class _GenreAutocompleteFieldState extends State<GenreAutocompleteField> {
  final _controller = TextEditingController();
  late final _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
  var _activeIndex = 0;
  var _showLimit = false;

  bool get _enabled => widget.selected.length < widget.max;
  bool get _showSuggestions => _enabled && _controller.text.isNotEmpty;

  List<String> get _matches {
    final query = _controller.text.trim().toLowerCase();
    final selected = widget.selected
        .map((genre) => genre.toLowerCase())
        .toSet();
    return widget.suggestions
        .where(
          (genre) =>
              genre.toLowerCase().contains(query) &&
              !selected.contains(genre.toLowerCase()),
        )
        .take(6)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_textChanged);
  }

  @override
  void didUpdateWidget(covariant GenreAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _activeIndex = _activeIndex.clamp(0, _matches.length);
    if (_enabled) _showLimit = false;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _textChanged() {
    setState(() {
      _activeIndex = _activeIndex.clamp(0, _matches.length);
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_showSuggestions) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        setState(() {
          final step = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
          _activeIndex = (_activeIndex + step).clamp(0, _matches.length);
        });
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) _commit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _commit() {
    if (_controller.text.trim().isEmpty) return;
    final matches = _matches;
    final index = _activeIndex.clamp(0, matches.length);
    _addGenre(index < matches.length ? matches[index] : _controller.text);
  }

  void _addGenre(String value) {
    final genre = value.trim();
    if (genre.isEmpty) return;

    final duplicate = widget.selected.any(
      (selected) => selected.toLowerCase() == genre.toLowerCase(),
    );
    if (!duplicate && !_enabled) {
      setState(() => _showLimit = true);
      return;
    }

    setState(() {
      _showLimit = false;
      _activeIndex = 0;
    });
    _controller.clear();
    _focusNode.requestFocus();
    if (!duplicate) widget.onChanged([...widget.selected, genre]);
  }

  Widget _selectedChip(BuildContext context, String genre) {
    return Semantics(
      key: Key('${widget.keyPrefix}-chip-$genre'),
      container: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: EpPill(label: genre, selected: true, onPressed: null),
          ),
          MergeSemantics(
            child: Semantics(
              label: 'Remove $genre',
              button: true,
              child: SizedBox.square(
                dimension: 44,
                child: IconButton(
                  onPressed: () => widget.onChanged([
                    for (final selected in widget.selected)
                      if (selected != genre) selected,
                  ]),
                  icon: Icon(
                    Icons.close,
                    color: context.epColors.contentSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionRow(
    BuildContext context,
    String genre,
    int index, {
    bool custom = false,
  }) {
    final active = index == _activeIndex;
    return InkWell(
      key: Key(
        custom
            ? '${widget.keyPrefix}-add-custom'
            : '${widget.keyPrefix}-suggestion-$index',
      ),
      onTap: () => _addGenre(genre),
      child: Semantics(
        selected: active,
        child: Ink(
          color: active ? context.epColors.accent.withValues(alpha: .18) : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      custom ? 'Add "$genre"' : genre,
                      style: Theme.of(context).textTheme.epBody.copyWith(
                        color: custom
                            ? context.epColors.accent
                            : context.epColors.contentPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.add, color: context.epColors.contentSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(EpLayout.controlRadius),
      borderSide: BorderSide(color: context.epColors.border),
    );
    final matches = _matches;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: FieldLabel('GENRES', required: widget.required)),
            const SizedBox(width: 8),
            EpMonoText(
              '${widget.selected.length} OF ${widget.max}',
              key: Key('${widget.keyPrefix}-count'),
              color: context.epColors.contentSecondary,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (widget.selected.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final genre in widget.selected)
                _selectedChip(context, genre),
            ],
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          key: Key('${widget.keyPrefix}-input'),
          controller: _controller,
          focusNode: _focusNode,
          enabled: _enabled,
          textInputAction: TextInputAction.done,
          // Done commits without the default focus dismissal.
          onEditingComplete: () {},
          onSubmitted: (_) => _commit(),
          decoration:
              epInputDecoration(
                context,
                _enabled ? 'Add a genre' : 'Genres full',
              ).copyWith(
                border: border,
                enabledBorder: border,
                disabledBorder: border,
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(EpLayout.controlRadius),
                  borderSide: BorderSide(
                    color: context.epColors.accent,
                    width: 1.5,
                  ),
                ),
              ),
        ),
        if (_showSuggestions)
          Container(
            key: Key('${widget.keyPrefix}-suggestions'),
            decoration: BoxDecoration(
              border: Border.all(color: context.epColors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < matches.length; index++)
                  _suggestionRow(context, matches[index], index),
                _suggestionRow(
                  context,
                  _controller.text.trim(),
                  matches.length,
                  custom: true,
                ),
              ],
            ),
          ),
        if (_showLimit) ...[
          const SizedBox(height: 8),
          EpMonoText(
            'Choose no more than three genres.',
            key: Key('${widget.keyPrefix}-limit'),
            color: context.epColors.muted,
            keepCase: true,
          ),
        ],
      ],
    );
  }
}
