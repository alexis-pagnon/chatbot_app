import 'dart:convert';
import 'dart:io';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../model/conversation_subject.dart';
import '../model/conversation.dart';
import '../variables.dart';

/* ----------------------------------
  Projet 4A : Chatbot App
  Date : 11/06/2025
  discussion_page.dart
---------------------------------- */

/// Page de discussion
/// Cette page permet à l'utilisateur de discuter avec le chatbot.
class DiscussionPage extends StatefulWidget {
  DiscussionPage({super.key, required this.titre, required this.conversation});
  DiscussionPage.empty({super.key}) : titre = "", conversation = null;

  final String titre; // Titre de la discussion
  Conversation? conversation;

  @override
  State<DiscussionPage> createState() => _DiscussionPageState();
}

class _DiscussionPageState extends State<DiscussionPage> {
  // Variables
  GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>(); // Clé pour le Scaffold (utile pour gérer le Drawer)
  TextEditingController inputController = TextEditingController(); // Contrôleur pour le champ de saisie de texte
  late final ScrollController _scrollController; // Contrôleur pour le défilement de la liste des messages
  bool researchMode = false; // true = recherche web, false = recherche locale
  List<File> files = []; // Liste des fichiers sélectionnés
  bool isLoading = false; // Indique si une requête est en cours (animation)

  Future<List<ConversationSubject>>? drawerData; // Données pour le Drawer (liste des sujets de conversation)

  // Liste des émotions disponibles pour les messages du bot
  final listeEmotions = ["naturel","amoureux","colère","détective","effrayant","endormi","fatigué","heureux","inquiet","intello","pensif","professeur","soulagé","surpris","triste"];

  // Instance de SpeechToText pour la reconnaissance vocale
  final SpeechToText _speechToText = SpeechToText();
  bool isListeningMic = false; // Indique si le microphone est en écoute
  bool _speechEnabled = false; // Indique si la reconnaissance vocale est activée
  bool _isListening = false; // Indique si la reconnaissance vocale est en cours
  String _currentText = ""; // Texte actuel saisi dans le champ de saisie (pour ajouter le texte reconnu à la suite de ce qui est déjà écrit)

  // Initialisation de l'utilisateur
  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    // Scroll to the bottom after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });

    if (widget.conversation != null) {
      launchConversation(); // Charge la conversation (sauf si c'est une nouvelle conversation)
    }

