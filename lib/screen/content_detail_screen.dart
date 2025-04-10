// content_detail_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'services/auth_service.dart';
import 'services/firebase_service.dart';

class ContentDetailScreen extends StatefulWidget {
  final String contentId;
  final String contentType;

  const ContentDetailScreen({
    super.key,
    required this.contentId,
    required this.contentType,
  });

  @override
  _ContentDetailScreenState createState() => _ContentDetailScreenState();
}

class _ContentDetailScreenState extends State<ContentDetailScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _contentData = {};
  List<Map<String, dynamic>> _chapters = [];
  int _selectedChapterIndex = 0;
  bool _isBookmarked = false;
  double _readingProgress = 0.0;
  final ScrollController _scrollController = ScrollController();
  bool _isInReadingMode = false;

  // For light novels and comics which might have chapters
  bool get _hasChapters => widget.contentType != 'stories';

  @override
  void initState() {
    super.initState();
    _loadContent();
    _scrollController.addListener(_updateReadingProgress);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateReadingProgress);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateReadingProgress() {
    if (!_isInReadingMode || _scrollController.positions.isEmpty) return;

    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    if (maxScrollExtent <= 0) return;

    final currentProgress = _scrollController.offset / maxScrollExtent;
    setState(() {
      _readingProgress = currentProgress.clamp(0.0, 1.0);
    });

    // Save reading progress if user is logged in and has read at least 10%
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.currentUser != null && currentProgress >= 0.1) {
      _saveReadingProgress();
    }
  }

  Future<void> _loadContent() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final firebaseService = Provider.of<FirebaseService>(
        context,
        listen: false,
      );
      final authService = Provider.of<AuthService>(context, listen: false);

      // Get the content document
      DocumentSnapshot doc =
          await FirebaseFirestore.instance
              .collection(widget.contentType)
              .doc(widget.contentId)
              .get();

      if (!doc.exists) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Content not found')));
        Navigator.pop(context);
        return;
      }

      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      data['id'] = doc.id;

      // Load chapters if this is a light novel or comic
      List<Map<String, dynamic>> chapters = [];
      if (_hasChapters) {
        QuerySnapshot chaptersSnapshot =
            await FirebaseFirestore.instance
                .collection(widget.contentType)
                .doc(widget.contentId)
                .collection('chapters')
                .orderBy('chapterNumber')
                .get();

        chapters =
            chaptersSnapshot.docs.map((chapterDoc) {
              Map<String, dynamic> chapterData =
                  chapterDoc.data() as Map<String, dynamic>;
              chapterData['id'] = chapterDoc.id;
              return chapterData;
            }).toList();
      }

      // Check if bookmarked
      bool isBookmarked = false;
      if (authService.currentUser != null) {
        DocumentSnapshot bookmarkDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(authService.currentUser!.uid)
                .collection('bookmarks')
                .doc(widget.contentId)
                .get();

        isBookmarked = bookmarkDoc.exists;

        // Get reading progress if available
        DocumentSnapshot progressDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(authService.currentUser!.uid)
                .collection('readingProgress')
                .doc(widget.contentId)
                .get();

        if (progressDoc.exists) {
          Map<String, dynamic> progressData =
              progressDoc.data() as Map<String, dynamic>;
          _readingProgress = progressData['progress'] ?? 0.0;

          if (_hasChapters &&
              chapters.isNotEmpty &&
              progressData['chapterId'] != null) {
            // Find the chapter index
            int chapterIndex = chapters.indexWhere(
              (c) => c['id'] == progressData['chapterId'],
            );
            if (chapterIndex >= 0) {
              _selectedChapterIndex = chapterIndex;
            }
          }
        }
      }

      // Increment view count
      await FirebaseFirestore.instance
          .collection(widget.contentType)
          .doc(widget.contentId)
          .update({'reads': FieldValue.increment(1)});

      setState(() {
        _contentData = data;
        _chapters = chapters;
        _isBookmarked = isBookmarked;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading content: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading content: $e')));
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleBookmark() async {
    final authService = Provider.of<AuthService>(context, listen: false);

    if (authService.currentUser == null) {
      _showLoginRequiredDialog();
      return;
    }

    setState(() {
      _isBookmarked = !_isBookmarked;
    });

    try {
      if (_isBookmarked) {
        // Add bookmark
        await FirebaseFirestore.instance
            .collection('users')
            .doc(authService.currentUser!.uid)
            .collection('bookmarks')
            .doc(widget.contentId)
            .set({
              'contentId': widget.contentId,
              'contentType': widget.contentType,
              'addedAt': FieldValue.serverTimestamp(),
            });
      } else {
        // Remove bookmark
        await FirebaseFirestore.instance
            .collection('users')
            .doc(authService.currentUser!.uid)
            .collection('bookmarks')
            .doc(widget.contentId)
            .delete();
      }
    } catch (e) {
      print('Error toggling bookmark: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating bookmark: $e')));

      // Revert state change on error
      setState(() {
        _isBookmarked = !_isBookmarked;
      });
    }
  }

  Future<void> _toggleLike() async {
    final authService = Provider.of<AuthService>(context, listen: false);

    if (authService.currentUser == null) {
      _showLoginRequiredDialog();
      return;
    }

    try {
      DocumentReference likeRef = FirebaseFirestore.instance
          .collection('users')
          .doc(authService.currentUser!.uid)
          .collection('likes')
          .doc(widget.contentId);

      DocumentSnapshot likeDoc = await likeRef.get();

      if (likeDoc.exists) {
        // Unlike
        await likeRef.delete();
        await FirebaseFirestore.instance
            .collection(widget.contentType)
            .doc(widget.contentId)
            .update({'likes': FieldValue.increment(-1)});

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Removed from your liked content')),
        );
      } else {
        // Like
        await likeRef.set({
          'contentId': widget.contentId,
          'contentType': widget.contentType,
          'likedAt': FieldValue.serverTimestamp(),
        });

        await FirebaseFirestore.instance
            .collection(widget.contentType)
            .doc(widget.contentId)
            .update({'likes': FieldValue.increment(1)});

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added to your liked content')),
        );
      }

      // Refresh content to update like count
      _loadContent();
    } catch (e) {
      print('Error toggling like: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating like: $e')));
    }
  }

  Future<void> _saveReadingProgress() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.currentUser == null) return;

    try {
      String chapterId = '';
      String chapterTitle = '';

      if (_hasChapters &&
          _chapters.isNotEmpty &&
          _selectedChapterIndex < _chapters.length) {
        chapterId = _chapters[_selectedChapterIndex]['id'];
        chapterTitle =
            'Chapter ${_chapters[_selectedChapterIndex]['chapterNumber']}: ${_chapters[_selectedChapterIndex]['title']}';
      } else {
        chapterTitle = 'Reading';
      }

      await Provider.of<FirebaseService>(
        context,
        listen: false,
      ).updateReadingProgress(
        userId: authService.currentUser!.uid,
        contentId: widget.contentId,
        contentType: widget.contentType,
        progress: _readingProgress,
        chapter: chapterTitle,
      );
    } catch (e) {
      print('Error saving reading progress: $e');
    }
  }

  void _shareContent() {
    final String title = _contentData['title'] ?? 'Check out this content';
    final String author = _contentData['authorName'] ?? 'Unknown Author';
    final String shareText = 'Check out "$title" by $author on BanglaLit!';

    // Using share_plus package to share content
    Share.share(shareText);
  }

  void _enterReadingMode() {
    setState(() {
      _isInReadingMode = true;
    });
  }

  void _exitReadingMode() {
    setState(() {
      _isInReadingMode = false;
    });

    // Save progress when exiting reading mode
    _saveReadingProgress();
  }

  void _showLoginRequiredDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Login Required'),
            content: const Text('You need to login to access this feature.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  // Navigate to login page
                },
                child: const Text('Login'),
              ),
            ],
          ),
    );
  }

  void _selectChapter(int index) {
    if (index < 0 || index >= _chapters.length) return;

    setState(() {
      _selectedChapterIndex = index;
      _readingProgress = 0.0; // Reset progress for new chapter
    });

    // Scroll back to top when changing chapters
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_isInReadingMode) {
      return _buildReadingMode();
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar with cover image
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                _contentData['title'] ?? 'No Title',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      blurRadius: 4.0,
                      color: Colors.black,
                      offset: Offset(0.0, 2.0),
                    ),
                  ],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Cover image
                  _contentData['coverUrl'] != null &&
                          _contentData['coverUrl'].isNotEmpty
                      ? CachedNetworkImage(
                        imageUrl: _contentData['coverUrl'],
                        fit: BoxFit.cover,
                        placeholder:
                            (context, url) => Container(
                              color: Colors.deepPurple[300],
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                        errorWidget:
                            (context, url, error) => Container(
                              color: Colors.deepPurple[300],
                              child: const Center(child: Icon(Icons.error)),
                            ),
                      )
                      : Container(
                        color: Colors.deepPurple[300],
                        child: Center(
                          child: Text(
                            _contentData['title']?[0] ?? 'N/A',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 48,
                            ),
                          ),
                        ),
                      ),
                  // Gradient overlay for better text visibility
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                        stops: const [0.7, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                ),
                onPressed: _toggleBookmark,
              ),
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: _shareContent,
              ),
            ],
          ),

          // Content details
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Author and content type
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'By ${_contentData['authorName'] ?? 'Unknown Author'}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _getContentTypeName(widget.contentType),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Genres
                  if (_contentData['genres'] != null &&
                      _contentData['genres'] is List) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(
                        (_contentData['genres'] as List).length,
                        (index) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _contentData['genres'][index],
                            style: TextStyle(
                              color: Colors.deepPurple[800],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Stats row (reads, likes, publish date)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStat(
                        icon: Icons.visibility,
                        value: _contentData['reads']?.toString() ?? '0',
                        label: 'Reads',
                      ),
                      _buildStat(
                        icon: Icons.favorite,
                        value: _contentData['likes']?.toString() ?? '0',
                        label: 'Likes',
                        onTap: _toggleLike,
                      ),
                      _buildStat(
                        icon: Icons.calendar_today,
                        value: _getPublishDate(),
                        label: 'Published',
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Description
                  const Text(
                    'Description',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _contentData['description'] ?? 'No description available.',
                    style: const TextStyle(fontSize: 16),
                  ),

                  const SizedBox(height: 24),

                  // Start reading button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _enterReadingMode,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        _readingProgress > 0.05
                            ? 'Continue Reading (${(_readingProgress * 100).toInt()}%)'
                            : 'Start Reading',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Chapters section (for light novels and comics)
          if (_hasChapters && _chapters.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    const SizedBox(height: 16),
                    const Text(
                      'Chapters',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final chapter = _chapters[index];
                final isSelected = index == _selectedChapterIndex;

                return ListTile(
                  title: Text(
                    'Chapter ${chapter['chapterNumber']}: ${chapter['title']}',
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle:
                      chapter['publishedDate'] != null
                          ? Text(
                            _formatDate(
                              (chapter['publishedDate'] as Timestamp).toDate(),
                            ),
                          )
                          : null,
                  trailing:
                      isSelected
                          ? const Icon(
                            Icons.arrow_forward,
                            color: Colors.deepPurple,
                          )
                          : null,
                  tileColor:
                      isSelected ? Colors.deepPurple.withOpacity(0.1) : null,
                  onTap: () {
                    _selectChapter(index);
                  },
                );
              }, childCount: _chapters.length),
            ),
          ],

          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildReadingMode() {
    final content =
        _hasChapters && _chapters.isNotEmpty
            ? _chapters[_selectedChapterIndex]['content'] ??
                'No content available.'
            : _contentData['content'] ?? 'No content available.';

    final title =
        _hasChapters && _chapters.isNotEmpty
            ? 'Chapter ${_chapters[_selectedChapterIndex]['chapterNumber']}: ${_chapters[_selectedChapterIndex]['title']}'
            : _contentData['title'] ?? 'Reading';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.font_download),
            onPressed: () {
              // Show font settings dialog
              _showFontSettingsDialog();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Reading progress indicator
          LinearProgressIndicator(
            value: _readingProgress,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurple),
          ),

          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child:
                  widget.contentType == 'comics'
                      ? _buildComicReader(content)
                      : _buildTextReader(content),
            ),
          ),

          // Navigation controls for chapters
          if (_hasChapters && _chapters.length > 1)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton(
                    onPressed:
                        _selectedChapterIndex > 0
                            ? () => _selectChapter(_selectedChapterIndex - 1)
                            : null,
                    child: const Text('Previous Chapter'),
                  ),
                  ElevatedButton(
                    onPressed:
                        _selectedChapterIndex < _chapters.length - 1
                            ? () => _selectChapter(_selectedChapterIndex + 1)
                            : null,
                    child: const Text('Next Chapter'),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.close),
        onPressed: _exitReadingMode,
      ),
    );
  }

  Widget _buildTextReader(String content) {
    // Use Markdown for formatted text
    return Markdown(
      controller: _scrollController,
      selectable: true,
      data: content,
    );
  }

  Widget _buildComicReader(String content) {
    // For comics, content would be a list of image URLs
    List<String> imageUrls = [];

    try {
      if (content.isNotEmpty) {
        // Attempt to parse as a list of URLs
        final dynamic contentData = content;
        if (contentData is List) {
          imageUrls = contentData.map((item) => item.toString()).toList();
        } else if (contentData is String) {
          // Try to split by newlines if it's a string
          imageUrls =
              contentData
                  .split('\n')
                  .map((line) => line.trim())
                  .where((line) => line.isNotEmpty)
                  .toList();
        }
      }
    } catch (e) {
      print('Error parsing comic content: $e');
    }

    if (imageUrls.isEmpty) {
      return const Center(child: Text('No comic pages available.'));
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: imageUrls.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: CachedNetworkImage(
            imageUrl: imageUrls[index],
            placeholder:
                (context, url) => Container(
                  height: 300,
                  color: Colors.grey[300],
                  child: const Center(child: CircularProgressIndicator()),
                ),
            errorWidget:
                (context, url, error) => Container(
                  height: 300,
                  color: Colors.grey[300],
                  child: const Center(child: Icon(Icons.error)),
                ),
          ),
        );
      },
    );
  }

  void _showFontSettingsDialog() {
    // This would show a dialog for adjusting text size, font, theme, etc.
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Reading Settings'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Font size slider, theme toggle, etc. would go here
                Text('Font size and appearance settings would go here.'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  Widget _buildStat({
    required IconData icon,
    required String value,
    required String label,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Icon(icon, color: Colors.deepPurple),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  String _getContentTypeName(String type) {
    switch (type) {
      case 'stories':
        return 'Story';
      case 'lightNovels':
        return 'Light Novel';
      case 'comics':
        return 'Comic/Manga';
      default:
        return type;
    }
  }

  String _getPublishDate() {
    if (_contentData['publishedDate'] == null) {
      return 'Unknown';
    }

    final timestamp = _contentData['publishedDate'] as Timestamp;
    return _formatDate(timestamp.toDate());
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMM d, yyyy').format(date);
  }
}
