import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

class RiverApi {
  static Future<http.Response> getSongList(
      List<String> playlists, int nsongs) async {
    const baseUrl = "https://riverbackend.pythonanywhere.com";
    final response = await http.post(Uri.parse("$baseUrl/mix"),
        body: jsonEncode({"pls": playlists, "ns": nsongs}),
        headers: {'Content-Type': 'application/json'});
    debugPrint(response.body.toString());
    return response;
  }
  
  static Future<http.Response> addSongs(
      List<dynamic> songlist, String playlistID, String accessToken) async {
    const baseUrl = "https://riverbackend.pythonanywhere.com";
    final response = await http.post(Uri.parse("$baseUrl/addSongs"),
        body: jsonEncode({"songlist": songlist, "playlistID": playlistID,"accessToken":accessToken}),
        headers: {'Content-Type': 'application/json'});
    debugPrint(response.body.toString());
    return response;
  }
}
