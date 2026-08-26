import 'package:flutter/material.dart';

/// An item's name, falling back to a grayed-out "Gjenstand" when it hasn't
/// been named yet (e.g. an item created via batch capture). Shared by
/// every place an item's name is displayed.
class ItemNameText extends StatelessWidget {
  final String? name;
  final TextOverflow? overflow;

  const ItemNameText({super.key, required this.name, this.overflow});

  @override
  Widget build(BuildContext context) {
    if (name != null) {
      return Text(name!, overflow: overflow);
    }
    return Text(
      'Gjenstand',
      overflow: overflow,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}
