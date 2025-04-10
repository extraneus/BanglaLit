import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  User? _user;

  User? get currentUser => _user;

  Future<void> initializeUser() async {
    _user = _auth.currentUser;
    notifyListeners();
  }

  // Sign in with email and password
  Future<User?> signInWithEmail(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      _user = result.user;
      notifyListeners();
      return _user;
    } catch (e) {
      print('Error signing in: $e');
      return null;
    }
  }

  // Register with email and password
  Future<User?> registerWithEmail(
    String email,
    String password,
    String displayName,
  ) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      _user = result.user;

      // Update display name
      await _user!.updateDisplayName(displayName);

      // Create user profile in Firestore
      await _firestore.collection('users').doc(_user!.uid).set({
        'displayName': displayName,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
        'bio': '',
        'profileImageUrl': '',
      });

      notifyListeners();
      return _user;
    } catch (e) {
      print('Error registering: $e');
      return null;
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
    _user = null;
    notifyListeners();
  }

  // Get user profile
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      DocumentSnapshot doc =
          await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        return data;
      }
      return null;
    } catch (e) {
      print('Error getting user profile: $e');
      return null;
    }
  }

  // Update user profile
  Future<bool> updateUserProfile({
    required String userId,
    String? displayName,
    String? bio,
    File? profileImage,
  }) async {
    try {
      Map<String, dynamic> updateData = {};

      if (displayName != null) {
        updateData['displayName'] = displayName;
        await _user?.updateDisplayName(displayName);
      }

      if (bio != null) {
        updateData['bio'] = bio;
      }

      if (profileImage != null) {
        String imagePath = 'profile_images/$userId.jpg';
        await FirebaseStorage.instance.ref(imagePath).putFile(profileImage);
        String imageUrl =
            await FirebaseStorage.instance.ref(imagePath).getDownloadURL();
        updateData['profileImageUrl'] = imageUrl;
      }

      if (updateData.isNotEmpty) {
        await _firestore.collection('users').doc(userId).update(updateData);
      }

      notifyListeners();
      return true;
    } catch (e) {
      print('Error updating profile: $e');
      return false;
    }
  }
}
