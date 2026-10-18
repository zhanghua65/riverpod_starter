import 'package:flutter/material.dart';

/// A slider that saves only when the user lets go.
class SliderTile extends StatefulWidget {
  const SliderTile({
    super.key,
    required this.title,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String title;
  final String unit;
  final int value;
  final int min;
  final int max;
  final int step;
  final Future<void> Function(int value) onChanged;

  @override
  State<SliderTile> createState() => _SliderTileState();
}

class _SliderTileState extends State<SliderTile> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final value = _dragging ?? widget.value.toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: '${widget.title} ',
            children: [
              TextSpan(
                text: '${value.round()} ${widget.unit}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        Slider(
          value: value,
          min: widget.min.toDouble(),
          max: widget.max.toDouble(),
          divisions: (widget.max - widget.min) ~/ widget.step,
          label: '${value.round()}',
          onChanged: (v) => setState(() => _dragging = v),
          onChangeEnd: (v) async {
            await widget.onChanged(v.round());
            if (mounted) setState(() => _dragging = null);
          },
        ),
      ],
    );
  }
}
