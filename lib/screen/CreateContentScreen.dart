// create_content_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path/path.dart' as path;
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import 'content_detail_screen.dart';

class CreateContentScreen extends StatefulWidget {
  final String contentType;
  final Map<String, dynamic>? existingContent; // For editing existing content

  const CreateContentScreen({
    super.key,
    required this.contentType,
    this.existingContent,
  });

  @override
  _CreateContentScreenState createState() => _CreateContentScreenState();
}

class _CreateContentScreenState extends State<CreateContentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _synopsisController = TextEditingController();
  final _contentController = TextEditingController();

  List<String> _selectedGenres = [];
  File? _coverImage;
  bool _isUploading = false;
  bool _isPremium = false;
  String _contentTypeTitle = 'Story';

  // Available genres
  final List<String> _availableGenres = [
    'Fantasy',
    'Science Fiction',
    'Romance',
    'Mystery',
    'Horror',
    'Adventure',
    'Action',
    'Comedy',
    'Drama',
    'Thriller',
    'Historical',
    'Slice of Life',
    'Supernatural',
    'Psychological',
  ];

  @override
  void initState() {
    super.initState();

    // Set the content type title
    switch (widget.contentType) {
      case 'stories':
        _contentTypeTitle = 'Story';
        break;
      case 'lightNovels':
        _contentTypeTitle = 'Light Novel';
        break;
      case 'comics':
        _contentTypeTitle = 'Comic/Manga';
        break;
    }

    // If editing existing content, populate the form
    if (widget.existingContent != null) {
      _titleController.text = widget.existingContent!['title'] ?? '';
      _synopsisController.text = widget.existingContent!['synopsis'] ?? '';
      _contentController.text = widget.existingContent!['content'] ?? '';
      _isPremium = widget.existingContent!['isPremium'] ?? false;

      if (widget.existingContent!['genres'] != null) {
        _selectedGenres = List<String>.from(widget.existingContent!['genres']);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _synopsisController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _coverImage = File(pickedFile.path);
      });
    }
  }

  void _toggleGenre(String genre) {
    setState(() {
      if (_selectedGenres.contains(genre)) {
        _selectedGenres.remove(genre);
      } else {
        _selectedGenres.add(genre);
      }
    });
  }

  Future<void> _submitContent() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    final firebaseService = Provider.of<FirebaseService>(
      context,
      listen: false,
    );

    if (authService.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in to publish content'),
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      String? coverUrl;

      // Upload cover image if selected
      if (_coverImage != null) {
        final filename = path.basename(_coverImage!.path);
        final destination =
            'covers/${authService.currentUser!.uid}/${DateTime.now().millisecondsSinceEpoch}_$filename';

        final ref = FirebaseStorage.instance.ref(destination);
        await ref.putFile(_coverImage!);
        coverUrl = await ref.getDownloadURL();
      }

      // Create content data map
      final contentData = {
        'title': _titleController.text.trim(),
        'synopsis': _synopsisController.text.trim(),
        'content':
            widget.contentType == 'comics'
                ? ''
                : _contentController.text.trim(),
        'authorId': authService.currentUser!.uid,
        'authorName': authService.currentUser!.displayName ?? 'Anonymous',
        'authorProfilePic': authService.currentUser!.photoURL ?? '',
        'publishedDate': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
        'coverUrl': coverUrl ?? '',
        'type': widget.contentType,
        'genres': _selectedGenres,
        'isPremium': _isPremium,
        'reads': 0,
        'likes': 0,
        'comments': 0,
        'rating': 0.0,
        'ratingCount': 0,
      };

      String contentId;
      if (widget.existingContent != null) {
        // Update existing content
        contentId = widget.existingContent!['id'];
        await firebaseService.updateContent(
          contentId,
          widget.contentType,
          contentData,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Content updated successfully')),
        );
      } else {
        // Create new content
        contentId = await firebaseService.createContent(
          widget.contentType,
          contentData,
        );

        // For light novels and comics, redirect to chapter creation
        if (widget.contentType == 'lightNovels' ||
            widget.contentType == 'comics') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Content created! Now add your first chapter'),
            ),
          );

          // Navigate to chapter creation screen
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder:
                  (context) => AddChapterScreen(
                    contentId: contentId,
                    contentType: widget.contentType,
                    isFirstChapter: true,
                  ),
            ),
          );
          return;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Content published successfully')),
          );
        }
      }

      // Navigate to content detail screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (context) => ContentDetailScreen(
                contentId: contentId,
                contentType: widget.contentType,
              ),
        ),
      );
    } catch (e) {
      print('Error publishing content: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error publishing content: $e')));
      setState(() {
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingContent != null
              ? 'Edit $_contentTypeTitle'
              : 'Create $_contentTypeTitle',
        ),
        actions: [
          TextButton(
            onPressed: _isUploading ? null : _submitContent,
            child: Text(
              'Publish',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body:
          _isUploading
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Publishing your content...'),
                  ],
                ),
              )
              : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cover image
                      _buildCoverImageSection(),
                      const SizedBox(height: 24),

                      // Title field
                      TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a title';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Synopsis field
                      TextFormField(
                        controller: _synopsisController,
                        decoration: const InputDecoration(
                          labelText: 'Synopsis',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 5,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a synopsis';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Genres
                      _buildGenresSection(),
                      const SizedBox(height: 16),

                      // Premium toggle
                      SwitchListTile(
                        title: const Text('Premium Content'),
                        subtitle: const Text(
                          'Make this content available only to premium users',
                        ),
                        value: _isPremium,
                        activeColor: Colors.deepPurple,
                        onChanged: (value) {
                          setState(() {
                            _isPremium = value;
                          });
                        },
                      ),
                      const SizedBox(height: 16),

                      // Content field (only for stories, not for light novels or comics)
                      if (widget.contentType == 'stories') ...[
                        const Text(
                          'Content',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _contentController,
                          decoration: const InputDecoration(
                            hintText: 'Write your story here...',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 20,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your story content';
                            }
                            return null;
                          },
                        ),
                      ],

                      const SizedBox(height: 32),

                      // Submit button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submitContent,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Text(
                            widget.contentType == 'stories'
                                ? 'Publish Story'
                                : 'Create & Add Chapters',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
    );
  }

  Widget _buildCoverImageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cover Image',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickImage,
          child: Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey),
            ),
            child:
                _coverImage != null
                    ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(_coverImage!, fit: BoxFit.cover),
                    )
                    : widget.existingContent != null &&
                        widget.existingContent!['coverUrl'] != null &&
                        widget.existingContent!['coverUrl'].isNotEmpty
                    ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        widget.existingContent!['coverUrl'],
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              value:
                                  loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                      : null,
                            ),
                          );
                        },
                      ),
                    )
                    : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.add_photo_alternate,
                          size: 48,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Upload Cover Image',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
          ),
        ),
      ],
    );
  }

  Widget _buildGenresSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Genres (Select up to 3)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              _availableGenres.map((genre) {
                final isSelected = _selectedGenres.contains(genre);
                return FilterChip(
                  label: Text(genre),
                  selected: isSelected,
                  selectedColor: Colors.deepPurple.withOpacity(0.3),
                  checkmarkColor: Colors.deepPurple,
                  onSelected:
                      _selectedGenres.length >= 3 && !isSelected
                          ? null
                          : (_) => _toggleGenre(genre),
                );
              }).toList(),
        ),
      ],
    );
  }
}

