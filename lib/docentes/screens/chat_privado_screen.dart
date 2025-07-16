import 'package:flutter/material.dart';

class ChatPrivadoScreen extends StatelessWidget {
  final String estudiante;

  const ChatPrivadoScreen({Key? key, required this.estudiante}) : super(key: key);

  static const Color primaryColor = Color(0xFF1A5276);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat con $estudiante'),
        backgroundColor: primaryColor,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: 10, // simula 10 mensajes
              itemBuilder: (context, index) {
                bool isSender = index % 2 == 0;
                return Align(
                  alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSender ? primaryColor : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isSender ? 'Mensaje enviado' : 'Mensaje recibido',
                      style: TextStyle(color: isSender ? Colors.white : Colors.black87),
                    ),
                  ),
                );
              },
            ),
          ),
          // Campo de texto + botón
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Escribe tu mensaje...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () {},
                  color: primaryColor,
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
