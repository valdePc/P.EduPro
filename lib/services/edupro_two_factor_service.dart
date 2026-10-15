import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:edupro/services/app_check_bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EduProTwoFactorService {
  EduProTwoFactorService._();

  static final FirebaseFunctions _fn =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<bool> ensureVerified(
    BuildContext context, {
    required String audience,
    String? schoolId,
    String? schoolName,
  }) async {
    final status = await _call(
      'getEduProTwoFactorStatus',
      <String, dynamic>{
        'audience': audience,
        if (schoolId != null && schoolId.trim().isNotEmpty)
          'schoolId': schoolId.trim(),
      },
    );

    if (status['required'] == false) {
      return true;
    }

    if (status['required'] != true || status['enrolled'] is! bool) {
      throw StateError('No se pudo comprobar la verificacion en dos pasos.');
    }

    if (status['verified'] == true && status['enrolled'] == true) return true;

    if (!context.mounted) return false;

    final enrolled = status['enrolled'] == true;
    if (enrolled) {
      return _showVerifyDialog(
        context,
        audience: audience,
        schoolId: schoolId,
        schoolName: schoolName,
      );
    }

    final setup = await _call(
      'startEduProTwoFactorEnrollment',
      <String, dynamic>{
        'audience': audience,
        if (schoolId != null && schoolId.trim().isNotEmpty)
          'schoolId': schoolId.trim(),
      },
    );

    if (!context.mounted) return false;

    return _showEnrollmentDialog(
      context,
      audience: audience,
      schoolId: schoolId,
      schoolName: schoolName,
      secret: (setup['secret'] ?? '').toString(),
      otpauthUri: (setup['otpauthUri'] ?? '').toString(),
      accountLabel: (setup['accountLabel'] ?? '').toString(),
    );
  }

  static Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> payload,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Tu sesion ha finalizado. Inicia sesion nuevamente.');
    }
    await AppCheckBootstrap.ensureReadyForProtectedCall();
    String? idToken;
    try {
      // Let the SDK reuse/refresh the current token normally. Never log it.
      idToken = await user.getIdToken();
    } catch (_) {
      throw StateError('No se pudo validar tu sesion. Inicia sesion nuevamente.');
    }
    if (idToken == null || idToken.isEmpty ||
        FirebaseAuth.instance.currentUser?.uid != user.uid) {
      throw StateError('Tu sesion ha finalizado. Inicia sesion nuevamente.');
    }
    // One request only: automatically replaying a TOTP can consume it twice.
    final callable = _fn.httpsCallable(name);
    final response = await callable.call(payload);
    final raw = response.data;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry('$key', value));
    }
    return const <String, dynamic>{};
  }

  static Future<bool> _showVerifyDialog(
    BuildContext context, {
    required String audience,
    String? schoolId,
    String? schoolName,
  }) async {
    final codeCtrl = TextEditingController();
    bool loading = false;
    String? errorText;
    Future<dynamic>? dialogTransition;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        dialogTransition = ModalRoute.of(dialogContext)?.completed;
        return StatefulBuilder(
          builder: (dialogContext, setModalState) {
            Future<void> submit() async {
              final code = codeCtrl.text.trim();
              if (!RegExp(r'^\d{6}$').hasMatch(code)) {
                setModalState(() => errorText = 'Escribe el código de 6 dígitos.');
                return;
              }

              setModalState(() {
                loading = true;
                errorText = null;
              });

              bool dismissed = false;
              try {
                final verification = await _call(
                  'verifyEduProTwoFactorCode',
                  <String, dynamic>{
                    'audience': audience,
                    'code': code,
                    if (schoolId != null && schoolId.trim().isNotEmpty)
                      'schoolId': schoolId.trim(),
                  },
                );
                if (verification['ok'] != true || verification['verified'] != true) {
                  throw StateError('No se pudo confirmar la verificacion.');
                }
                if (dialogContext.mounted) {
                  dismissed = true;
                  Navigator.of(dialogContext).pop(true);
                }
              } on FirebaseFunctionsException catch (e) {
                setModalState(() {
                  errorText =
                      e.message ?? 'No se pudo verificar el código.';
                });
              } catch (e) {
                setModalState(() {
                  errorText = 'No se pudo verificar el código: $e';
                });
              } finally {
                if (!dismissed && dialogContext.mounted) {
                  setModalState(() => loading = false);
                }
              }
            }

            final titleSuffix = (schoolName ?? '').trim();

            return AlertDialog(
              title: Text(
                titleSuffix.isEmpty
                    ? 'Verificación en dos pasos'
                    : 'Verificación en dos pasos · $titleSuffix',
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Abre tu app autenticadora y escribe el código temporal de 6 dígitos para continuar.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: codeCtrl,
                      autofocus: true,
                      enabled: !loading,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Código de 6 dígitos',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) {
                        if (!loading) {
                          submit();
                        }
                      },
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: loading
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: loading ? null : submit,
                  child: Text(loading ? 'Verificando...' : 'Verificar'),
                ),
              ],
            );
          },
        );
      },
    );

    // showDialog completes when pop is requested, before its reverse animation
    // removes the route. Keep the controller alive until that route is gone.
    if (dialogTransition != null) await dialogTransition;
    codeCtrl.dispose();
    return result == true;
  }

  static Future<bool> _showEnrollmentDialog(
    BuildContext context, {
    required String audience,
    String? schoolId,
    String? schoolName,
    required String secret,
    required String otpauthUri,
    required String accountLabel,
  }) async {
    final codeCtrl = TextEditingController();
    bool loading = false;
    String? errorText;
    Future<dynamic>? dialogTransition;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        dialogTransition = ModalRoute.of(dialogContext)?.completed;
        return StatefulBuilder(
          builder: (dialogContext, setModalState) {
            Future<void> submit() async {
              final code = codeCtrl.text.trim();
              if (!RegExp(r'^\d{6}$').hasMatch(code)) {
                setModalState(() => errorText = 'Escribe el código de 6 dígitos.');
                return;
              }

              setModalState(() {
                loading = true;
                errorText = null;
              });

              bool dismissed = false;
              try {
                final enrollment = await _call(
                  'confirmEduProTwoFactorEnrollment',
                  <String, dynamic>{
                    'audience': audience,
                    'code': code,
                    if (schoolId != null && schoolId.trim().isNotEmpty)
                      'schoolId': schoolId.trim(),
                  },
                );
                if (enrollment['ok'] != true || enrollment['enrolled'] != true) {
                  throw StateError('No se pudo confirmar la activacion.');
                }
                if (dialogContext.mounted) {
                  dismissed = true;
                  Navigator.of(dialogContext).pop(true);
                }
              } on FirebaseFunctionsException catch (e) {
                setModalState(() {
                  errorText =
                      e.message ?? 'No se pudo activar la verificación.';
                });
              } catch (e) {
                setModalState(() {
                  errorText = 'No se pudo activar la verificación: $e';
                });
              } finally {
                if (!dismissed && dialogContext.mounted) {
                  setModalState(() => loading = false);
                }
              }
            }

            Future<void> copyText(String label, String value) async {
              await Clipboard.setData(ClipboardData(text: value));
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(content: Text('$label copiado.')),
              );
            }

            final titleSuffix = (schoolName ?? '').trim();

            return AlertDialog(
              title: Text(
                titleSuffix.isEmpty
                    ? 'Activa la verificación en dos pasos'
                    : 'Activa la verificación en dos pasos · $titleSuffix',
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tu cuenta aún no tiene 2FA. Añádela en Google Authenticator, Authy o cualquier app TOTP y luego confirma con el primer código.',
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F7FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFD7E0FF)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cuenta: $accountLabel',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              secret,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: loading
                                      ? null
                                      : () => copyText('Clave secreta', secret),
                                  icon: const Icon(Icons.key_rounded),
                                  label: const Text('Copiar clave'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: loading
                                      ? null
                                      : () => copyText(
                                            'Enlace de autenticador',
                                            otpauthUri,
                                          ),
                                  icon: const Icon(Icons.link_rounded),
                                  label: const Text('Copiar enlace'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Pasos rápidos',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '1. Abre tu app autenticadora.\n'
                        '2. Elige agregar cuenta manual.\n'
                        '3. Usa la clave secreta mostrada arriba.\n'
                        '4. Tipo de código: TOTP / 6 dígitos / 30 segundos.\n'
                        '5. Escribe aquí el primer código para activarlo.',
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: codeCtrl,
                        autofocus: true,
                        enabled: !loading,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Primer código de 6 dígitos',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) {
                          if (!loading) {
                            submit();
                          }
                        },
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorText!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: loading
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: loading ? null : submit,
                  child: Text(loading ? 'Activando...' : 'Activar 2FA'),
                ),
              ],
            );
          },
        );
      },
    );

    if (dialogTransition != null) await dialogTransition;
    codeCtrl.dispose();
    return result == true;
  }
}
