import 'dart:convert';
import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class CloudinaryService {
  static const String cloudName = "dgd2y8gzq";
  static const String uploadPreset = "absen_selfie";

  static Future<File?> compressTo200KB(File file) async {
    final dir = await getTemporaryDirectory();
    final targetPath = "${dir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg";

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

      if (size <= 200 * 1024) {
        return result;
      }

      quality -= 10;
      if (quality < 20) break;
    }

    return result;
  }

  static Future<String> uploadImage(File file) async {
    final url = Uri.parse("https://api.cloudinary.com/v1_1/$cloudName/image/upload");

    var request = http.MultipartRequest("POST", url);
    request.fields["upload_preset"] = uploadPreset;
    request.files.add(await http.MultipartFile.fromPath("file", file.path));

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode != 200) {
      throw Exception("Upload gagal: $responseBody");
    }

    final jsonData = json.decode(responseBody);
    return jsonData["secure_url"];
  }
}
