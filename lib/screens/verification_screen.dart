import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class VerificationPage extends StatefulWidget {
  const VerificationPage({super.key});
  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  File? _image;
  bool _isUploading = false;
  final ImagePicker _picker = ImagePicker();

  Future<void> _takeSelfie() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
    );
    if (photo != null) {
      setState(() => _image = File(photo.path));
    }
  }

  Future<void> _submit() async {
    if (_image == null) return;
    setState(() => _isUploading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = jsonDecode(prefs.getString('user_data')!);
      
      // Upload image
      var request = http.MultipartRequest('POST', Uri.parse('http://72.61.170.181:5000/api/chat/upload'));
      request.files.add(await http.MultipartFile.fromPath('image', _image!.path));
      var res = await request.send();
      
      if (res.statusCode == 200) {
        var resBody = await http.Response.fromStream(res);
        var data = jsonDecode(resBody.body);
        String selfieUrl = data['imageUrl'];

        // Submit verification request
        final response = await http.post(
          Uri.parse('http://72.61.170.181:5000/api/user/verify-request'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'phone': user['phone'],
            'selfieUrl': selfieUrl
          })
        );

        if (response.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification submitted! Admin will review it.')));
            Navigator.pop(context);
          }
        }
      }
    } catch (e) {
      print(e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Submission failed')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: const Text('Get Verified')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(Icons.verified_user_rounded, size: 80, color: Colors.blueAccent),
            const SizedBox(height: 20),
            const Text('Verify your identity', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text(
              'Take a live selfie to get a Blue Tick on your profile. This helps users know you are real.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const Spacer(),
            if (_image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.file(_image!, height: 300, width: double.infinity, fit: BoxFit.cover),
              )
            else
              GestureDetector(
                onTap: _takeSelfie,
                child: Container(
                  height: 300,
                  width: double.infinity,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10, style: BorderStyle.solid)),
                  child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.camera_alt_rounded, color: Colors.white54, size: 50), SizedBox(height: 12), Text('Tap to take Selfie', style: TextStyle(color: Colors.white54))]),
                ),
              ),
            const Spacer(),
            if (_isUploading)
              const CircularProgressIndicator(color: Colors.orangeAccent)
            else
              ElevatedButton(
                onPressed: _image == null ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  disabledBackgroundColor: Colors.white10
                ),
                child: const Text('Submit for Review', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