class AddChapterScreen extends StatefulWidget {
  final String contentId;
  final String contentType;
  final bool isFirstChapter;
  final Map<String, dynamic>? existingChapter;

  const AddChapterScreen({
    super.key,
    required this.contentId,
    required this.contentType,
    this.isFirstChapter = false,
    this.existingChapter,
  });

  @override
  _AddChapterScreenState createState() => _AddChapterScreenState();
}

class _AddChapterScreenState extends State<AddChapterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final List<File> _chapterImages = [];
  bool _isUploading = false;
  int _chapterNumber = 1;

  @override
  void initState() {
    super.initState();

    // If editing existing chapter, populate form
    if (widget.existingChapter != null) {
      _titleController.text = widget.existingChapter!['title'] ?? '';
      _contentController.text = widget.existingChapter!['content'] ?? '';
      _chapterNumber = widget.existingChapter!['number'] ?? 1;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage();

    if (pickedFiles.isNotEmpty) {
      setState(() {
        _chapterImages.addAll(pickedFiles.map((e) => File(e.path)).toList());
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _chapterImages.removeAt(index);
    });
  }

  Future<void> _submitChapter() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    final firebaseService = Provider.of<FirebaseService>(
      context,
      listen: false,
    );

    if (authService.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in to publish content'),
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      List<String> imageUrls = [];

      // Upload images if this is a comic
      if (widget.contentType == 'comics' && _chapterImages.isNotEmpty) {
        for (int i = 0; i < _chapterImages.length; i++) {
          final file = _chapterImages[i];
          final filename = path.basename(file.path);
          final destination =
              'chapters/${widget.contentId}/${DateTime.now().millisecondsSinceEpoch}_$filename';

          final ref = FirebaseStorage.instance.ref(destination);
          await ref.putFile(file);
          final url = await ref.getDownloadURL();
          imageUrls.add(url);
        }
      }

      // Create chapter data
      final chapterData = {
        'title': _titleController.text.trim(),
        'content':
            widget.contentType == 'comics'
                ? ''
                : _contentController.text.trim(),
        'images': imageUrls,
        'publishedDate': FieldValue.serverTimestamp(),
        'number':
            widget.existingChapter != null
                ? widget.existingChapter!['number']
                : await firebaseService.getNextChapterNumber(
                  widget.contentId,
                  widget.contentType,
                ),
      };

      if (widget.existingChapter != null) {
        // Update existing chapter
        await firebaseService.updateChapter(
          widget.contentId,
          widget.contentType,
          widget.existingChapter!['id'],
          chapterData,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chapter updated successfully')),
        );
      } else {
        // Create new chapter
        await firebaseService.addChapter(
          widget.contentId,
          widget.contentType,
          chapterData,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chapter published successfully')),
        );
      }

      // Navigate back to content detail
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (context) => ContentDetailScreen(
                contentId: widget.contentId,
                contentType: widget.contentType,
              ),
        ),
      );
    } catch (e) {
      print('Error publishing chapter: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error publishing chapter: $e')));
      setState(() {
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingChapter != null
              ? 'Edit Chapter'
              : widget.isFirstChapter
              ? 'Add First Chapter'
              : 'Add New Chapter',
        ),
        actions: [
          TextButton(
            onPressed: _isUploading ? null : _submitChapter,
            child: const Text(
              'Publish',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body:
          _isUploading
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Publishing your chapter...'),
                  ],
                ),
              )
              : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title field
                      TextFormField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          labelText: 'Chapter Title',
                          hintText:
                              'e.g. Chapter $_chapterNumber: New Beginnings',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a chapter title';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // For comics - image upload section
                      if (widget.contentType == 'comics') ...[
                        _buildComicImagesSection(),
                      ],

                      // For light novels - content text field
                      if (widget.contentType == 'lightNovels') ...[
                        const Text(
                          'Chapter Content',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _contentController,
                          decoration: const InputDecoration(
                            hintText: 'Write your chapter content here...',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 20,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your chapter content';
                            }
                            return null;
                          },
                        ),
                      ],

                      const SizedBox(height: 32),

                      // Submit button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submitChapter,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Text(
                            widget.existingChapter != null
                                ? 'Update Chapter'
                                : 'Publish Chapter',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
    );
  }

  Widget _buildComicImagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Comic Pages',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            ElevatedButton.icon(
              onPressed: _pickImages,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Add Images'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_chapterImages.isEmpty)
          Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.photo_library, size: 48, color: Colors.grey),
                SizedBox(height: 8),
                Text(
                  'No images selected',
                  style: TextStyle(color: Colors.grey),
                ),
                SizedBox(height: 4),
                Text(
                  'Tap "Add Images" to upload comic pages',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          )
        else
          Column(
            children: [
              const Text(
                'Tip: Drag to reorder images',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _chapterImages.length,
                itemBuilder: (context, index) {
                  return Card(
                    key: Key('$index'),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: SizedBox(
                        width: 60,
                        height: 60,
                        child: Image.file(
                          _chapterImages[index],
                          fit: BoxFit.cover,
                        ),
                      ),
                      title: Text('Page ${index + 1}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeImage(index),
                      ),
                    ),
                  );
                },
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (oldIndex < newIndex) {
                      newIndex -= 1;
                    }
                    final item = _chapterImages.removeAt(oldIndex);
                    _chapterImages.insert(newIndex, item);
                  });
                },
              ),
            ],
          ),
        const SizedBox(height: 8),
        if (_chapterImages.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              'Your comic must have at least one image',
              style: TextStyle(color: Colors.red),
            ),
          ),
      ],
    );
  }
}

