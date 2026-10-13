import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/review_models.dart';
import '../models/partner_models.dart';
import '../repository/firestore_repository.dart';
import '../services/auth_service.dart';

/// Shows a modal bottom sheet for submitting a review.
/// Call this from anywhere a "Rate" button is tapped.
Future<void> showReviewSheet({
  required BuildContext context,
  required String bookingId,
  required String targetId,
  required String targetName,
  required String targetRole,
}) async {
  final uid = AuthService.instance.currentUser?.uid;
  if (uid == null) return;

  // Check if already reviewed
  final alreadyReviewed = await FirestoreRepository.instance.hasReviewed(
    bookingId,
    uid,
    targetId,
  );
  if (alreadyReviewed) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Вы уже оставили отзыв об этом участнике.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return;
  }

  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ReviewSheetBody(
      bookingId: bookingId,
      authorId: uid,
      targetId: targetId,
      targetName: targetName,
      targetRole: targetRole,
    ),
  );
}

class _ReviewSheetBody extends StatefulWidget {
  final String bookingId, authorId, targetId, targetName, targetRole;
  const _ReviewSheetBody({
    required this.bookingId,
    required this.authorId,
    required this.targetId,
    required this.targetName,
    required this.targetRole,
  });

  @override
  State<_ReviewSheetBody> createState() => _ReviewSheetBodyState();
}

class _ReviewSheetBodyState extends State<_ReviewSheetBody> {
  double _rating = 5.0;
  final _commentCtrl = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      final uid = AuthService.instance.currentUser?.uid ?? '';
      final profile = uid.isNotEmpty
          ? await FirestoreRepository.instance.getPartner(uid)
          : null;
      final authorName = profile != null
          ? '${profile.firstName} ${profile.lastName}'.trim()
          : 'Партнёр';
      final review = Review(
        id: '',
        bookingId: widget.bookingId,
        authorId: widget.authorId,
        authorName: authorName,
        authorRole: (profile?.role.isDriver == true) ? 'driver' : 'guide',
        targetId: widget.targetId,
        targetRole: widget.targetRole,
        rating: _rating,
        comment: _commentCtrl.text.trim(),
        createdAt: DateTime.now(),
      );
      await FirestoreRepository.instance.submitReview(review);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Оценить: ${widget.targetName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            // Star Rating
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final star = i + 1;
                return GestureDetector(
                  onTap: () => setState(() => _rating = star.toDouble()),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      _rating >= star
                          ? CupertinoIcons.star_fill
                          : CupertinoIcons.star,
                      color: _rating >= star
                          ? const Color(0xFFFFCC00)
                          : Colors.grey,
                      size: 36,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _commentCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Ваш комментарий (необязательно)',
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFF2F2F7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : const Text(
                        'Отправить отзыв',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
