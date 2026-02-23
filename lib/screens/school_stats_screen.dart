import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SchoolStatsScreen extends StatelessWidget {
  final String schoolCode;
  final String schoolName;

  const SchoolStatsScreen({
    Key? key,
    required this.schoolCode,
    required this.schoolName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return Scaffold(
      appBar: AppBar(
        title: Text('Estadísticas - $schoolName'),
        backgroundColor: Colors.blue.shade900,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db.collection('schools').doc(schoolCode).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data();
          if (data == null) {
            return const Center(child: Text('No hay datos'));
          }

          final teachers = data['teachersCount'] ?? 0;
          final students = data['studentsCount'] ?? 0;
          final plan = (data['plan'] ?? '').toString().toUpperCase();
          final maxTeachers = data['maxTeachers'] ?? 1;
          final maxStudents = data['maxStudents'] ?? 1;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _planCard(plan),
                const SizedBox(height: 30),
                _usageCard(
                  title: "Docentes",
                  used: teachers,
                  max: maxTeachers,
                  color: Colors.blue,
                ),
                const SizedBox(height: 30),
                _usageCard(
                  title: "Estudiantes",
                  used: students,
                  max: maxStudents,
                  color: Colors.green,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _planCard(String plan) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade300, Colors.orange.shade700],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "PLAN ACTUAL",
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Text(
            plan,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          )
        ],
      ),
    );
  }

  Widget _usageCard({
    required String title,
    required int used,
    required int max,
    required Color color,
  }) {
    final percentage = (used / max).clamp(0.0, 1.0);
    final isOverLimit = used > max;

    final indicatorColor = isOverLimit ? Colors.red : color;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
          )
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                "$used / $max",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: indicatorColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          /// 🎯 CÍRCULO
          SizedBox(
            height: 120,
            width: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: percentage,
                  strokeWidth: 10,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(indicatorColor),
                ),
                Text(
                  "${(percentage * 100).toInt()}%",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: indicatorColor,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          /// 📊 BARRA PROGRESO
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: percentage,
              minHeight: 10,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(indicatorColor),
            ),
          ),

          if (isOverLimit)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                "⚠ Límite superado",
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}