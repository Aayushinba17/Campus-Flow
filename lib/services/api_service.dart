import 'package:http/http.dart' as http;
import 'dart:convert';

class ApiService {
  // Replace with your EC2 IP once deployed
  static const String baseUrl = 'http://YOUR_EC2_IP:8000/api';

  static Future<Map<String, dynamic>> getDigest(List<Map> notifications) async {
    final response = await http.post(
      Uri.parse('$baseUrl/digest'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'notifications': notifications}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> chat(String message, Map context) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'message': message, 'context': context}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> parseSchedule(String text) async {
    final response = await http.post(
      Uri.parse('$baseUrl/schedule/parse'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );
    return jsonDecode(response.body);
  }
}