import 'package:flutter/material.dart';
import 'package:flutter_web_auth/flutter_web_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:river_agoravai/api.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  await dotenv.load();

  final clientId = dotenv.env['SPOTIFY_CLIENT_ID'];
  final clientSecret = dotenv.env['SPOTIFY_CLIENT_SECRET'];

  runApp(MyApp(cid: clientId!, secret: clientSecret!));
}

class MyApp extends StatelessWidget {
  final String cid;
  final String secret;

  const MyApp({super.key, required this.cid, required this.secret});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    const storage = FlutterSecureStorage();
    return MaterialApp(
      title: 'RIVER MVP',
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: const Color.fromARGB(255, 0, 0, 0)),
        useMaterial3: true,
      ),
      home: MVP(
        title: 'RIVER',
        storage: storage,
        cid: cid,
        secret: secret,
      ),
    );
  }
}

class MVP extends StatefulWidget {
  final String title;
  final FlutterSecureStorage? storage;
  final String cid;
  final String secret;

  const MVP(
      {super.key,
      required this.title,
      this.storage,
      required this.cid,
      required this.secret});

  @override
  State<MVP> createState() => _MVPState();
}

class _MVPState extends State<MVP> {
  late List<TextEditingController> controllers = [TextEditingController()];
  final TextEditingController npl = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  var link = "";
  var _loading = false;
  var _clicked = false;
  List<Map<dynamic, dynamic>> userPlaylists = [];

  late int playlists = 1;

  void addInputField() {
    if (playlists < 10) {
      setState(() {
        playlists += 1;
        controllers.add(TextEditingController());
      });
    }
  }

  void removeInputField() {
    setState(() {
      playlists -= 1;
      controllers.removeLast();
    });
  }

  void userAuth() async {
    const String redirectUri = 'river://spotify-auth-callback';

    String spotifyAuthUrl =
        'https://accounts.spotify.com/authorize?response_type=code&client_id=${widget.cid}&scope=playlist-modify-private&redirect_uri=$redirectUri';

    try {
      final result = await FlutterWebAuth.authenticate(
        url: spotifyAuthUrl,
        callbackUrlScheme: 'river',
      );

      // Check for and extract the authorization code from the result.
      final code = result.split("code=")[1];
      debugPrint(code);

      final tokens = await requestSpotifyTokens(code, redirectUri);
      if (tokens != null) {
        final accessToken = tokens['access_token'];
        final refreshToken = tokens['refresh_token'];
        await widget.storage!.write(key: "spAccessToken", value: accessToken);
        await widget.storage!.write(key: "spRefreshToken", value: refreshToken);

        const String userInfoEndpoint = 'https://api.spotify.com/v1/me';

        final response = await http.get(
          Uri.parse(userInfoEndpoint),
          headers: {
            'Authorization': 'Bearer $accessToken',
          },
        );
        debugPrint(response.body);
        final parsedResponse = jsonDecode(response.body);
        final userID = parsedResponse["id"] ?? "null";
        widget.storage!.write(key: "userID", value: userID);

        debugPrint(userID + tokens.toString());
      }
    } catch (e) {
      debugPrint('Authentication error: $e');
    }
  }

  Future<Map<String, dynamic>?> requestSpotifyTokens(
      String authorizationCode, String redirectUri) async {
    const tokenUrl = 'https://accounts.spotify.com/api/token';

    debugPrint(
        base64Encode(utf8.encode('${widget.cid}:${widget.secret}')).toString());

    final response = await http.post(
      Uri.parse(tokenUrl),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization':
            'Basic ${base64Encode(utf8.encode('${widget.cid}:${widget.secret}'))}',
      },
      body: {
        'grant_type': 'authorization_code',
        'code': authorizationCode,
        'redirect_uri': redirectUri,
      },
    );

