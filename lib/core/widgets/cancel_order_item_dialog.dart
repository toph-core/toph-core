import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

/// Prompts for a required cancellation reason before cancelling a committed
/// order item. Returns the trimmed comment, or `null` if the user backed out.
Future<String?> showCancelOrderItemDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const _CancelOrderItemDialog(),
  );
}

class _CancelOrderItemDialog extends StatefulWidget {
  const _CancelOrderItemDialog();

  @override
  State<_CancelOrderItemDialog> createState() =>
      _CancelOrderItemDialogState();
}

class _CancelOrderItemDialogState extends State<_CancelOrderItemDialog> {
  late final TextEditingController _commentController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _commentController = TextEditingController();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _selectQuickComment(String comment) {
    setState(() {
      _commentController.text = comment;
      _errorText = null;
    });
  }

  void _submit() {
    final comment = _commentController.text.trim();
    if (comment.isEmpty) {
      setState(() => _errorText = S.current.strCancelOrderItemReasonRequired);
      return;
    }
    Navigator.pop(context, comment);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colors.bgDefault,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    S.current.strCancelOrderItemTitle,
                    style: context.textStyles.bold20.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, size: 24),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _commentController,
              maxLines: 3,
              autofocus: true,
              onChanged: (_) {
                if (_errorText != null) setState(() => _errorText = null);
              },
              decoration: InputDecoration(
                hintText: S.current.strCancelOrderItemReasonHint,
                hintStyle: context.textStyles.bodySm.copyWith(
                  color: colors.textSecondary,
                ),
                errorText: _errorText,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: Color(0xFFFB6633),
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
              style: context.textStyles.bodySm,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                S.current.strCancelledByClient,
                S.current.strWaitersMistake,
              ]
                  .map(
                    (suggestion) => GestureDetector(
                      onTap: () => _selectQuickComment(suggestion),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3EE),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFFB6633).withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          suggestion,
                          style: context.textStyles.bodySm.copyWith(
                            color: const Color(0xFFFB6633),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
            Row(
              spacing: 12,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          S.current.strCancel,
                          style: context.textStyles.bodySm.copyWith(
                            color: colors.textDefault,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: _submit,
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFB6633),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          S.current.strSave,
                          style: context.textStyles.bodySm.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
