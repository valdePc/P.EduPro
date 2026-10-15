import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'edupro_two_factor_service.dart';

class TeamActionVerification {
  static Future<bool> confirm(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Inicia sesión para continuar.');
    final providers = user.providerData.map((p) => p.providerId).toSet();
    if (providers.contains('google.com')) {
      if (kIsWeb) {
        await user.reauthenticateWithPopup(
          GoogleAuthProvider()
            ..setCustomParameters({'login_hint': user.email ?? ''}),
        );
      } else {
        await GoogleSignIn.instance.initialize();
        final account = await GoogleSignIn.instance.authenticate();
        await user.reauthenticateWithCredential(
          GoogleAuthProvider.credential(
            idToken: account.authentication.idToken,
          ),
        );
      }
    } else if (providers.contains('password') && user.email != null) {
      String password = '';
      Future<dynamic>? transition;
      final result = await showDialog<String>(
        context: context,
        builder: (context) {
          transition = ModalRoute.of(context)?.completed;
          return AlertDialog(
            title: const Text('Confirma tu identidad'),
            content: TextField(
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Tu contraseña'),
              onChanged: (value) => password = value,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, password),
                child: const Text('Confirmar'),
              ),
            ],
          );
        },
      );
      await transition;
      if (result == null || !context.mounted) return false;
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: user.email!, password: result),
      );
    } else {
      throw StateError(
        'Vuelve a iniciar sesión para confirmar esta operación.',
      );
    }
    if (!context.mounted || FirebaseAuth.instance.currentUser?.uid != user.uid)
      return false;
    return EduProTwoFactorService.ensureVerified(
      context,
      audience: 'admin_general',
    );
  }
}