    if (response.statusCode == 200) {
      // Parse the JSON response to get the access token and refresh token.
      final Map<String, dynamic> data = json.decode(response.body);
      return data;
    } else {
      // Handle token request error.
      debugPrint('Token request failed. Status code: ${response.statusCode}');
      return null;
    }
  }

  Future<void> _getPls() async {
    final userID = await widget.storage!.read(key: "userID");
    final accessToken = await widget.storage!.read(key: "spAccessToken");

    const String playlistEndpoint =
        'https://api.spotify.com/v1/users/{user_id}/playlists';

    final postPlaylistResponse = await http.get(
      Uri.parse(
          "${playlistEndpoint.replaceFirst('{user_id}', '$userID')}?limit=25"), // Replace with the user's Spotify ID
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
    );

    debugPrint(postPlaylistResponse.body.toString());

    final parsedResponse = jsonDecode(postPlaylistResponse.body);
    final List<dynamic> items = parsedResponse["items"];

    items.forEach((item) {
      setState(() {
        userPlaylists.add({item["name"]: item["external_urls"]["spotify"]});
      });
    });
  }

  Future<String> _mix(List<String> playlists, int nsongs, String name) async {
    setState(() {
      link = "";
    });

    //treat playlists
    playlists.removeWhere((element) => element == "");

    final riverResponse = await RiverApi.getSongList(playlists, nsongs);
    final songlist = jsonDecode(riverResponse.body)["songlist"];
    final userID = await widget.storage!.read(key: "userID");
    final accessToken = await widget.storage!.read(key: "spAccessToken");

    try {
      const String playlistEndpoint =
          'https://api.spotify.com/v1/users/{user_id}/playlists';

      final postPlaylistResponse = await http.post(
        Uri.parse(playlistEndpoint.replaceFirst(
            '{user_id}', '$userID')), // Replace with the user's Spotify ID
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': name,
          'description': 'Playlist criada a partir do RIVER ©',
          'public': false,
        }),
      );

      if (postPlaylistResponse.statusCode == 201) {
        final playlistID = jsonDecode(postPlaylistResponse.body)["id"];
        final playlistURL =
            jsonDecode(postPlaylistResponse.body)["external_urls"]["spotify"];
        debugPrint('Playlist created successfully.');
        debugPrint(accessToken);
        final addPlaylistResponse =
            await RiverApi.addSongs(songlist, playlistID, accessToken!);
        if (addPlaylistResponse.statusCode == 200) {
          return playlistURL;
        }
      } else {
        debugPrint(
            'Failed to create the playlist. Status code: ${postPlaylistResponse.statusCode}');
        return "ERRO NA CRIAÇÃO DA PLAYLIST";
      }
    } catch (e) {
      debugPrint('Authentication error: $e');
      return "ERRO NA AUTENTICAÇÃO DO SPOTIFY";
    }
    return "ERRO";
  }

  @override
  void initState() {
    super.initState();
    userAuth();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [
            Colors.black,
            Color.fromARGB(255, 166, 166, 166),
          ], transform: GradientRotation(1.6))),
          height: MediaQuery.of(context).size.height,
          width: MediaQuery.of(context).size.width,
          child: SingleChildScrollView(
            child: Column(children: [
              const Text(
                "PLAYLIST MIXER",
                style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: ElevatedButton(
                  onPressed: _clicked ? () {} : () {
                    setState(() {
                      _clicked = true;
                    });
                    _getPls();
                    },
                  style: ButtonStyle(
                      backgroundColor: _clicked
                          ? const MaterialStatePropertyAll(Colors.grey)
                          : const MaterialStatePropertyAll(
                              Color.fromARGB(96, 76, 175, 79))),
                  child: const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 0.0, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Text(
                          "IMPORT PLAYLISTS FROM SPOTIFY  ",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                        ),
                        Icon(
                          Icons.arrow_circle_down_rounded,
                          color: Colors.white,
                        )
                      ],
                    ),
                  ),
                ),
              ),
              Column(
                children: List.generate(
                    userPlaylists.length,
                    (index) => TextButton(
                        onPressed: () {
                          setState(() {
                            controllers[playlists - 1].text =
                                userPlaylists[index].values.first;
                            userPlaylists.removeAt(index);
                          });
                          addInputField();
                        },
                        child: Text(userPlaylists[index].keys.first))),
              ),
              Column(
                  children: List.generate(
                      playlists,
                      (index) => Padding(
                            padding: const EdgeInsets.only(
                                top: 15, left: 30, right: 30),
                            child: TextField(
                              decoration: InputDecoration(
                                  label: Text("PLAYLIST #${index + 1}"),
                                  fillColor: Colors.white,
                                  filled: true,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(20))),
                              controller: controllers[index],
                            ),
                          ))),
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: addInputField,
                        style: const ButtonStyle(
                            fixedSize: MaterialStatePropertyAll(Size(50, 50)),
                            overlayColor: MaterialStatePropertyAll(Colors.grey),
                            backgroundColor:
                                MaterialStatePropertyAll(Colors.white),
                            shape: MaterialStatePropertyAll(
                              CircleBorder(
                                  eccentricity: 0, side: BorderSide.none),
                            )),
                        child: const Text(
                          "+",
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.black),
                        ),
                      ),
                      const SizedBox(
                        width: 20,
                      ),
                      ElevatedButton(
                        onPressed: (playlists > 1) ? removeInputField : () {},
                        style: const ButtonStyle(
                            elevation: MaterialStatePropertyAll(10),
                            backgroundColor:
                                MaterialStatePropertyAll(Colors.white),
                            fixedSize: MaterialStatePropertyAll(Size(50, 50)),
                            overlayColor: MaterialStatePropertyAll(Colors.grey),
                            shape: MaterialStatePropertyAll(
                              CircleBorder(
                                  eccentricity: 0, side: BorderSide.none),
                            )),
                        child: const Text(
                          "-",
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 15, left: 60, right: 60),
                child: TextField(
                  controller: npl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      hintText: "NÚMERO DE MÚSICAS",
                      fillColor: Colors.white,
                      filled: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20))),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 15, left: 60, right: 60),
                child: TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                      hintText: "NOME DA PLAYLIST",
                      fillColor: Colors.white,
                      filled: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20))),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: ElevatedButton(
                  onPressed: () async {
                    setState(() {
                      _loading = true;
                    });
                    final List<String> playlists = [];
                    controllers.forEach(
                      (element) => playlists.add(element.text.toString()),
                    );
                    final String url = await _mix(
                        playlists, int.parse(npl.text), nameController.text);
                    setState(() {
                      _loading = false;
                      link = url;
                    });
                  },
                  style: const ButtonStyle(
                      backgroundColor: MaterialStatePropertyAll(
                          Color.fromARGB(96, 76, 175, 79))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30.0, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        const Text(
                          "MIX  ",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 30),
                        ),
                        Image.asset(
                          "assets/images/riverNoText.png",
                          scale: 12,
                        )
                      ],
                    ),
                  ),
                ),
              ),
              _loading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : const SizedBox(
                      height: 0,
                    ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: TextButton(
                  onPressed: () {
                    launchUrl(Uri.parse(link));
                  },
                  child: Text(
                    link,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        decoration: TextDecoration.underline),
                  ),
                ),
              )
            ]),
          ),
        ),
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: AppBar(
            title: Image.asset(
              "assets/images/river.png",
              scale: 13,
            ),
            bottomOpacity: 0,
            backgroundColor: Colors.black,
          ),
        ));
  }
}
