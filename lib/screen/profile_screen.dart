// profile_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import 'content_detail_screen.dart';
import 'CreateContentScreen.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;

  const ProfileScreen({super.key, required this.userId});

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _userContent = [];
  List<Map<String, dynamic>> _savedContent = [];
  List<Map<String, dynamic>> _followingAuthors = [];
  bool _isLoading = true;
  bool _isCurrentUser = false;
  bool _isFollowing = false;
  int _followersCount = 0;
  int _totalReads = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final firebaseService = Provider.of<FirebaseService>(
        context,
        listen: false,
      );

      // Check if viewing own profile
      _isCurrentUser =
          authService.currentUser != null &&
          authService.currentUser!.uid == widget.userId;

      // Load user data
      final userData = await firebaseService.getUserData(widget.userId);

      // Check if current user is following this profile
      if (authService.currentUser != null && !_isCurrentUser) {
        _isFollowing = await firebaseService.isFollowing(
          authService.currentUser!.uid,
          widget.userId,
        );
      }

      // Get followers count
      _followersCount = await firebaseService.getFollowersCount(widget.userId);

      // Load content created by this user
      final userContent = await firebaseService.getUserContent(widget.userId);

      // Calculate total reads
      _totalReads = userContent.fold(
        0,
        (sum, content) => sum + ((content['reads'] ?? 0) as int),
      );

      // Load saved content (only for current user)
      List<Map<String, dynamic>> savedContent = [];
      if (_isCurrentUser) {
        savedContent = await firebaseService.getSavedContent(widget.userId);
      }

      // Load following authors (only for current user)
      List<Map<String, dynamic>> followingAuthors = [];
      if (_isCurrentUser) {
        followingAuthors = await firebaseService.getFollowingAuthors(
          widget.userId,
        );
      }

      if (mounted) {
        setState(() {
          _userData = userData;
          _userContent = userContent;
          _savedContent = savedContent;
          _followingAuthors = followingAuthors;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading profile data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile data: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isCurrentUser ? 'My Profile' : 'Author Profile'),
        actions: [
          if (_isCurrentUser)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => EditProfileScreen(userData: _userData!),
                  ),
                );
                if (result == true) {
                  _loadUserData();
                }
              },
            ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _userData == null
              ? const Center(child: Text('User not found'))
              : Column(
                children: [
                  _buildProfileHeader(),
                  _buildTabBar(),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildContentTab(),
                        _buildSavedTab(),
                        _buildFollowingTab(),
                      ],
                    ),
                  ),
                ],
              ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Profile image
          CircleAvatar(
            radius: 50,
            backgroundColor: Colors.deepPurple[100],
            backgroundImage:
                _userData!['photoUrl'] != null &&
                        _userData!['photoUrl'].isNotEmpty
                    ? CachedNetworkImageProvider(_userData!['photoUrl'])
                    : null,
            child:
                _userData!['photoUrl'] == null || _userData!['photoUrl'].isEmpty
                    ? Text(
                      _userData!['displayName'] != null
                          ? _userData!['displayName'][0].toUpperCase()
                          : '?',
                      style: const TextStyle(fontSize: 36, color: Colors.white),
                    )
                    : null,
          ),
          const SizedBox(height: 16),

          // Username
          Text(
            _userData!['displayName'] ?? 'Unknown Author',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),

          // Join date
          if (_userData!['createdAt'] != null)
            Text(
              'Member since ${DateFormat('MMMM yyyy').format((_userData!['createdAt'] as Timestamp).toDate())}',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),

          const SizedBox(height: 12),

          // Bio
          if (_userData!['bio'] != null && _userData!['bio'].isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _userData!['bio'],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
            ),

          const SizedBox(height: 16),

          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStat('Stories', _userContent.length.toString()),
              _buildStat('Followers', _followersCount.toString()),
              _buildStat('Reads', _formatNumber(_totalReads)),
            ],
          ),

          const SizedBox(height: 16),

          // Follow/Edit button
          if (!_isCurrentUser)
            SizedBox(
              width: 200,
              child: ElevatedButton(
                onPressed: _toggleFollow,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isFollowing ? Colors.grey[300] : Colors.deepPurple,
                  foregroundColor: _isFollowing ? Colors.black : Colors.white,
                ),
                child: Text(_isFollowing ? 'Unfollow' : 'Follow'),
              ),
            )
          else
            SizedBox(
              width: 200,
              child: ElevatedButton(
                onPressed: () {
                  _showPublishOptions(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                ),
                child: const Text('Publish New Content'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      tabs: [
        Tab(text: _isCurrentUser ? 'My Content' : 'Content'),
        Tab(text: 'Saved', icon: _isCurrentUser ? null : Icon(Icons.lock)),
        Tab(text: 'Following', icon: _isCurrentUser ? null : Icon(Icons.lock)),
      ],
    );
  }

  Widget _buildContentTab() {
    if (_userContent.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.book, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _isCurrentUser
                  ? 'You haven\'t published any content yet'
                  : 'This author hasn\'t published any content yet',
              style: TextStyle(color: Colors.grey[600]),
            ),
            if (_isCurrentUser) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _showPublishOptions(context),
                child: const Text('Publish Your First Content'),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _userContent.length,
      itemBuilder: (context, index) {
        final item = _userContent[index];
        return _buildContentItem(item);
      },
    );
  }

  Widget _buildSavedTab() {
    if (!_isCurrentUser) {
      return const Center(
        child: Text('This tab is only visible to the profile owner'),
      );
    }

    if (_savedContent.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark_border, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'You haven\'t saved any content yet',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _savedContent.length,
      itemBuilder: (context, index) {
        final item = _savedContent[index];
        return _buildContentItem(item);
      },
    );
  }

  Widget _buildFollowingTab() {
    if (!_isCurrentUser) {
      return const Center(
        child: Text('This tab is only visible to the profile owner'),
      );
    }

    if (_followingAuthors.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'You aren\'t following any authors yet',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _followingAuthors.length,
      itemBuilder: (context, index) {
        final author = _followingAuthors[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.deepPurple[100],
            backgroundImage:
                author['photoUrl'] != null && author['photoUrl'].isNotEmpty
                    ? CachedNetworkImageProvider(author['photoUrl'])
                    : null,
            child:
                author['photoUrl'] == null || author['photoUrl'].isEmpty
                    ? Text(
                      author['displayName'] != null
                          ? author['displayName'][0].toUpperCase()
                          : '?',
                      style: const TextStyle(color: Colors.white),
                    )
                    : null,
          ),
          title: Text(author['displayName'] ?? 'Unknown Author'),
          subtitle: Text(
            '${author['contentCount'] ?? 0} stories · ${author['followersCount'] ?? 0} followers',
          ),
          trailing: ElevatedButton(
            onPressed: () => _unfollowAuthor(author['id']),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[300],
              foregroundColor: Colors.black,
              minimumSize: const Size(80, 36),
            ),
            child: const Text('Unfollow'),
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProfileScreen(userId: author['id']),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildContentItem(Map<String, dynamic> item) {
    final timestamp = item['publishedDate'] as Timestamp?;
    final publishDate = timestamp != null ? timestamp.toDate() : DateTime.now();
    final timeAgo = _getTimeAgo(publishDate);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: InkWell(
        onTap: () => _navigateToContentDetail(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image
            if (item['coverUrl'] != null && item['coverUrl'].isNotEmpty)
              SizedBox(
                height: 150,
                width: double.infinity,
                child: CachedNetworkImage(
                  imageUrl: item['coverUrl'],
                  fit: BoxFit.cover,
                  placeholder:
                      (context, url) => Container(
                        color: Colors.deepPurple[100],
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                  errorWidget:
                      (context, url, error) => Container(
                        color: Colors.deepPurple[100],
                        child: const Center(child: Icon(Icons.error)),
                      ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and type badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item['title'] ?? 'Untitled',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
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
                          _getContentTypeName(item['type'] ?? 'stories'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Summary
                  if (item['summary'] != null && item['summary'].isNotEmpty)
                    Text(
                      item['summary'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),

                  const SizedBox(height: 12),

                  // Stats row
                  Row(
                    children: [
                      Icon(
                        Icons.remove_red_eye,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${item['reads'] ?? 0}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.favorite, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        '${item['likes'] ?? 0}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.comment, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        '${item['comments'] ?? 0}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                      const Spacer(),
                      Text(
                        timeAgo,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPublishOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Publish Your Creation',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              _buildPublishOption(
                icon: Icons.book,
                title: 'Write a Story',
                description: 'Short stories, novellas, and more',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) =>
                              CreateContentScreen(contentType: 'stories'),
                    ),
                  );
                },
              ),
              const Divider(),
              _buildPublishOption(
                icon: Icons.menu_book,
                title: 'Create a Light Novel',
                description: 'Series with chapters and illustrations',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) =>
                              CreateContentScreen(contentType: 'lightNovels'),
                    ),
                  );
                },
              ),
              const Divider(),
              _buildPublishOption(
                icon: Icons.photo_library,
                title: 'Publish a Comic/Manga',
                description: 'Visual stories and illustrations',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) =>
                              CreateContentScreen(contentType: 'comics'),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPublishOption({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.deepPurple, size: 28),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(description),
      onTap: onTap,
    );
  }

  Future<void> _toggleFollow() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final firebaseService = Provider.of<FirebaseService>(
      context,
      listen: false,
    );

    if (authService.currentUser == null) {
      _showLoginRequiredDialog();
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isFollowing) {
        await firebaseService.unfollowAuthor(
          authService.currentUser!.uid,
          widget.userId,
        );
        _followersCount--;
      } else {
        await firebaseService.followAuthor(
          authService.currentUser!.uid,
          widget.userId,
        );
        _followersCount++;
      }

      setState(() {
        _isFollowing = !_isFollowing;
        _isLoading = false;
      });
    } catch (e) {
      print('Error toggling follow: $e');
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _unfollowAuthor(String authorId) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final firebaseService = Provider.of<FirebaseService>(
      context,
      listen: false,
    );

    setState(() {
      _isLoading = true;
    });

    try {
      await firebaseService.unfollowAuthor(
        authService.currentUser!.uid,
        authorId,
      );

      // Reload following authors
      await _loadUserData();
    } catch (e) {
      print('Error unfollowing author: $e');
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _navigateToContentDetail(Map<String, dynamic> item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => ContentDetailScreen(
              contentId: item['id'],
              contentType: item['type'] ?? 'stories',
            ),
      ),
    );
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

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 30) {
      return DateFormat('MMM d, yyyy').format(dateTime);
    } else if (difference.inDays > 1) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inHours > 1) {
      return '${difference.inHours} hours ago';
    } else if (difference.inMinutes > 1) {
      return '${difference.inMinutes} minutes ago';
    } else {
      return 'Just now';
    }
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    } else {
      return number.toString();
    }
  }
}
