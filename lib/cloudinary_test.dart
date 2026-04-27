import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CloudinaryTestPage extends StatefulWidget {
  const CloudinaryTestPage({super.key});

  @override
  State<CloudinaryTestPage> createState() => _CloudinaryTestPageState();
}

class _CloudinaryTestPageState extends State<CloudinaryTestPage> {
  File? _image;
  String? _uploadedUrl;
  bool _loading = false;

  // GANTI sesuai milik kamu
final String cloudName = "dgd2y8gzq";
final String uploadPreset = "absen_selfie";


  Future<File?> compressTo200KB(File file) async {
    final dir = await getTemporaryDirectory();
    final targetPath = "${dir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg";

    // Compress step (quality akan disesuaikan)
    int quality = 80;
    File? result;

    for (int i = 0; i < 6; i++) {
      final compressed = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: quality,
        format: CompressFormat.jpeg,
      );

      if (compressed == null) return null;

      result = File(compressed.path);
      final size = await result.length();

      if (size <= 200 * 1024) { // <= 200KB
        return result;
      }

      quality -= 10; // turunkan kualitas kalau masih besar
      if (quality < 20) break;
    }

    return result; // return terbaik yang didapat
  }

  Future<void> pickAndUpload() async {
    setState(() {
      _loading = true;
      _uploadedUrl = null;
    });

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 100);

      if (picked == null) {
        setState(() => _loading = false);
        return;
      }

      File original = File(picked.path);
      File? compressed = await compressTo200KB(original);
      if (compressed == null) throw Exception("Gagal compress");

      setState(() {
        _image = compressed;
      });

      final url = Uri.parse("https://api.cloudinary.com/v1_1/$cloudName/image/upload");

      var request = http.MultipartRequest("POST", url);
      request.fields["upload_preset"] = uploadPreset;
      request.files.add(await http.MultipartFile.fromPath("file", compressed.path));

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final jsonData = json.decode(responseBody);

      if (response.statusCode != 200) {
        throw Exception("Upload gagal: $responseBody");
      }

      setState(() {
        _uploadedUrl = jsonData["secure_url"];
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Cloudinary Upload Test")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: _loading ? null : pickAndUpload,
              child: Text(_loading ? "Uploading..." : "Ambil Foto & Upload"),
            ),
            const SizedBox(height: 16),
            if (_image != null) Image.file(_image!, height: 200),
            const SizedBox(height: 16),
            if (_uploadedUrl != null)
              SelectableText("✅ Uploaded URL:\n$_uploadedUrl"),
          ],
        ),
      ),
    );
  }
}
