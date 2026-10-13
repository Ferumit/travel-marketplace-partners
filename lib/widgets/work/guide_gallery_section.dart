import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/partner_models.dart';
import '../../repository/firestore_repository.dart';
import '../../services/firebase_storage_service.dart';

class GuideGallerySection extends StatefulWidget {
  final bool isDark;
  final PartnerProfile? profile;

  const GuideGallerySection({super.key, required this.isDark, this.profile});

  @override
  State<GuideGallerySection> createState() => _GuideGallerySectionState();
}

class _GuideGallerySectionState extends State<GuideGallerySection> {
  bool _isUploading = false;

  Future<void> _uploadPhoto() async {
    if (widget.profile == null) return;
    final uid = widget.profile!.id;
    final currentGallery = widget.profile!.galleryUrls;
    if (currentGallery.length >= 15) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Достигнут лимит 15 фотографий')),
        );
      }
      return;
    }
    setState(() => _isUploading = true);
    try {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (xFile == null) {
        setState(() => _isUploading = false);
        return;
      }
      final file = File(xFile.path);
      final path = 'partners/$uid/gallery/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final url = await FirebaseStorageService.instance.uploadFile(file: file, path: path);
      if (url != null) {
        final updated = List<String>.from(currentGallery)..add(url);
        await FirestoreRepository.instance.updatePartner(uid, {'galleryUrls': updated});
      }
    } catch (e) {
      debugPrint('Error uploading gallery photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка загрузки фото')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _deletePhoto(String url) async {
    if (widget.profile == null) return;
    final uid = widget.profile!.id;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Удалить фото?'),
        content: const Text('Фотография будет удалена из портфолио'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final updated = List<String>.from(widget.profile!.galleryUrls)..remove(url);
      await FirestoreRepository.instance.updatePartner(uid, {'galleryUrls': updated});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Фото удалено'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка удаления: $e')),
        );
      }
    }
  }

  void _openFullscreen(List<String> gallery, int startIndex) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.93),
      builder: (ctx) => GalleryFullscreenViewer(
        urls: gallery,
        initialIndex: startIndex,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.profile == null || !widget.profile!.role.isGuide) {
      return const SizedBox.shrink();
    }
    final gallery = widget.profile!.galleryUrls;
    final count = gallery.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with icon, title, count badge, and add button
          Row(
            children: [
              const Icon(CupertinoIcons.photo_on_rectangle,
                  color: Color(0xFF6FBF4F), size: 18),
              const SizedBox(width: 8),
              Text(
                'Галерея портфолио',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF6FBF4F).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6FBF4F),
                  ),
                ),
              ),
              const Spacer(),
              if (_isUploading)
                const CupertinoActivityIndicator()
              else if (count < 15)
                GestureDetector(
                  onTap: _uploadPhoto,
                  child: const Icon(CupertinoIcons.add_circled_solid,
                      color: Color(0xFF6FBF4F), size: 24),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            count < 15
                ? 'Нажмите + чтобы добавить фото  $count/15'
                : 'Достигнут лимит (15/15)',
            style: const TextStyle(color: CupertinoColors.systemGrey, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // Empty state
          if (gallery.isEmpty)
            GestureDetector(
              onTap: _uploadPhoto,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFF6FBF4F).withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFF6FBF4F).withValues(alpha: 0.05),
                ),
                child: Column(
                  children: [
                    Icon(
                      CupertinoIcons.camera,
                      color: const Color(0xFF6FBF4F).withValues(alpha: 0.6),
                      size: 32,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Нет фотографий',
                      style: TextStyle(
                        color: CupertinoColors.systemGrey,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Нажмите чтобы добавить или загрузите\nчерез сайт в разделе «Галерея»',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: CupertinoColors.systemGrey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            // Grid view with 3 columns
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: gallery.length,
              itemBuilder: (context, index) {
                final url = gallery[index];
                return GestureDetector(
                  onTap: () => _openFullscreen(gallery, index),
                  onLongPress: () => _deletePhoto(url),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          url,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            color: CupertinoColors.systemGrey5,
                            child: const Icon(
                              CupertinoIcons.exclamationmark_triangle,
                              color: CupertinoColors.systemGrey,
                              size: 28,
                            ),
                          ),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              color: widget.isDark
                                  ? const Color(0xFF2C2C2E)
                                  : CupertinoColors.systemGrey6,
                              child: const Center(
                                child: CupertinoActivityIndicator(),
                              ),
                            );
                          },
                        ),
                      ),
                      // Delete button top-right
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => _deletePhoto(url),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemRed
                                  .withValues(alpha: 0.85),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: const Icon(
                              CupertinoIcons.xmark,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// Fullscreen gallery viewer with swipe and zoom
class GalleryFullscreenViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const GalleryFullscreenViewer({
    super.key,
    required this.urls,
    required this.initialIndex,
  });

  @override
  State<GalleryFullscreenViewer> createState() =>
      _GalleryFullscreenViewerState();
}

class _GalleryFullscreenViewerState
    extends State<GalleryFullscreenViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          // Swipeable pages
          PageView.builder(
            controller: _pageController,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (context, index) => InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: Center(
                child: Image.network(
                  widget.urls[index],
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    CupertinoIcons.exclamationmark_triangle,
                    color: Colors.white54,
                    size: 48,
                  ),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(
                      child: CupertinoActivityIndicator(color: Colors.white),
                    );
                  },
                ),
              ),
            ),
          ),
          // Close button
          Positioned(
            top: kToolbarHeight,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(
                  CupertinoIcons.xmark,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
          // Page counter
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_currentIndex + 1} / ${widget.urls.length}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
