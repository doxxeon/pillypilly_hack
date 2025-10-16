import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class PrescriptionUploadPage extends StatefulWidget {
  const PrescriptionUploadPage({Key? key}) : super(key: key);

  @override
  State<PrescriptionUploadPage> createState() => _PrescriptionUploadPageState();
}

class _PrescriptionUploadPageState extends State<PrescriptionUploadPage> {
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImageFromGallery() async {
    final XFile? pickedFile =
        await _picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  void _uploadPrescription() {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 이미지를 선택해주세요.')),
      );
      return;
    }

    // TODO: 실제 서버 업로드 로직 추가
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('처방전이 업로드되었습니다 ✅')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('처방전 업로드'),
        backgroundColor: Colors.teal,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickImageFromGallery,
              child: Container(
                height: 250,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal, width: 2),
                ),
                child: _selectedImage == null
                    ? const Center(
                        child: Text(
                          '갤러리에서 처방전 선택하기',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          _selectedImage!,
                          fit: BoxFit.cover,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _uploadPrescription,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.cloud_upload),
              label: const Text(
                '업로드하기',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}