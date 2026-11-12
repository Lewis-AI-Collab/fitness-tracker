import 'package:flutter/material.dart';

import 'icon_tip.dart';

Future<bool> confirmChoice(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTip(
              icon: Icons.close,
              message: 'Cancel',
              onPressed: () => Navigator.pop(context, false),
            ),
            IconTip(
              icon: Icons.check,
              message: 'Confirm',
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}

Future<bool> confirmDiscard(
  BuildContext context, {
  required String title,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTip(
                  icon: Icons.close,
                  message: 'Cancel',
                  onPressed: () => Navigator.pop(context, false),
                ),
                IconTip(
                  icon: Icons.delete_outline,
                  message: 'Discard',
                  onPressed: () => Navigator.pop(context, true),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}
