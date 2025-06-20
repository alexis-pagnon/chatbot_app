

/* ----------------------------------
  Projet 4A : Chatbot App
  Date : 11/06/2025
  conversation_subject.dart
---------------------------------- */

/// Classe représentant un sujet de conversation
/// Elle contient un identifiant, un titre et la date de la dernière mise à jour
/// Elle est utilisée pour afficher les sujets de conversation dans l'application, en chargeant les données depuis un format json
class ConversationSubject {
  final String id;
  final String titre;
  final DateTime lastUpdate;

  ConversationSubject({
    required this.id,
    required this.titre,
    required this.lastUpdate,
  });

  factory ConversationSubject.fromJson(Map<String, dynamic> json) {
    return ConversationSubject(
      id: json['id'].toString(),
      titre: json['title'],
      lastUpdate: DateTime.parse(json['last_update'])
    );
  }

  @override
  String toString() {
    return 'Conversation(id: $id, title: $titre, last_update: $lastUpdate)';
  }
}