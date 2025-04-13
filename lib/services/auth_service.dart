import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  User? _user;

  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  User? get currentUser => _user;

  Future<void> initializeUser() async {
    _user = _auth.currentUser;
    // Removed notifyListeners() here to prevent build issues
  }

  Future<User?> signInWithEmail(String email, String password) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      _user = result.user;
      notifyListeners();
      return _user;
    } on FirebaseAuthException catch (e) {
      debugPrint('Error signing in: ${e.code} - ${e.message}');
      rethrow; // Better to let the UI handle specific errors
    }
  }

  Future<User?> registerWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      _user = result.user;
      await _user?.updateDisplayName(displayName);
      await _user?.reload();
      _user = _auth.currentUser; // Refresh user data
      await _firestore.collection('users').doc(_user?.uid).set({
        'displayName': displayName,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
        'bio': '',
        'profileImageUrl': '',
        'uid': _user?.uid, // Important for queries
      });
      notifyListeners();
      return _user;
    } on FirebaseAuthException catch (e) {
      debugPrint('Error registering: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _user = null;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      return doc.data();
    } catch (e) {
      debugPrint('Error getting user profile: $e');
      return null;
    }
  }

  Future<bool> updateUserProfile({
    required String userId,
    String? displayName,
    String? bio,
    File? profileImage,
  }) async {
    try {
      final updateData = <String, dynamic>{};
      if (displayName != null) {
        updateData['displayName'] = displayName;
        await _user?.updateDisplayName(displayName);
      }
      if (bio != null) {
        updateData['bio'] = bio;
      }
      if (profileImage != null) {
        final imagePath =
            'profile_images/$userId-${DateTime.now().millisecondsSinceEpoch}.jpg';
        final ref = FirebaseStorage.instance.ref(imagePath);
        await ref.putFile(profileImage);
        final imageUrl = await ref.getDownloadURL();
        updateData['profileImageUrl'] = imageUrl;
      }
      if (updateData.isNotEmpty) {
        await _firestore.collection('users').doc(userId).update(updateData);
        await _user?.reload();
        _user = _auth.currentUser;
        notifyListeners();
      }
      return true;
    } catch (e) {
      debugPrint('Error updating profile: $e');
      return false;
    }
  }
}
