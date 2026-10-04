import 'package:flutter/material.dart';

class AppButton extends StatelessWidget {
  const AppButton(
      {super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 19), const SizedBox(width: 9)],
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(onPressed: onPressed, child: child),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
              child: Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800))),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      );
}

class ChoiceChips extends StatelessWidget {
  const ChoiceChips(
      {super.key,
      required this.options,
      required this.selected,
      required this.onSelected,
      this.multiple = false});
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onSelected;
  final bool multiple;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 2,
        children: options
            .map((option) => FilterChip(
                  label: Text(option),
                  selected: selected.contains(option),
                  onSelected: (_) => onSelected(option),
                  showCheckmark: false,
                ))
            .toList(),
      );
}
