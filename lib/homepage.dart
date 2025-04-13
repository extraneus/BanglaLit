// home_page.dart (Updated with Firebase)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'services/auth_service.dart';
import 'services/firebase_service.dart';
import 'screen/content_detail_screen.dart';
import 'screen/CreateContentScreen.dart';
import 'screen/profile_screen.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  _HomepageState createState() => _HomepageState();
}

class _HomepageState extends State<Homepage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentCarouselIndex = 0;

  // Data loaded from Firebase
  List<Map<String, dynamic>> _featuredItems = [];
  List<Map<String, dynamic>> _popularItems = [];
  List<Map<String, dynamic>> _newReleases = [];
  List<Map<String, dynamic>> _continueReading = [];
  bool _isLoading = true;

  final List<String> _categories = [
    'Romance',
    'Fantasy',
    'Adventure',
    'Mystery',
    'Thriller',
    'Science Fiction',
    'Comedy',
    'Drama',
    'Historical',
    'Horror',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final firebaseService = Provider.of<FirebaseService>(
        context,
        listen: false,
      );
      final authService = Provider.of<AuthService>(context, listen: false);

      // Load data in parallel
      final featuredFuture = firebaseService.getFeaturedItems();
      final popularFuture = firebaseService.getPopularContent();
      final newReleasesFuture = firebaseService.getNewReleases();

      // Only load continue reading if user is logged in
      final continueFuture =
          authService.currentUser != null
              ? firebaseService.getContinueReading(authService.currentUser!.uid)
              : Future.value(<Map<String, dynamic>>[]);

      // Wait for all futures to complete
      final results = await Future.wait([
        featuredFuture,
        popularFuture,
        newReleasesFuture,
        continueFuture,
      ]);

      setState(() {
        _featuredItems = results[0];
        _popularItems = results[1];
        _newReleases = results[2];
        _continueReading = results[3];
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading data: $e');
      setState(() {
        _isLoading = false;
      });
      // Show error snackbar
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'BanglaLit',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // Search functionality
              showSearch(
                context: context,
                delegate: ContentSearchDelegate(
                  Provider.of<FirebaseService>(context, listen: false),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: () {
              if (authService.currentUser != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) =>
                            ProfileScreen(userId: authService.currentUser!.uid),
                  ),
                );
              } else {
                // Show login dialog
                _showLoginRequiredDialog();
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Stories'),
            Tab(text: 'Light Novels'),
            Tab(text: 'Comics/Manga'),
          ],
        ),
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                controller: _tabController,
                children: [
                  _buildContentTab('stories'),
                  _buildContentTab('lightNovels'),
                  _buildContentTab('comics'),
                ],
              ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          if (authService.currentUser != null) {
            _showPublishOptions(context);
          } else {
            _showLoginRequiredDialog();
          }
        },
      ),
      drawer: Drawer(child: _buildDrawer(context)),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        DrawerHeader(
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 91, 51, 160),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'BanglaLit',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (authService.currentUser != null) ...[
                Text(
                  'Welcome, ${authService.currentUser!.displayName ?? 'User'}',
                  style: const TextStyle(color: Colors.white),
                ),
              ] else ...[
                const Text(
                  'Join the community',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.home),
          title: const Text('Home'),
          onTap: () {
            Navigator.pop(context);
          },
        ),
        ListTile(
          leading: const Icon(Icons.favorite),
          title: const Text('My Library'),
          onTap: () {
            Navigator.pop(context);
            if (authService.currentUser != null) {
              // Navigate to library
            } else {
              _showLoginRequiredDialog();
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.category),
          title: const Text('Categories'),
          onTap: () {
            Navigator.pop(context);
            // Navigate to categories
          },
        ),
        const Divider(),
        if (authService.currentUser != null) ...[
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () {
              Navigator.pop(context);
              // Navigate to settings
            },
          ),
          ListTile(
            leading: const Icon(Icons.exit_to_app),
            title: const Text('Sign Out'),
            onTap: () async {
              await authService.signOut();
              Navigator.pop(context);
            },
          ),
        ] else ...[
          ListTile(
            leading: const Icon(Icons.login),
            title: const Text('Sign In'),
            onTap: () {
              Navigator.pop(context);
              // Navigate to login
            },
          ),
        ],
      ],
    );
  }

  Widget _buildContentTab(String contentType) {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          // Featured Carousel
          if (_featuredItems.isNotEmpty) _buildFeaturedCarousel(),

          // Categories Section
          _buildCategoriesSection(),

          // Popular This Week
          _buildSectionTitle('Popular This Week'),
          _popularItems.isNotEmpty
              ? _buildPopularGrid()
              : const Center(child: Text('No popular content available')),

          // New Releases
          _buildSectionTitle('New Releases'),
          _newReleases.isNotEmpty
              ? _buildNewReleasesGrid()
              : const Center(child: Text('No new releases available')),

          // Continue Reading (only if there are items and user is logged in)
          if (_continueReading.isNotEmpty) ...[
            _buildSectionTitle('Continue Reading'),
            _buildContinueReadingList(),
          ],

          const SizedBox(height: 70), // Bottom padding for FAB
        ],
      ),
    );
  }

  Widget _buildFeaturedCarousel() {
    return SizedBox(
      height: 200,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: _featuredItems.length,
            onPageChanged: (index) {
              setState(() {
                _currentCarouselIndex = index;
              });
            },
            itemBuilder: (context, index) {
              final item = _featuredItems[index];
              return GestureDetector(
                onTap: () {
                  _navigateToContentDetail(item);
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Cover image
                    item['coverUrl'] != null && item['coverUrl'].isNotEmpty
                        ? CachedNetworkImage(
                          imageUrl: item['coverUrl'],
                          fit: BoxFit.cover,
                          placeholder:
                              (context, url) => Container(
                                color: Colors.deepPurple[(index + 1) * 100],
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                          errorWidget:
                              (context, url, error) => Container(
                                color: Colors.deepPurple[(index + 1) * 100],
                                child: const Center(child: Icon(Icons.error)),
                              ),
                        )
                        : Container(
                          color: Colors.deepPurple[(index + 1) * 100],
                          child: Center(
                            child: Text(
                              item['title'],
                              style: const TextStyle(color: Colors.white),
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
                            const Color.fromARGB(
                              255,
                              10,
                              10,
                              10,
                            ).withOpacity(0.7),
                          ],
                          stops: const [0.6, 1.0],
                        ),
                      ),
                    ),

                    // Content details
                    Positioned(
                      bottom: 20,
                      left: 16,
                      right: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['title'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'By ${item['authorName']}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _getContentTypeName(
                                    item['type'] ??
                                        'default', // Replace 'default' with an appropriate fallback
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              if (item['genres'] != null &&
                                  item['genres'] is List &&
                                  item['genres'].isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurple.shade200,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    item['genres'][0],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // Carousel indicators
          Positioned(
            bottom: 5,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _featuredItems.length,
                (index) => Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        _currentCarouselIndex == index
                            ? Colors.white
                            : Colors.white.withOpacity(0.5),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesSection() {
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          return Container(
            margin: const EdgeInsets.only(right: 8),
            child: ElevatedButton(
              onPressed: () {
                _showCategoryContent(_categories[index]);
              },
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(_categories[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          TextButton(
            onPressed: () {
              // See all functionality
              _showAllContent(title);
            },
            child: const Text('See All'),
          ),
        ],
      ),
    );
  }

  Widget _buildPopularGrid() {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.7,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _popularItems.length,
      itemBuilder: (context, index) {
        final item = _popularItems[index];
        return _buildBookItem(
          title: item['title'],
          author: item['authorName'],
          coverUrl: item['coverUrl'],
          badge: '${item['reads']} reads',
          onTap: () => _navigateToContentDetail(item),
        );
      },
    );
  }

  Widget _buildNewReleasesGrid() {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.8,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _newReleases.length,
      itemBuilder: (context, index) {
        final item = _newReleases[index];
        final timestamp = item['publishedDate'] as Timestamp?;
        final publishDate =
            timestamp != null ? timestamp.toDate() : DateTime.now();
        final timeAgo = _getTimeAgo(publishDate);

        return _buildBookItem(
          title: item['title'],
          author: item['authorName'],
          coverUrl: item['coverUrl'],
          badge: timeAgo,
          isLarge: true,
          onTap: () => _navigateToContentDetail(item),
        );
      },
    );
  }

  Widget _buildContinueReadingList() {
    return Container(
      height: 180,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _continueReading.length,
        itemBuilder: (context, index) {
          final item = _continueReading[index];
          return Container(
            width: 300,
            margin: const EdgeInsets.only(right: 16),
            child: Card(
              elevation: 4,
              child: InkWell(
                onTap: () => _navigateToContentDetail(item),
                child: Row(
                  children: [
                    SizedBox(
                      width: 120,
                      height: double.infinity,
                      child:
                          item['coverUrl'] != null &&
                                  item['coverUrl'].isNotEmpty
                              ? CachedNetworkImage(
                                imageUrl: item['coverUrl'],
                                fit: BoxFit.cover,
                                placeholder:
                                    (context, url) => Container(
                                      color: Colors.amber[100 * (index + 1)],
                                      child: const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    ),
                                errorWidget:
                                    (context, url, error) => Container(
                                      color: Colors.amber[100 * (index + 1)],
                                      child: const Center(
                                        child: Icon(Icons.error),
                                      ),
                                    ),
                              )
                              : Container(
                                color: Colors.amber[100 * (index + 1)],
                                child: Center(
                                  child: Text(
                                    'Cover',
                                    style: TextStyle(color: Colors.amber[900]),
                                  ),
                                ),
                              ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              item['title'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'By ${item['authorName']}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              item['chapter'] ?? 'Chapter 1',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: item['progress'] ?? 0.0,
                              backgroundColor: Colors.grey[200],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.deepPurple,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${((item['progress'] ?? 0.0) * 100).toInt()}%',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBookItem({
    required String title,
    required String author,
    String? coverUrl,
    required String badge,
    bool isLarge = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: coverUrl == null ? Colors.deepPurple[200] : null,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child:
                      coverUrl != null && coverUrl.isNotEmpty
                          ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: coverUrl,
                              fit: BoxFit.cover,
                              placeholder:
                                  (context, url) => const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                              errorWidget:
                                  (context, url, error) =>
                                      const Center(child: Icon(Icons.error)),
                            ),
                          )
                          : Center(
                            child: Text(
                              title.substring(
                                0,
                                title.length > 2 ? 2 : title.length,
                              ),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                ),
                Positioned(
                  top: 5,
                  right: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: isLarge ? 14 : 12,
            ),
          ),
          Text(
            'By $author',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: isLarge ? 12 : 10,
            ),
          ),
        ],
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

  void _showCategoryContent(String category) {
    // Navigate to category content page
  }

  void _showAllContent(String sectionTitle) {
    // Navigate to see all content for the section
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
}

// ContentSearchDelegate class for search functionality
class ContentSearchDelegate extends SearchDelegate<String> {
  final FirebaseService _firebaseService;

  ContentSearchDelegate(this._firebaseService);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, '');
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _searchContent(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No results found'));
        } else {
          return ListView.builder(
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final item = snapshot.data![index];
              return ListTile(
                leading:
                    item['coverUrl'] != null && item['coverUrl'].isNotEmpty
                        ? ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: CachedNetworkImage(
                            imageUrl: item['coverUrl'],
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                          ),
                        )
                        : Container(
                          width: 50,
                          height: 50,
                          color: Colors.deepPurple[200],
                          child: Center(
                            child: Text(
                              item['title'][0],
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                title: Text(item['title']),
                subtitle: Text('By ${item['authorName']}'),
                trailing: Text(
                  _getContentTypeName(item['type']),
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                onTap: () {
                  close(context, item['id']);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => ContentDetailScreen(
                            contentId: item['id'],
                            contentType: item['type'],
                          ),
                    ),
                  );
                },
              );
            },
          );
        }
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.length < 3) {
      return const Center(child: Text('Type at least 3 characters to search'));
    }

    return buildResults(context);
  }

  Future<List<Map<String, dynamic>>> _searchContent(String query) async {
    if (query.length < 3) return [];

    List<Map<String, dynamic>> results = [];

    // Search in all content types
    for (String type in ['stories', 'lightNovels', 'comics']) {
      QuerySnapshot snapshot =
          await FirebaseFirestore.instance
              .collection(type)
              .where('title', isGreaterThanOrEqualTo: query)
              .where('title', isLessThanOrEqualTo: '$query\uf8ff')
              .limit(5)
              .get();

      for (var doc in snapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        data['type'] = type;
        results.add(data);
      }
    }

    return results;
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
}
