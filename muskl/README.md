# MUSKL Flutter

Cliente móvil Flutter conectado al API de MUSKL y PostgreSQL. La autenticación usa el backend como autoridad para identidad y estado de cuenta; los tokens de acceso y renovación se guardan con `flutter_secure_storage`, se rotan al vencer el acceso y se validan con `/api/v1/auth/me` al abrir la app.

## Arranque local

Primero inicia PostgreSQL y el API siguiendo [backend/README.md](../backend/README.md). Para Android:

```bash
cd muskl
flutter pub get
flutter run -d ID_DEL_DISPOSITIVO --dart-define=MUSKL_API_URL=http://IP_DE_TU_PC:8000
```

Para habilitar Google y Apple en Android, consulta la sección **Inicio de sesión con Google y Apple** en `backend/README.md`. El ID OAuth Web de Google ya está configurado en la app y el ejemplo del API; falta crear el cliente OAuth Android con el paquete y la huella SHA-1 de la firma. Apple requiere su configuración de Apple Developer y sus variables de compilación.

En un emulador Android, usa `http://10.0.2.2:8000`; en un teléfono físico usa la IP LAN de la computadora. La dirección predeterminada `127.0.0.1` solo sirve cuando Flutter y el API corren en el mismo dispositivo.

El usuario administrador inicial se crea con el comando interactivo documentado en `backend/README.md`. No hay cuentas de prueba disponibles en la app conectada.

Para probar en un teléfono Android conectado por USB, inicia el API y usa la IP local de la computadora. En el build de depuración Android permite HTTP para esa conexión local; los builds de distribución deben usar una URL HTTPS:

```bash
flutter run -d ID_DEL_DISPOSITIVO --dart-define=MUSKL_API_URL=http://IP_DE_TU_PC:8000
```

Para generar un APK instalable de depuración:

```bash
flutter build apk --debug
```

El archivo queda en `build/app/outputs/flutter-apk/app-debug.apk`. El acceso por correo y contraseña y las notificaciones internas funcionan con el API.

## Flujos conectados

- Inicio de sesión por correo o número de socio, cierre de sesión, recuperación de contraseña y restauración de sesión segura.
- Registro de cliente, entrenador (con certificación) y admin (con token de invitación).
- Onboarding de cliente, planes, entrenadores y selección de una rutina publicada compatible.
- Promociones grupales: cada integrante tiene credenciales, cuenta y onboarding individual; el grupo comparte el número de socio y el plan (Parejas, Tres personas o Cuatro o más).
- Paneles y datos del cliente, entrenador y admin; rutinas, fases de ocho semanas, asistencia, notificaciones internas y asignaciones.
- Ajustes del gimnasio, planes, invitaciones y perfil del entrenador persistidos en PostgreSQL; el admin puede activar avisos internos de nuevas solicitudes de staff.
- Revisión de solicitudes de staff y solicitudes de baja de clientes. Al aprobar una baja, se desactiva el acceso durante 90 días; después, el API elimina la cuenta y sus datos personales y conserva la solicitud administrativa desvinculada.

## Integraciones que requieren configuración

- La recuperación de contraseña envía correo por SMTP. Sin SMTP, en modo desarrollo el código aparece en el log del contenedor API.
- Las notificaciones se guardan en la base; falta conectar un proveedor de push.
- Google y Apple autentican cuentas MUSKL existentes cuyo correo verificado coincide con el proveedor; consulta `backend/README.md` para configurar las credenciales.
- Las certificaciones se guardan en el volumen local `backend/uploads`; para despliegue se necesita almacenamiento privado y HTTPS.

## Estructura

- `lib/core`: tema, navegación y componentes comunes.
- `lib/features/auth`: contrato de repositorio, API PostgreSQL y flujos de acceso.
- `lib/features/status`: estados de cuenta pendiente, rechazada y desactivada.
- `lib/features/prototype_screens.dart`: registro y onboarding (conectados al API pese al nombre histórico del archivo).
- `lib/features/workspace_screens.dart`: módulos de cliente, entrenador y administrador.
