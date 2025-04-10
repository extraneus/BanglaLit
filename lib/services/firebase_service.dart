import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final Uuid _uuid = const Uuid();

  // Collection references
  CollectionReference get stories => _firestore.collection('stories');
  CollectionReference get lightNovels => _firestore.collection('lightNovels');
  CollectionReference get comics => _firestore.collection('comics');
  CollectionReference get users => _firestore.collection('users');

    Future<Map<String, dynamic>> getContentDetails(String contentId, String contentType) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(contentType)
          .doc(contentId)
          .get();

      if (doc.exists) {
        return doc.data() as Map<String, dynamic>;
      } else {
        throw Exception('Content not found');
      }
    } catch (e) {
      throw Exception('Error fetching content details: $e');
    }
  }
}

  // Get featured content
  Future<List<Map<String, dynamic>>> getFeaturedItems() async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('featured')
          .orderBy('date', descending: true)
          .limit(5)
          .get();
      
      return snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('Error getting featured items: $e');
      return [];
    }
  }

  // Get content by type (stories, light novels, comics)
  Future<List<Map<String, dynamic>>> getContentByType(String type) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection(type)
          .orderBy('publishedDate', descending: true)
          .limit(20)
          .get();
      
      return snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('Error getting $type: $e');
      return [];
    }
  }

  // Get popular content
  Future<List<Map<String, dynamic>>> getPopularContent() async {
    try {
      // Get popular content across all types sorted by read count
      QuerySnapshot storiesSnap = await stories.orderBy('reads', descending: true).limit(3).get();
      QuerySnapshot novelsSnap = await lightNovels.orderBy('reads', descending: true).limit(3).get();
      QuerySnapshot comicsSnap = await comics.orderBy('reads', descending: true).limit(3).get();
      
      List<Map<String, dynamic>> result = [];
      
      // Process all three collections
      for (var doc in storiesSnap.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        data['type'] = 'stories';
        result.add(data);
      }
      
      for (var doc in novelsSnap.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        data['type'] = 'lightNovels';
        result.add(data);
      }
      
      for (var doc in comicsSnap.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        data['type'] = 'comics';
        result.add(data);
      }
      
      // Sort combined results by reads
      result.sort((a, b) => (b['reads'] as num).compareTo(a['reads'] as num));
      return result.take(6).toList();
    } catch (e) {
      print('Error getting popular content: $e');
      return [];
    }
  }

  // Get new releases
  Future<List<Map<String, dynamic>>> getNewReleases() async {
    try {
      final DateTime oneWeekAgo = DateTime.now().subtract(const Duration(days: 7));
      
      QuerySnapshot snapshot = await _firestore
          .collectionGroup('content')
          .where('publishedDate', isGreaterThan: oneWeekAgo)
          .orderBy('publishedDate', descending: true)
          .limit(4)
          .get();
      
      return snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('Error getting new releases: $e');
      return [];
    }
  }

  // Get user's reading progress
  Future<List<Map<String, dynamic>>> getContinueReading(String userId) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('readingProgress')
          .orderBy('lastReadTimestamp', descending: true)
          .limit(3)
          .get();
      
      List<Map<String, dynamic>> progressItems = snapshot.docs.map((doc) {
        return doc.data() as Map<String, dynamic>;
      }).toList();
      
      // Get the full content details for each progress item
      List<Map<String, dynamic>> result = [];
      for (var progress in progressItems) {
        String contentType = progress['contentType'];
        String contentId = progress['contentId'];
        
        DocumentSnapshot contentDoc = await _firestore
            .collection(contentType)
            .doc(contentId)
            .get();
        
        if (contentDoc.exists) {
          Map<String, dynamic> data = contentDoc.data() as Map<String, dynamic>;
          data['progress'] = progress['progress'];
          data['chapter'] = progress['chapter'];
          data['id'] = contentDoc.id;
          result.add(data);
        }
      }
      
      return result;
    } catch (e) {
      print('Error getting reading progress: $e');
      return [];
    }
  }

  // Upload content (story, light novel, comic)
  Future<String?> uploadContent({
    required String contentType,
    required String title,
    required String authorId,
    required String authorName,
    required String description,
    required List<String> genres,
    required String content,
    File? coverImage,
  }) async {
    try {
      // Upload cover image if provided
      String coverUrl = '';
      if (coverImage != null) {
        String coverPath = 'covers/${_uuid.v4()}.jpg';
        await _storage.ref(coverPath).putFile(coverImage);
        coverUrl = await _storage.ref(coverPath).getDownloadURL();
      }
      
      // Create the content document
      DocumentReference docRef = await _firestore.collection(contentType).add({
        'title': title,
        'authorId': authorId,
        'authorName': authorName,
        'description': description,
        'genres': genres,
        'content': content,
        'coverUrl': coverUrl,
        'reads': 0,
        'likes': 0,
        'publishedDate': FieldValue.serverTimestamp(),
      });
      
      return docRef.id;
    } catch (e) {
      print('Error uploading content: $e');
      return null;
    }
  }

  // Update reading progress
  Future<void> updateReadingProgress({
    required String userId,
    required String contentId,
    required String contentType,
    required double progress,
    required String chapter,
  }) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('readingProgress')
          .doc(contentId)
          .set({
        'contentId': contentId,
        'contentType': contentType,
        'progress': progress,
        'chapter': chapter,
        'lastReadTimestamp': FieldValue.serverTimestamp(),
      });
      
      // Increment the read counter for the content
      await _firestore.collection(contentType).doc(contentId).update({
        'reads': FieldValue.increment(1),
      });
    } catch (e) {
      print('Error updating reading progress: $e');
    }
  }

  // Get content by genre
  Future<List<Map<String, dynamic>>> getContentByGenre(String genre) async {
    try {
      List<Map<String, dynamic>> result = [];
      
      // Query all content types with the specified genre
      for (String type in ['stories', 'lightNovels', 'comics']) {
        QuerySnapshot snapshot = await _firestore
            .collection(type)
            .where('genres', arrayContains: genre)
            .limit(10)
            .get();
        
        for (var doc in snapshot.docs) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          data['id'] = doc.id;
          data['type'] = type;
          result.add(data);
        }
      }
      
      return result;
    } catch (e) {
      print('Error getting content by genre: $e');
      return [];
    }
  }
}
