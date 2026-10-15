import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'package:edupro/firebase_options.dart';
import 'package:edupro/utils/equipo_edupro_access.dart';

class EquipoEduProScreen extends StatelessWidget {
  const EquipoEduProScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SafeArea(child: EquipoEduProManager()));
  }
}

class EquipoEduProManager extends StatefulWidget {
  final bool embedded;
  final String title;
  final String subtitle;

  const EquipoEduProManager({
    super.key,
    this.embedded = false,
    this.title = 'Equipo EduPro',
    this.subtitle =
        'Aqui gestionamos al equipo interno de EduPro con acceso por correo, contrasena, horario y dias permitidos.',
  });

  @override
  State<EquipoEduProManager> createState() => _EquipoEduProManagerState();
}

class _EquipoEduProManagerState extends State<EquipoEduProManager> {
  static const Color _kEduProBlue = Color(0xFF1A237E);
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _savingTeamChange = false;

  static const List<_WeekdayOption> _weekdayOptions = [
    _WeekdayOption(1, 'Lunes'),
    _WeekdayOption(2, 'Martes'),
    _WeekdayOption(3, 'Miercoles'),
    _WeekdayOption(4, 'Jueves'),
    _WeekdayOption(5, 'Viernes'),
    _WeekdayOption(6, 'Sabado'),
    _WeekdayOption(7, 'Domingo'),
  ];

  int _toMinutes(TimeOfDay value) => value.hour * 60 + value.minute;

  String _timeLabel(TimeOfDay value) {
    final hour = value.hourOfPeriod == 0 ? 12 : value.hourOfPeriod;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $suffix';
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<UserCredential> _createSecondaryUser({
    required String email,
    required String password,
  }) async {
    final appName = 'equipo-valmich-${DateTime.now().microsecondsSinceEpoch}';
    final app = await Firebase.initializeApp(
      name: appName,
      options: DefaultFirebaseOptions.currentPlatform,
    );

    try {
      final auth = FirebaseAuth.instanceFor(app: app);
      return await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } finally {
      try {
        await FirebaseAuth.instanceFor(app: app).signOut();
      } catch (_) {}
      await app.delete();
    }
  }

  Future<void> _saveTeamChange(Future<void> Function() action) async {
    if (_savingTeamChange) return;
    setState(() => _savingTeamChange = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Permisos actualizados.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudieron guardar los permisos. Revisa tu acceso y vuelve a intentarlo.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingTeamChange = false);
    }
  }

