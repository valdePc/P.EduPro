## Endurecimiento de Firebase

Las `apiKey` del cliente en Firebase no se ocultan de forma real dentro de una app Flutter/Web. La protección efectiva consiste en restringir las keys y exigir App Check.

### Restringe las keys en Google Cloud Console

- `Web`: limita la key por `HTTP referrers` y deja solo tus dominios reales.
- `Android`: limita la key por nombre de paquete y huellas `SHA-1` / `SHA-256`.
- `iOS`: limita la key por `bundle id`.
- Verifica que no sigas publicando con identificadores de ejemplo como `com.example.edupro` si ya tienes IDs productivos.

### Activa App Check en Firebase Console

Habilítalo para:

- Authentication
- Cloud Firestore
- Cloud Storage
- Cloud Functions

Proveedores esperados por este proyecto:

- `Web`: reCAPTCHA Enterprise por defecto; reCAPTCHA v3 si se proporciona expresamente `VALMICH_RECAPTCHA_V3_SITE_KEY`.
- `Android`: Play Integrity
- `Apple`: DeviceCheck

### Compila con App Check activo

Web:

La configuración web de este proyecto activa App Check por defecto con la clave
pública Enterprise registrada para `edupro-8c4fd.web.app`. Una compilación normal
ya incluye esa configuración. Los defines siguientes mantienen compatibilidad
con una configuración V3 explícita; no usar una clave Enterprise en el define V3.

```bash
flutter build web ^
  --dart-define=VALMICH_APP_CHECK=true ^
  --dart-define=VALMICH_APP_CHECK_STRICT=true ^
  --dart-define=VALMICH_RECAPTCHA_V3_SITE_KEY=TU_SITE_KEY
```

Android:

```bash
flutter build apk --dart-define=VALMICH_APP_CHECK=true --dart-define=VALMICH_APP_CHECK_STRICT=true
```

iOS:

```bash
flutter build ios --dart-define=VALMICH_APP_CHECK=true --dart-define=VALMICH_APP_CHECK_STRICT=true
```

### Despliega Functions exigiendo App Check

Según la documentación oficial de Firebase Functions, puedes persistir variables
de entorno de runtime con un archivo `functions/.env` o `functions/.env.<alias>`
y luego desplegar. En este repo quedó una plantilla en
`functions/.env.example`.

Ejemplo:

```bash
Copy-Item functions/.env.example functions/.env
```

Luego despliega normalmente:

```bash
firebase deploy --only functions
```

### Desarrollo local en web

Usar la configuración de VS Code **EduPro Web (App Check)** o
`flutter run -d chrome --web-port=55595` para conservar el mismo origen entre
ejecuciones. Consulta [la corrección del login](login-app-check-fix-2026-10-05.md)
para la autorización administrativa del navegador sin copiar secretos al código.

Según la documentación oficial de App Check para Flutter, en `localhost` puedes
usar debug tokens. Este repo ahora activa automáticamente:

```js
self.FIREBASE_APPCHECK_DEBUG_TOKEN = true
```

solo cuando la app corre en `localhost`, `127.0.0.1` o `::1`.

Cuando abras la app local, revisa la consola del navegador, copia el debug token
y regístralo en Firebase Console > Security > App Check > tu app web > Manage
debug tokens.

### Si sospechas abuso

- Rota las keys por plataforma.
- Publica una nueva build.
- Revoca las keys antiguas después de validar el tráfico nuevo.