    // Charge le SpeechToText si l'application est sur Android
    if(Platform.isAndroid) {
      _initSpeech();
    }
  }


  /// Fonction pour descendre en bas de la liste des messages
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });
    }
  }

  // ---------------------------------- Speech-to-text ----------------------------------

  /// Initialise le SpeechToText
  Future<void> _initSpeech() async {
    _speechEnabled = await _speechToText.initialize(
    );
    setState(() {});
  }

  /// Démarre ou arrête l'écoute du microphone
  void _startListening() async {
    await _speechToText.listen(
      onResult: _onSpeechResult,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
      ),
    );
    setState(() => _isListening = true);
  }

  /// Arrête l'écoute du microphone
  void _stopListening() async {
    await _speechToText.stop();
    setState(() => _isListening = false);
  }

  /// Fonction appelée lorsque le résultat de la reconnaissance vocale est disponible
  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) return; // Vérifie si le widget est toujours monté
    //inputController.text = result.recognizedWords;
    inputController.text = "$_currentText ${result.recognizedWords}";
  }

  // ---------------------------------- Fonctions pour l'API ----------------------------------

  /// Crée un client HTTP sécurisé avec le certificat CA
  Future<HttpClient> createSecureHttpClient() async {
    final context = SecurityContext.defaultContext;
    final ByteData certData = await rootBundle.load('assets/certs/myCA.pem');
    context.setTrustedCertificatesBytes(certData.buffer.asUint8List());
    return HttpClient(context: context);
  }

  /// Supprime une discussion
  void removeDiscussion(String id) async {
    // Prépare l'URL pour la requête de suppression
    final uri = Uri.parse('$urlPrefix/delete_conversation/$id');
    // Ajout du bearer token pour l'authentification
    final request = http.MultipartRequest('POST', uri)..headers['Authorization'] = 'Bearer ${user.accessToken}';

    try {
      // Envoie la requête de suppression
      final response = await request.send();

      if (response.statusCode == 200) {
        //print("La suppression a réussie");
        // Si la suppression réussit, on recharge les sujets
        loadSubjects().then((sujets) {
          // Met à jour les données du Drawer avec les nouveaux sujets
          drawerData = Future.value(sujets);
          if (id == widget.conversation?.id) {
            // Si la conversation supprimée est celle en cours, on redirige vers une nouvelle discussion
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => DiscussionPage(titre: "", conversation: null)));
          } else {
            setState(() {});
          }
        });
      } else {
        //print("Erreur lors de la suppression de la conversation : ${response.statusCode}");
      }
    } catch (e) {
      // En cas d'erreur, nous n'avons rien a traité côté client
      //print("Exception pendant la récupération : $e");
    }
  }

  /// Lance la récupération de la conversation
  void launchConversation() async {
    // Charge un objet Conversation
    widget.conversation = Conversation(id: widget.conversation!.id, title: widget.titre, messages: []);

    // Prépare l'URL pour la requête de récupération de la conversation
    final uri = Uri.parse('$urlPrefix/chat/${widget.conversation!.id}');
    final request = http.MultipartRequest('GET', uri)..headers['Authorization'] = 'Bearer ${user.accessToken}';

    try {
      // Envoie la requête pour récupérer la conversation
      final response = await request.send();

      if (response.statusCode == 200) {
        //print("Réception de la conversation réussie");

        // Lit le corps de la réponse et le décode en JSON
        final responseBody = await response.stream.bytesToString();
        final json = jsonDecode(responseBody);
        List<List<String>> messages = [];
        // Parcourt les messages et les ajoute à la liste
        for (var item in json) {
          final role = item["role"].toString();
          final message = item["content"].toString();
          messages.add([role, message, "naturel"]);
        }

        // Ajoute ces messages à la conversation
        widget.conversation?.messages.addAll(messages);

        setState(() {});
        _scrollToBottom();
      } else {
        // En cas d'erreur, nous n'avons rien a traité côté client
        //print("Erreur lors de la récupération de la conversation : ${response.statusCode}");
      }
    } catch (e) {
      // En cas d'exception, nous n'avons rien a traité côté client
      //print("Exception pendant la récupération : $e");
    }
  }

  /// Déconnexion de l'utilisateur
  void logout() async {
    // Préparer l'URL pour la requête de déconnexion
    final uri = Uri.parse('$urlPrefix/logout');
    final request = http.MultipartRequest('POST', uri)..headers['Authorization'] = 'Bearer ${user.accessToken}';
    try {
      final response = await request.send();
      if (response.statusCode == 200) {
        //print("Déconnexion réussie");
      } else {
        //print("Erreur lors de la déconnexion : ${response.statusCode}");
      }
    } catch (e) {
      //print("Exception pendant la récupération : $e");
    }
    // Réinitialiser l'utilisateur
    user.clear();
    // Retourne à la page de connexion
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Charge les sujets de conversation depuis l'API
  Future<List<ConversationSubject>> loadSubjects() async {
    // Crée un client HTTP sécurisé
    final client = await createSecureHttpClient();
    final url = Uri.parse('$urlPrefix/conversations');

    try {
      // Prépare la requête GET pour récupérer les sujets de conversation
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.contentTypeHeader, "application/json");
      // Ajout du token d'authentification
      request.headers.set(HttpHeaders.authorizationHeader, "Bearer ${user.accessToken}");

      final response = await request.close();

      if (response.statusCode == 200) {
        //print("Récupération des sujets réussie");

        final responseBody = await response.transform(utf8.decoder).join();
        final List<dynamic> data = jsonDecode(responseBody);
        // Convertit la liste JSON en liste d'objets ConversationSubject
        List<ConversationSubject> listeSujets = data.map((json) => ConversationSubject.fromJson(json)).toList();
        // Trie la liste des sujets par date de dernière mise à jour
        listeSujets.sort(
          (a, b) => b.lastUpdate.compareTo(a.lastUpdate), // Tri par date de dernière mise à jour, du plus récent au plus ancien
        );
        return listeSujets;
      } else {
        //print("Erreur lors de la récupération des sujets : ${response.statusCode}");
        // En cas d'erreur, nous la faisons remonter
        throw Exception("Erreur lors de la récupération des sujets : ${response.statusCode}");
      }
    } catch (e) {
      //print("Exception pendant la récupération : $e");
      // En cas d'exception, nous la faisons remonter
      throw Exception("Erreur lors de la récupération des sujets.");
    }
  }

  /// Fonction appelée lorsque le Drawer est ouvert
  void _onDrawerOpened() {
    setState(() {
      drawerData = loadSubjects();
    });
  }

  /// Ouvre ou ferme le menu latéral (Drawer)
  void openMenu() {
    scaffoldKey.currentState?.openDrawer();
  }

  /// Ferme le menu latéral (Drawer)
  void closeMenu() {
    scaffoldKey.currentState?.closeDrawer();
  }

  /// Envoie le message saisi par l'utilisateur
  void send() async {
    setState(() {
      if (widget.conversation == null) {
        // Si la conversation est nulle, on crée une nouvelle conversation
        widget.conversation = Conversation(
          id: "-1",
          title: "",
          messages: [
            ["user", inputController.text, ""],
          ],
        );
      } else {
        // Sinon, on ajoute le message à la conversation existante
        widget.conversation?.addMessage("user", inputController.text, "");
      }
      isLoading = true;
      widget.conversation?.messages.add(["system", "loading", ""]); // message temporaire pour l'animation
    });
    _scrollToBottom();

    // Prépare la requête pour envoyer le message
    final uri = Uri.parse('$urlPrefix/send');

    final request =
        http.MultipartRequest('POST', uri)
          ..fields['content'] = inputController.text
          ..fields['use_web'] = researchMode.toString()
          ..fields['conversation_id'] = (widget.conversation?.id).toString()
          ..headers['Authorization'] = 'Bearer ${user.accessToken}';

    // Ajoute les fichiers à la requête s'il y en a
    for (var file in files) {
      final fileStream = http.ByteStream(file.openRead());
      final fileLength = await file.length();
      final multipartFile = http.MultipartFile('files', fileStream, fileLength, filename: p.basename(file.path));
      request.files.add(multipartFile);
    }

    // Reset le champ de saisie et la liste des fichiers
    inputController.clear();
    if (files.isNotEmpty) {
      files.clear();
    }

    try {
      // Envoie la requête
      final response = await request.send();

      if (response.statusCode == 200) {
        //print("Envoi de message réussi");

        final responseBody = await response.stream.bytesToString();
        final json = jsonDecode(responseBody);

        if(context.mounted) {
          final String conversationId = json['conversation_id'].toString();
          final String responseText = json['response'].toString();
          final String title = json['title'].toString();
          final String emotion = (json['emotion'] ?? 'naturel').toString().replaceAll("#", "");

          if (widget.conversation?.id == "-1") {
            // Si la conversation est nouvelle, on lui donne un ID reçu
            widget.conversation?.id = conversationId;
          }

          setState(() {
            isLoading = false;
            // Remplace le "loading" par la vraie réponse
            final firstIndex = widget.conversation!.messages.indexWhere((msg) => msg[0] == "system" && msg[1] == "loading");
            if (firstIndex != -1) {
              widget.conversation!.messages[firstIndex] = ["assistant", responseText, emotion];
              if (widget.conversation?.title == "") {
                // Si le titre de la conversation est vide, on le met à jour
                widget.conversation?.title = title;
              }
            }
          });
        }

      } else {
        // Message d'erreur
        //print("Erreur lors de la récupération des messages : ${response.statusCode}");
        if(context.mounted) {
          setState(() {
            isLoading = false;
            // Remplace le "loading" par un message d'erreur
            final firstIndex = widget.conversation!.messages.indexWhere((msg) => msg[0] == "system" && msg[1] == "loading");
            if (firstIndex != -1) {
              widget.conversation!.messages[firstIndex] = ["assistant", "Erreur lors de la récupération des messages", ""];
            }
          });
        }

      }
    } catch (e) {
      // Exception : message d'erreur
      //print("Exception pendant la récupération : $e");
      if(context.mounted) {
        setState(() {
          isLoading = false;
          // Remplace le "loading" par un message d'erreur
          final lastIndex = widget.conversation!.messages.lastIndexWhere((msg) => msg[0] == "system" && msg[1] == "loading");
          if (lastIndex != -1) {
            widget.conversation!.messages[lastIndex] = ["assistant", "Erreur lors de la récupération des messages", ""];
          }
        });
      }
    }
  }

  /// Active ou désactive le mode de recherche avancée
  void switchResearchMode() {
    // Si il y a des fichiers, on ne peut pas activer la recherche web
    if(!researchMode && files.isNotEmpty) {
      // Si on est en mode recherche web et qu'il y a des fichiers, on affiche un message d'avertissement
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AutoSizeText(
            "Veuillez supprimer les fichiers avant d'activer la recherche en ligne.",
            style: const TextStyle(color: Colors.white, fontSize: 20),
            maxLines: 1,
            maxFontSize: 20,
            minFontSize: 8,
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      researchMode = !researchMode;
    });

    // Cacher le SnackBar précédent s'il est visible
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    // Afficher le SnackBar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(researchMode ? Icons.check_circle_outline : Icons.highlight_off, color: researchMode ? Colors.white : Colors.white, size: 30),
            const SizedBox(width: 20),
            SizedBox(
              width: MediaQuery.of(context).size.width - 100,
              child: AutoSizeText(
                researchMode ? "Recherche avancée via Internet activée" : "Recherche avancée via Internet désactivée",
                style: const TextStyle(color: Colors.white, fontSize: 20),
                maxLines: 1,
                maxFontSize: 20,
                minFontSize: 8,
              ),
            ),
          ],
        ),
        backgroundColor: researchMode ? Colors.green : Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Sélectionne des fichiers à envoyer
  Future<void> selectFiles() async {
    // Ouvre le sélecteur de fichiers
    FilePickerResult? result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['txt', 'pdf', 'markdown', 'md']);

    if (result != null) {
      List<File> selectedFiles = result.paths.map((path) => File(path!)).toList();
      for (File f in selectedFiles) {
        if (await f.length() > 24000000 || files.length >= 4 || files.any((file) => file.path == f.path)) {
          // Si le fichier est déjà dans la liste ou qu'on a déjà 4 fichiers, on ne l'ajoute pas
          continue;
        } else {
          files.add(f);
        }
      }

      // Si on est en mode recherche web, on affiche un message d'avertissement
      if (researchMode) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AutoSizeText(
              "Recherche web désactivée pour pouvoir envoyer des fichiers.",
              style: const TextStyle(color: Colors.white, fontSize: 20),
              maxLines: 1,
              maxFontSize: 20,
              minFontSize: 8,
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
        researchMode = false;
      }
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: const Color.fromRGBO(59, 59, 63, 1),
      // Gère l'ouverture et la fermeture du Drawer
      onDrawerChanged: (isOpened) {
        if (isOpened) _onDrawerOpened();
      },

      // Menu latéral (Drawer)
      drawer: Drawer(
      width: 300,
      backgroundColor: const Color.fromRGBO(70, 70, 70, 1),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Partie haute scrollable
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Image.asset("assets/logo.png", width: 128, height: 128),

                  // Bouton nouvelle discussion
                  RawMaterialButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => DiscussionPage.empty()),
                      );
                    },
                    child: Container(
                      width: 300,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(103, 103, 103, 1),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(width: 10),
                          Text("Nouvelle discussion", style: TextStyle(color: Colors.white, fontSize: 20)),
                          Expanded(child: SizedBox()),
                          Icon(Icons.add_circle_outline, color: Colors.white, size: 32),
                          SizedBox(width: 16),
                        ],
                      ),
                    ),
                  ),

                  // Liste des discussions
                  FutureBuilder<List<ConversationSubject>>(
                    future: drawerData,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: Padding(
                          padding: EdgeInsets.only(top:10),
                          child: CircularProgressIndicator(),
                        ));
                      } else if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text("${snapshot.error}",
                              style: const TextStyle(color: Colors.white, fontSize: 20),
                            ),
                          ),
                        );
                      } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Text("Aucun sujet trouvé.",
                              style: TextStyle(color: Colors.white, fontSize: 20),
                            ),
                          ),
                        );
                      }
                      // Données récupérées avec succès
                      final sujets = snapshot.data!;

                      return ListView.builder(
                        shrinkWrap: true, // important pour ListView dans Column
                        physics: const NeverScrollableScrollPhysics(), // évite conflits avec le SingleChildScrollView
                        itemCount: sujets.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: RawMaterialButton(
                              onPressed: () {
                                // Changement de la page de discussion
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DiscussionPage(
                                      titre: sujets[index].titre,
                                      conversation: Conversation(
                                        id: sujets[index].id,
                                        title: sujets[index].titre,
                                        messages: [],
                                      ),
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                width: 300,
                                height: 50,
                                decoration: BoxDecoration(color: const Color.fromRGBO(103, 103, 103, 1)),
                                child: Row(
                                  children: [
                                    const SizedBox(width: 10),
                                    SizedBox(
                                      width: 230,
                                      child: AutoSizeText(
                                        sujets[index].titre,
                                        style: const TextStyle(color: Colors.white, fontSize: 20),
                                        maxLines: 1,
                                        maxFontSize: 20,
                                        minFontSize: 8,
                                      ),
                                    ),
                                    const Expanded(child: SizedBox()),
                                    IconButton(
                                      onPressed: () {
                                        removeDiscussion(sujets[index].id);
                                      },
                                      icon: const Icon(Icons.delete, color: Colors.white, size: 32),
                                    ),
                                    const SizedBox(width: 10),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Partie basse avec le nom d'utilisateur
          Container(
            width: 300,
            height: 50,
            decoration: const BoxDecoration(color: Color.fromRGBO(103, 103, 103, 1)),
            child: Center(
              child: Text(
                user.username,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    ),


    // Page de discussion
      body: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Barre en haut
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(onPressed: openMenu, icon: Icon(Icons.menu, color: Colors.white, size: 50)),

              const Expanded(child: SizedBox()),

              SizedBox(
                width: MediaQuery.of(context).size.width - 150,
                height: 50,
                child: Center(
                  child: AutoSizeText(
                    widget.conversation == null ? "" : widget.conversation!.title,
                    maxLines: 1,
                    maxFontSize: 40,
                    minFontSize: 8,
                    style: const TextStyle(color: Colors.white, fontSize: 40),
                  ),
                ),
              ),

              const Expanded(child: SizedBox()),
              // Bouton de déconnexion
              IconButton(onPressed: logout, icon: Icon(Icons.logout, color: Colors.white, size: 50)),
            ],
          ),

          // Contenu de la discussion
          if (widget.conversation == null) const Expanded(child: SizedBox()),

          if (widget.conversation == null)
            const Center(child: Text("Comment puis-je vous aider ?", style: TextStyle(color: Colors.white, fontSize: 32), textAlign: TextAlign.center))
          else // Liste des messages
            Expanded(
              child: SizedBox(
                width: MediaQuery.of(context).size.width,
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: widget.conversation?.messages.length,
                  itemBuilder: (context, index) {
                    if (widget.conversation?.messages[index][0] == "file") {
                      return SizedBox.shrink();
                    }
                    // Vérifie si le message est de l'utilisateur ou du bot
                    final isUser = widget.conversation?.messages[index][0] == "user";
                    final isBot = widget.conversation?.messages[index][0] == "assistant";
                    final message = widget.conversation?.messages[index][1];
                    // Vérifie l'émotion
                    String emotion = "";
                    if(widget.conversation?.messages[index].length == 3) {
                      emotion = widget.conversation?.messages[index][2] ?? "naturel";
                    }
                    else {
                      emotion = "naturel";
                    }

                    final isLoadingMessage = message == "loading";

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Bot avec émotion connue
                        if (isBot && listeEmotions.contains(emotion))
                          Padding(
                            padding: const EdgeInsets.only(left: 8, top: 8),
                            child: Image.asset('assets/images/$emotion.png', width: 32),
                          ),
                        // Bot avec émotion inconnue --> image naturelle
                        if(isBot && !listeEmotions.contains(emotion))
                          Padding(
                            padding: const EdgeInsets.only(left: 8, top: 8),
                            child: Image.asset('assets/images/naturel.png', width: 32),
                          ),

                        // Messages
                        Expanded(
                          child: Align(
                            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                              padding: const EdgeInsets.all(10),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                              decoration: BoxDecoration(color: const Color.fromRGBO(85, 85, 85, 1), borderRadius: BorderRadius.circular(15)),
                              child:
                                  isLoadingMessage
                                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      :
                                  // Message traité comme du markdown
                                  MarkdownBody(
                                        data: message!,
                                        selectable: true,
                                        styleSheet: MarkdownStyleSheet(
                                            p: const TextStyle(color: Colors.white, fontSize: 14),
                                            code: const TextStyle(color: Colors.white, fontSize: 14),
                                            blockquote: const TextStyle(color: Colors.white, fontSize: 14, fontStyle: FontStyle.italic),
                                            h1: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                                            h2: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                                            h3: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                            h4: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                            h5: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                            h6: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                            a: const TextStyle(color: Colors.blue, fontSize: 14, decoration: TextDecoration.underline),
                                            strong: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                            em: const TextStyle(color: Colors.white, fontSize: 14, fontStyle: FontStyle.italic),
                                            del: const TextStyle(color: Colors.white, fontSize: 14, decoration: TextDecoration.lineThrough),
                                            blockquoteDecoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            codeblockDecoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            listBullet: const TextStyle(color: Colors.white, fontSize: 14),
                                        ),
                                      ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

          if (widget.conversation == null) const Expanded(child: SizedBox()),
          const SizedBox(height: 5),

          // Barre de saisie
          Container(
            width: MediaQuery.of(context).size.width * 0.8,
            height: 50,
            decoration: BoxDecoration(color: const Color.fromRGBO(85, 85, 85, 1), borderRadius: BorderRadius.circular(25)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Boutons de la barre de saisie
                IconButton(onPressed: selectFiles, icon: Icon(Icons.add, color: Colors.black45, size: 30)),
                IconButton(onPressed: switchResearchMode, icon: Icon(Icons.language, color: researchMode ? Colors.white70 : Colors.black45, size: 30)),

                // Champ de saisie de texte
                Expanded(
                  child: TextField(
                    controller: inputController,
                    decoration: InputDecoration(hintText: "Posez votre question...", hintStyle: const TextStyle(color: Colors.white30), border: InputBorder.none, counterText: ""),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    cursorColor: Colors.white,
                    maxLength: 25000,
                    onSubmitted: (value) {
                      // Envoie le message lorsque l'utilisateur appuie sur "Entrée"
                      send();
                    },
                  ),
                ),
                // Bouton microphone pour la reconnaissance vocale
                if(Platform.isAndroid)
                  IconButton(onPressed: () {
                    if(_speechEnabled && !_isListening) {
                      setState(() {
                        isListeningMic = true;
                      });
                      _currentText = inputController.text; // Sauvegarde le texte actuel
                      _startListening();
                    } else if(_speechEnabled && _isListening) {
                      setState(() {
                        isListeningMic = false;
                      });
                      _stopListening();
                    }

                  }, icon: Icon(Icons.mic, color: isListeningMic ? Colors.white54 : Colors.black45, size: 30)),
                // Bouton d'envoi du message
                IconButton(onPressed: send, icon: const Icon(Icons.send_rounded, color: Colors.black45, size: 30)),
              ],
            ),
          ),

          // Liste des fichiers sélectionnés
          files.isEmpty
              ? const SizedBox(height: 60)
              : Padding(
                padding: const EdgeInsets.all(8.0),
                child: SizedBox(
                  height: 50,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: files.length,
                    itemBuilder: (context, index) {
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(color: const Color.fromRGBO(85, 85, 85, 1), borderRadius: BorderRadius.circular(15)),
                        child: SizedBox(
                          width: 200,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(child: Text(p.basename(files[index].path), style: const TextStyle(color: Colors.white, fontSize: 14), overflow: TextOverflow.ellipsis)),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  setState(() {
                                    files.removeAt(index);
                                  });
                                },
                                icon: const Icon(Icons.close, color: Colors.white, size: 20),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
        ],
      ),
    );
  }
}