  Future<void> _toggleEnabled(String uid, bool enabled) async {
    final batch = _db.batch();
    final patch = <String, dynamic>{
      'enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    // Preserve legacy records while all consumers move to EquipoEduPro.
    final legacy = await _db.collection('EquipoValMich').doc(uid).get();
    final canonical = await _db.collection('EquipoEduPro').doc(uid).get();
    final primary = await _db.collection('users').doc(uid).get();
    final legacyProfile = await _db.collection('Users').doc(uid).get();
    final identity =
        primary.data() ??
        legacyProfile.data() ??
        canonical.data() ??
        legacy.data() ??
        {};
    final role = EquipoEduProRoles.normalize(
      (identity['teamRole'] ?? identity['role'])?.toString(),
    );
    if (role == EquipoEduProRoles.denied) {
      throw StateError('Asigna un rol válido antes de cambiar el acceso.');
    }
    patch.addAll({'role': role, 'teamRole': role});
    batch.set(_db.collection('EquipoEduPro').doc(uid), {
      ...?legacy.data(),
      ...?canonical.data(),
      ...patch,
    }, SetOptions(merge: true));
    batch.set(
      _db.collection('EquipoValMich').doc(uid),
      patch,
      SetOptions(merge: true),
    );
    batch.set(_db.collection('users').doc(uid), {
      if (!primary.exists) ...identity,
      ...patch,
    }, SetOptions(merge: true));
    if (legacyProfile.exists) batch.update(legacyProfile.reference, patch);
    await batch.commit();
  }

  Future<void> _updateTeamRole(String uid, String role) async {
    final normalized = EquipoEduProRoles.normalize(role);
    if (normalized == EquipoEduProRoles.denied) return;
    final batch = _db.batch();
    final patch = <String, dynamic>{
      'role': normalized,
      'teamRole': normalized,
      'teamRoleLabel': EquipoEduProRoles.label(normalized),
      'teamRoleSummary': EquipoEduProRoles.summary(normalized),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final legacy = await _db.collection('EquipoValMich').doc(uid).get();
    final canonical = await _db.collection('EquipoEduPro').doc(uid).get();
    final primary = await _db.collection('users').doc(uid).get();
    final legacyProfile = await _db.collection('Users').doc(uid).get();
    batch.set(_db.collection('EquipoEduPro').doc(uid), {
      ...?legacy.data(),
      ...?canonical.data(),
      ...patch,
    }, SetOptions(merge: true));
    batch.set(
      _db.collection('EquipoValMich').doc(uid),
      patch,
      SetOptions(merge: true),
    );
    batch.set(_db.collection('users').doc(uid), {
      if (!primary.exists)
        ...?legacyProfile.data() ?? canonical.data() ?? legacy.data(),
      ...patch,
    }, SetOptions(merge: true));
    if (legacyProfile.exists) batch.update(legacyProfile.reference, patch);
    await batch.commit();
  }

  Future<void> _openCreateDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    TimeOfDay startTime = const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 18, minute: 0);
    final selectedDays = <int>{1, 2, 3, 4, 5};
    String teamRole = EquipoEduProRoles.supportOnboarding;
    bool enabled = true;
    bool saving = false;

    Future<void> pickTime({
      required BuildContext context,
      required bool isStart,
      required void Function(void Function()) setDialogState,
    }) async {
      final picked = await showTimePicker(
        context: context,
        initialTime: isStart ? startTime : endTime,
      );
      if (picked == null) return;
      setDialogState(() {
        if (isStart) {
          startTime = picked;
        } else {
          endTime = picked;
        }
      });
    }

    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Agregar usuario Equipo EduPro'),
                  content: SizedBox(
                    width: 620,
                    child: Form(
                      key: formKey,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextFormField(
                              controller: nameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Nombre completo',
                                border: OutlineInputBorder(),
                              ),
                              validator:
                                  (v) =>
                                      (v == null || v.trim().isEmpty)
                                          ? 'Requerido'
                                          : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Correo',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) {
                                final value = (v ?? '').trim();
                                if (value.isEmpty) return 'Requerido';
                                if (value.length > 254 ||
                                    !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                        .hasMatch(value))
                                  return 'Correo invalido';
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: passCtrl,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: const InputDecoration(
                                labelText: 'Contrasena',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) {
                                final value = v ?? '';
                                if (value.length < 6)
                                  return 'Minimo 6 caracteres';
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: teamRole,
                              decoration: const InputDecoration(
                                labelText: 'Rol interno',
                                border: OutlineInputBorder(),
                              ),
                              items:
                                  EquipoEduProRoles.all
                                      .map(
                                        (role) => DropdownMenuItem<String>(
                                          value: role,
                                          child: Text(
                                            EquipoEduProRoles.label(role),
                                          ),
                                        ),
                                      )
                                      .toList(),
                              onChanged:
                                  saving
                                      ? null
                                      : (value) => setDialogState(
                                        () =>
                                            teamRole =
                                                EquipoEduProRoles.normalize(
                                                  value,
                                                ),
                                      ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                EquipoEduProRoles.summary(teamRole),
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap:
                                        saving
                                            ? null
                                            : () => pickTime(
                                              context: context,
                                              isStart: true,
                                              setDialogState: setDialogState,
                                            ),
                                    child: InputDecorator(
                                      decoration: const InputDecoration(
                                        labelText: 'Hora inicial',
                                        border: OutlineInputBorder(),
                                      ),
                                      child: Text(_timeLabel(startTime)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: InkWell(
                                    onTap:
                                        saving
                                            ? null
                                            : () => pickTime(
                                              context: context,
                                              isStart: false,
                                              setDialogState: setDialogState,
                                            ),
                                    child: InputDecorator(
                                      decoration: const InputDecoration(
                                        labelText: 'Hora final',
                                        border: OutlineInputBorder(),
                                      ),
                                      child: Text(_timeLabel(endTime)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Dias permitidos',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children:
                                  _weekdayOptions.map((day) {
                                    final selected = selectedDays.contains(
                                      day.value,
                                    );
                                    return FilterChip(
                                      label: Text(day.label),
                                      selected: selected,
                                      onSelected:
                                          saving
                                              ? null
                                              : (value) {
                                                setDialogState(() {
                                                  if (value) {
                                                    selectedDays.add(day.value);
                                                  } else {
                                                    selectedDays.remove(
                                                      day.value,
                                                    );
                                                  }
                                                });
                                              },
                                    );
                                  }).toList(),
                            ),
                            const SizedBox(height: 12),
                            SwitchListTile(
                              value: enabled,
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Acceso habilitado'),
                              onChanged:
                                  saving
                                      ? null
                                      : (value) =>
                                          setDialogState(() => enabled = value),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed:
                          saving ? null : () => Navigator.pop(dialogContext),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed:
                          saving
                              ? null
                              : () async {
                                if (!(formKey.currentState?.validate() ??
                                    false))
                                  return;
                                if (selectedDays.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Selecciona al menos un dia permitido.',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                setDialogState(() => saving = true);
                                try {
                                  final email =
                                      emailCtrl.text.trim().toLowerCase();
                                  final password = passCtrl.text;
                                  final created = await _createSecondaryUser(
                                    email: email,
                                    password: password,
                                  );
                                  final uid = created.user!.uid;

                                  final dayLabels =
                                      _weekdayOptions
                                          .where(
                                            (d) =>
                                                selectedDays.contains(d.value),
                                          )
                                          .map((d) => d.label)
                                          .toList();

                                  final now = FieldValue.serverTimestamp();
                                  final batch = _db.batch();
                                  final teamData = <String, dynamic>{
                                    'uid': uid,
                                    'name': nameCtrl.text.trim(),
                                    'email': email,
                                    'emailLower': email,
                                    'teamRole': teamRole,
                                    'teamRoleLabel': EquipoEduProRoles.label(
                                      teamRole,
                                    ),
                                    'teamRoleSummary':
                                        EquipoEduProRoles.summary(teamRole),
                                    'enabled': enabled,
                                    'startMinute': _toMinutes(startTime),
                                    'endMinute': _toMinutes(endTime),
                                    'startLabel': _timeLabel(startTime),
                                    'endLabel': _timeLabel(endTime),
                                    'allowedWeekdays':
                                        selectedDays.toList()..sort(),
                                    'allowedDayLabels': dayLabels,
                                    'createdAt': now,
                                    'updatedAt': now,
                                  };
                                  batch.set(
                                    _db.collection('EquipoEduPro').doc(uid),
                                    teamData,
                                  );
                                  batch.set(
                                    _db.collection('EquipoValMich').doc(uid),
                                    teamData,
                                  );
                                  batch.set(
                                    _db.collection('users').doc(uid),
                                    {
                                      'uid': uid,
                                      'email': email,
                                      'role': teamRole,
                                      'teamRole': teamRole,
                                      'teamRoleLabel': EquipoEduProRoles.label(
                                        teamRole,
                                      ),
                                      'enabled': enabled,
                                      'source': 'equipo_EduPro',
                                      'displayName': nameCtrl.text.trim(),
                                      'createdAt': now,
                                      'updatedAt': now,
                                    },
                                    SetOptions(merge: true),
                                  );

                                  await batch.commit();

                                  if (!mounted) return;
                                  Navigator.pop(dialogContext);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Usuario del Equipo EduPro creado para ${nameCtrl.text.trim()}.',
                                      ),
                                    ),
                                  );
                                } on FirebaseAuthException {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'No se pudo crear el usuario. Revisa los datos e intenta nuevamente.',
                                      ),
                                    ),
                                  );
                                } catch (_) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('No se pudo completar la creacion del usuario. Intenta nuevamente.'),
                                    ),
                                  );
                                } finally {
                                  if (context.mounted) {
                                    setDialogState(() => saving = false);
                                  }
                                }
                              },
                      child: const Text('Crear usuario'),
                    ),
                  ],
                ),
          ),
    );
  }

  Widget _buildHeader(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final activeCount =
        docs.where((doc) => doc.data()['enabled'] != false).length;
    final blockedCount = docs.length - activeCount;
    final roleCount =
        docs
            .map(
              (doc) => EquipoEduProRoles.normalize(
                (doc.data()['teamRole'] ?? doc.data()['role']).toString(),
              ),
            )
            .toSet()
            .length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kEduProBlue, Color(0xFF2D64C8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _kEduProBlue.withOpacity(0.18),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _openCreateDialog,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Agregar usuario'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _kEduProBlue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeaderBadge(label: 'Usuarios', value: '${docs.length}'),
              _HeaderBadge(label: 'Activos', value: '$activeCount'),
              _HeaderBadge(label: 'Bloqueados', value: '$blockedCount'),
              _HeaderBadge(label: 'Roles', value: '$roleCount'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar usuario, correo o rol...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon:
                  _searchQuery.isEmpty
                      ? null
                      : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFD7DEFA)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        PopupMenuButton<String>(
          tooltip: 'Acciones masivas',
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'export') {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Exportando ${docs.length} usuarios del equipo...',
                  ),
                ),
              );
            }
          },
          itemBuilder:
              (_) => const [
                PopupMenuItem(value: 'export', child: Text('Exportar listado')),
              ],
        ),
      ],
    );
  }

  Widget _buildStatCards(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final activeCount =
        docs.where((doc) => doc.data()['enabled'] != false).length;
    final blockedCount = docs.length - activeCount;
    final rolesCount =
        docs
            .map(
              (doc) => EquipoEduProRoles.normalize(
                (doc.data()['teamRole'] ?? doc.data()['role']).toString(),
              ),
            )
            .toSet()
            .length;

    return Wrap(
      spacing: 18,
      runSpacing: 18,
      children: [
        _StatAccessCard(
          icon: Icons.people_alt_outlined,
          title: 'Usuarios visibles',
          value: '${docs.length}',
          accent: _kEduProBlue,
        ),
        _StatAccessCard(
          icon: Icons.verified_user_outlined,
          title: 'Activos',
          value: '$activeCount',
          accent: Colors.green,
        ),
        _StatAccessCard(
          icon: Icons.warning_amber_rounded,
          title: 'Bloqueados',
          value: '$blockedCount',
          accent: Colors.orange,
        ),
        _StatAccessCard(
          icon: Icons.rule_folder_outlined,
          title: 'Roles definidos',
          value: '$rolesCount',
          accent: Colors.teal,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream:
          _db
              .collection('EquipoValMich')
              .orderBy('createdAt', descending: true)
              .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? const [];
        final filteredDocs =
            docs.where((doc) {
              if (_searchQuery.isEmpty) return true;
              final data = doc.data();
              final name = (data['name'] ?? '').toString().toLowerCase();
              final email = (data['email'] ?? '').toString().toLowerCase();
              final role =
                  EquipoEduProRoles.label(
                    EquipoEduProRoles.normalize(
                      (data['teamRole'] ?? data['role']).toString(),
                    ),
                  ).toLowerCase();
              return name.contains(_searchQuery) ||
                  email.contains(_searchQuery) ||
                  role.contains(_searchQuery);
            }).toList();

        return ListView(
          padding: EdgeInsets.all(widget.embedded ? 0 : 20),
          children: [
            _buildHeader(docs),
            const SizedBox(height: 18),
            _buildStatCards(docs),
            const SizedBox(height: 20),
            _buildToolbar(filteredDocs),
            const SizedBox(height: 20),
            if (filteredDocs.isEmpty)
              Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Center(
                  child: Text(
                    docs.isEmpty
                        ? 'Todavia no hay usuarios registrados en Equipo EduPro.'
                        : 'No hay coincidencias para este filtro.',
                  ),
                ),
              )
            else
              ...filteredDocs.map((doc) {
                final data = doc.data();
                final enabled = data['enabled'] != false;
                final teamRole = EquipoEduProRoles.normalize(
                  (data['teamRole'] ?? data['role']).toString(),
                );
                final dayLabels =
                    (data['allowedDayLabels'] is List)
                        ? (data['allowedDayLabels'] as List)
                            .map((e) => e.toString())
                            .toList()
                        : const <String>[];
                final lastLoginAt = data['lastLoginAt'];

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color:
                          enabled ? Colors.green.shade100 : Colors.red.shade100,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (data['name'] ?? 'Sin nombre').toString(),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  (data['email'] ?? '').toString(),
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                                const SizedBox(height: 6),
                                _InfoPill(
                                  icon: Icons.verified_user_outlined,
                                  text: EquipoEduProRoles.label(teamRole),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Cambiar rol',
                            enabled: !_savingTeamChange,
                            onSelected:
                                (value) => _saveTeamChange(
                                  () => _updateTeamRole(doc.id, value),
                                ),
                            itemBuilder:
                                (context) =>
                                    EquipoEduProRoles.all
                                        .map(
                                          (role) => PopupMenuItem<String>(
                                            value: role,
                                            child: Text(
                                              EquipoEduProRoles.label(role),
                                            ),
                                          ),
                                        )
                                        .toList(),
                          ),
                          Switch(
                            value: enabled,
                            onChanged:
                                _savingTeamChange
                                    ? null
                                    : (value) => _saveTeamChange(
                                      () => _toggleEnabled(doc.id, value),
                                    ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _InfoPill(
                            icon: Icons.schedule,
                            text:
                                '${(data['startLabel'] ?? '--').toString()} - ${(data['endLabel'] ?? '--').toString()}',
                          ),
                          _InfoPill(
                            icon: Icons.calendar_month,
                            text:
                                dayLabels.isEmpty
                                    ? 'Sin dias configurados'
                                    : dayLabels.join(', '),
                          ),
                          _InfoPill(
                            icon: enabled ? Icons.verified : Icons.block,
                            text: enabled ? 'Habilitado' : 'Desactivado',
                          ),
                          _InfoPill(
                            icon: Icons.rule_folder_outlined,
                            text: EquipoEduProRoles.summary(teamRole),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        lastLoginAt is Timestamp
                            ? 'Ultimo acceso: ${lastLoginAt.toDate()}'
                            : 'Ultimo acceso: sin registros todavia',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  final String label;
  final String value;

  const _HeaderBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatAccessCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color accent;

  const _StatAccessCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.blue.shade800),
          const SizedBox(width: 8),
          Flexible(child: Text(text)),
        ],
      ),
    );
  }
}

class _WeekdayOption {
  final int value;
  final String label;

  const _WeekdayOption(this.value, this.label);
}