// This would typically be in an EditProfileScreen file
class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const EditProfileScreen({super.key, required this.userData});

  @override
  _EditProfileScreenState createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();

  File? _profileImage;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _displayNameController.text = widget.userData['displayName'] ?? '';
    _bioController.text = widget.userData['bio'] ?? '';
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _profileImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final firebaseService = Provider.of<FirebaseService>(
        context,
        listen: false,
      );

      String? photoUrl = widget.userData['photoUrl'];

      // Upload new profile image if selected
      if (_profileImage != null) {
        final filename = path.basename(_profileImage!.path);
        final destination =
            'profile_images/${authService.currentUser!.uid}/$filename';

        final ref = FirebaseStorage.instance.ref(destination);
        await ref.putFile(_profileImage!);
        photoUrl = await ref.getDownloadURL();
      }

      // Update profile data
      await firebaseService.updateUserProfile(authService.currentUser!.uid, {
        'displayName': _displayNameController.text.trim(),
        'bio': _bioController.text.trim(),
        'photoUrl': photoUrl,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );

      Navigator.pop(context, true); // Return true to indicate successful update
    } catch (e) {
      print('Error updating profile: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating profile: $e')));

      setState(() {
        _isUpdating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          TextButton(
            onPressed: _isUpdating ? null : _updateProfile,
            child: const Text(
              'Save',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body:
          _isUpdating
              ? const Center(child: CircularProgressIndicator())
              : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // Profile image
                      GestureDetector(
                        onTap: _pickImage,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircleAvatar(
                              radius: 60,
                              backgroundColor: Colors.deepPurple[100],
                              backgroundImage:
                                  _profileImage != null
                                      ? FileImage(_profileImage!)
                                      : (widget.userData['photoUrl'] != null &&
                                                  widget
                                                      .userData['photoUrl']
                                                      .isNotEmpty
                                              ? NetworkImage(
                                                widget.userData['photoUrl'],
                                              )
                                              : null)
                                          as ImageProvider?,
                              child:
                                  widget.userData['photoUrl'] == null &&
                                          _profileImage ==
                                              null // Continuing from where the code was cut off, inside the CircleAvatar's child property
                                      ? const Icon(
                                        Icons.person,
                                        size: 60,
                                        color: Colors.white,
                                      )
                                      : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Display name field
                      TextFormField(
                        controller: _displayNameController,
                        decoration: const InputDecoration(
                          labelText: 'Display Name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a display name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Bio field
                      TextFormField(
                        controller: _bioController,
                        decoration: const InputDecoration(
                          labelText: 'Bio',
                          hintText: 'Tell us about yourself...',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 5,
                      ),
                      const SizedBox(height: 32),

                      // Submit button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _updateProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Update Profile'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
    );
  }
}
