# MUSKL API + PostgreSQL

Base real inicial del sistema. El API implementa autenticación con correo o número de socio, contraseñas Argon2, límite de intentos de inicio de sesión, sesiones JWT revocables con refresh token rotativo de 30 días, verificación de correo al registrarse, cambio y recuperación de contraseña con códigos, alta de clientes, solicitudes de entrenador con certificación, solicitudes de admin por invitación, revisión de staff, planes y baja/reactivación con auditoría.

La base también define membresías, grupos de clientes con cuentas individuales y número de socio compartido, asignaciones de entrenador, onboarding, rutinas y fases de ocho semanas, catálogo buscable de ejercicios, asistencia, solicitudes de eliminación, notificaciones y auditoría. La migración `008_exercise_catalog.sql` crea el catálogo inicial y enlaza los ejercicios elegidos a las rutinas; `009_client_profile_photo.sql` permite que cada cliente guarde y cambie una foto JPG o PNG en su perfil. Las certificaciones nuevas de entrenadores se guardan en el bucket privado de R2 cuando está configurado; la base conserva solo la clave del objeto. Las promociones soportan parejas, tres integrantes y grupos de cuatro a cincuenta personas. En los grupos cada persona usa su propio correo y contraseña, y completa individualmente su onboarding, preferencias y rutina; todos conservan el mismo plan y número de socio. Flutter conecta inicio de sesión, recuperación y registro de cliente, entrenador y admin (certificación obligatoria para entrenador; token solo para admin), onboarding, perfil y asistencia del cliente, listas de usuarios/solicitudes y métricas admin, además de clientes y rutinas. En el onboarding se puede elegir una rutina publicada compatible con el objetivo y los días disponibles. El entrenador puede crear rutinas, buscar ejercicios del catálogo, publicar fases y asignarlas a clientes; al completar ocho semanas, el backend avanza a la siguiente fase publicada y crea avisos internos para el cliente o el entrenador. El cliente ve su fase vigente y puede registrar la sesión del día. Los ajustes admin de gimnasio, planes, cuentas, invitaciones y preferencia para avisos de nuevas solicitudes, además de los ajustes del entrenador (datos personales, perfil, contraseña y preferencias), se guardan en PostgreSQL. Al registrarse un entrenador o admin, se crea un aviso interno para los admins activos que tengan habilitada esa preferencia; pueden consultarlo y marcarlo como leído en Solicitudes. Los tokens de invitación solo se muestran una vez; la base conserva su hash y permite revocarlos. La baja administrativa bloquea el acceso de inmediato y permite reactivación durante 30 días. Después, el API purga cada 12 horas las cuentas dadas de baja de clientes y entrenadores, sus datos asociados, fotos de perfil y certificados en R2, y conserva la auditoría sin referencias personales. Las solicitudes de baja aprobadas usan el mismo plazo. La entrega push al dispositivo y el envío de notificaciones operativas por correo aún requieren configurar sus proveedores.

El calendario del cliente muestra los días de entrenamiento de su rutina y las asistencias del mes. También puede registrar desde la app una asistencia diaria si tiene una membresía vigente; esos registros quedan identificados con origen `app` y se limitan a uno por día. Durante una rutina, cada ejercicio se confirma por separado y el servidor no acepta terminar la sesión hasta que estén confirmados todos los ejercicios de ese día.

Cada ejercicio admite `media_url` para una imagen o GIF HTTPS; el archivo debe estar alojado en una dirección accesible por el teléfono. El API envía esa dirección a la app del cliente, que muestra imágenes y GIF animados en el detalle del ejercicio.

## Arranque local

Requiere Docker Engine con Compose.

1. Desde la raíz del proyecto, copia `backend/.env.example` a `backend/.env`.
2. Sustituye `POSTGRES_PASSWORD` y `JWT_SECRET` por secretos aleatorios. En Linux puedes generarlos con `openssl rand -hex 32`.
3. Inicia PostgreSQL y el API:

```bash
docker compose --env-file backend/.env up --build -d
```

4. Crea el primer admin. El comando pide los datos de forma interactiva y luego muestra un token de invitación de un solo uso:

```bash
docker compose --env-file backend/.env run --rm -it api python -m app.bootstrap_admin
```

5. Abre `http://localhost:8000/docs` para ver y usar el contrato HTTP. El health check está en `http://localhost:8000/health`.

## Base PostgreSQL en la nube

El API usa PostgreSQL estándar y acepta la URL mediante `DATABASE_URL`. Para iniciar con Neon, crea una base PostgreSQL y copia su cadena de conexión desde el panel. Guárdala como secreto `DATABASE_URL` en el servicio que alojará el API; añade `sslmode=require` si la URL del proveedor no lo incluye. No pongas esta cadena en Flutter ni en GitHub como texto del código.

Antes de iniciar el API en una base nueva, ejecuta una sola vez:

```bash
python -m app.migrate
```

El comando aplica todas las migraciones numeradas de `db/` en orden, guarda las versiones en `muskl_schema_migrations` y omite las ya aplicadas. Usa un bloqueo advisory para que dos despliegues no apliquen migraciones simultáneamente. La primera ejecución supone una base vacía. Si ya tienes datos locales que quieras conservar, primero hay que exportarlos e importarlos; crear la base en la nube no copia esos datos. Render ejecuta este comando al iniciar el servicio.

La migración `021_client_trainer_requests.sql` permite que los socios entren a su panel sin entrenador ni rutina, soliciten entrenador y esperen aceptación. La rutina se asigna después desde el panel del entrenador. Si un entrenador se da de baja, sus socios quedan marcados para reasignación administrativa.

Para crear el primer administrador en Neon desde tu computadora, instala los requisitos de `backend/requirements.txt` y ejecuta desde `backend`:

```bash
.venv/bin/python -m app.bootstrap_admin
```

El script solicita la URL de Neon sin mostrarla en pantalla, además de nombre, correo y contraseña. Después crea el admin activo y muestra una invitación de un solo uso para crear otros administradores. Si ya existe un admin activo, no crea otra cuenta.

Configura también en el servicio del API `JWT_SECRET` con al menos 32 caracteres aleatorios y `MUSKL_ENV=production`. Para correo transaccional puedes usar Brevo por HTTPS: configura `BREVO_API_KEY` y `BREVO_FROM_EMAIL` con un remitente verificado en Brevo; opcionalmente define `BREVO_FROM_NAME`. Resend (`MUSKL_RESEND_API_KEY` y `MUSKL_RESEND_FROM`) y `MUSKL_SMTP_*` se mantienen como alternativas. En Render Free conviene usar Brevo o Resend por HTTPS porque Render bloquea conexiones SMTP salientes comunes. El backend envía por correo códigos para registro, cambio de contraseña, recuperación, cambio de correo y avisos de cuenta. La verificación de registro vence en 10 minutos, permite hasta cinco intentos por código y limita los envíos a tres por hora. El inicio de sesión permite hasta siete intentos por identificador en una ventana de 15 minutos y bloquea temporalmente los siguientes; la clave del limitador se guarda como hash HMAC; no se almacenan correos ni números en esa tabla. Para certificados crea un bucket **privado** en R2 y un token S3 con lectura/escritura limitado a ese bucket; guarda en Render `MUSKL_R2_ACCOUNT_ID`, `MUSKL_R2_ACCESS_KEY_ID`, `MUSKL_R2_SECRET_ACCESS_KEY` y `MUSKL_R2_PRIVATE_BUCKET`. El API sube los documentos y entrega a los admins del mismo gimnasio enlaces de descarga con vigencia de 10 minutos. No pongas estas credenciales en GitHub ni en el APK. Los códigos de cambio de correo y contraseña se envían por email; cambiar correo exige además la contraseña actual. Olvidar contraseña requiere código válido 10 minutos, con límite de 3 solicitudes por hora y 5 intentos por código. La URL pública del API debe ser HTTPS, y esa URL se compila en Flutter con `--dart-define=MUSKL_API_URL=https://...`.

El archivo `backend/.env` es para desarrollo local y está excluido de Git. En GitHub guarda secretos solo en la configuración de Actions/Deploy, nunca en commits, documentación ni en el APK.

El usuario admin inicial es el único que se crea automáticamente; no hay contraseñas demo en el código. Las contraseñas se almacenan como hash, nunca en texto plano.

### Despliegue de prueba con Render y Neon

La raíz del repositorio contiene `render.yaml`, configurado para crear una API Docker gratuita en Render desde `main`. En Render, crea un Blueprint y conecta el repositorio `GeraldineAntonio/MUSKL`. Crea primero una base vacía PostgreSQL en Neon, selecciona **Pooled connection** en el panel y pega esa cadena como `DATABASE_URL` cuando Render la solicite; debe incluir `sslmode=require`. Render genera `JWT_SECRET` y define `MUSKL_ENV=production`.

El comando de inicio de Render aplica las migraciones con `python -m app.migrate` antes de arrancar Uvicorn en el puerto que Render asigne. Esto requiere una base Neon vacía la primera vez. El health check público será `https://NOMBRE.onrender.com/health`. Render Free puede dormir después de 15 minutos sin tráfico; la primera petición puede tardar cerca de un minuto en despertar. La app permite ese tiempo de conexión.

La migración `020_member_registry.sql` crea `client_member_registry` para precargar socios que aún no tienen cuenta de app. Cada integrante tiene su propia fila y puede compartir `member_number` con su pareja; la identidad se comprueba por nombre, apellido y fecha de nacimiento. Al registrarse, un número existente permite seleccionar y vincular una ficha conservando `payment_due_on`; si el número/persona no está en el padrón, se crea una ficha nueva con la fecha local del gimnasio como fecha de pago. La importación del padrón y la edición administrativa de fechas se harán con una herramienta aparte antes de cargar los socios activos.

Cuando Render termine de arrancar y aplicar las migraciones, crea el administrador principal en la base Neon desde `backend`: ejecuta `.venv/bin/python -m app.bootstrap_admin_cloud`. El comando pide la URL de Neon sin mostrarla y después pide los datos del admin. No pegues la URL aquí ni la guardes en Git. Para una prueba rápida, el script de Eimy puede crear su propio administrador temporal si todavía no hay uno activo.

Para crear la cuenta **Eimy Prueba** y asignarle una rutina de cuerpo completo, ejecuta `.venv/bin/python -m app.seed_demo_client_routine_cloud` desde `backend`. El comando pide solo la URL de Neon de forma oculta y crea la membresía y el perfil de prueba. Si todavía no hay un administrador o entrenador activo, también crea un administrador de demostración con contraseña aleatoria. Al terminar, muestra las credenciales temporales en esa terminal. Guarda la contraseña de Eimy para iniciar sesión en la app cliente. La rutina tiene tres sesiones semanales; las imágenes o GIF se pueden agregar luego desde el catálogo de ejercicios. El comando se detiene sin alterar nada si ya existe `eimy.prueba@example.com`.

Para retirar estos datos de demostración, ejecuta `.venv/bin/python -m app.cleanup_demo_cloud` desde `backend` y proporciona la URL de Neon. El script elimina solo la cuenta `eimy.prueba@example.com`, la rutina demo registrada en auditoría, su grupo de membresía y el administrador `admin.muskl.demo@example.com` si no tiene otras rutinas. Conserva las demás cuentas y rutinas.

El plan gratuito de Render no conserva archivos en el disco local y bloquea SMTP saliente en sus puertos comunes. Por ahora, usa esta instalación para probar cuentas, rutinas y flujos internos; las certificaciones subidas no son almacenamiento duradero y la recuperación por correo necesita configurar Brevo, Resend o un proveedor compatible. Sin Brevo, Resend o SMTP configurados, la baja se registra y queda una notificación interna, pero no se envía un mensaje externo; el panel del admin informa ese resultado. No uses esta configuración gratis para datos reales del gimnasio.

## Flutter contra el API

Arranca el API como arriba y obtén la IP local de esta computadora (por ejemplo con `ip addr`). En el teléfono, `localhost` apunta al teléfono, así que usa la IP LAN del equipo:

```bash
cd /home/geri/MUSKL/muskl
flutter pub get
flutter run -d R5GL839XY3P --dart-define=MUSKL_API_URL=http://IP_DE_TU_PC:8000
```

Flutter usa el API real por defecto en `http://127.0.0.1:8000`. En un emulador Android configura `--dart-define=MUSKL_API_URL=http://10.0.2.2:8000`; en un teléfono físico usa la IP LAN de la computadora como muestra el comando. Las cuentas de prueba se crean solo al ejecutar explícitamente `app.seed_demo_client_routine_cloud`.

## Desarrollo y despliegue

En modo `development`, si no configuras correo, los códigos se escriben en el log del contenedor API. En producción configura Brevo, Resend o SMTP antes de habilitar cambios y recuperación de contraseña. Las nuevas certificaciones se guardan en R2 privado; en desarrollo, si R2 no está configurado, se guardan localmente en `backend/uploads`. Restringe `MUSKL_CORS_ORIGINS` al origen real si se añade una aplicación web.

### Migrar certificaciones locales existentes a R2

Después de configurar las variables `MUSKL_R2_*`, ejecuta `python -m app.migrate_certifications_to_r2` desde `backend`, en un entorno que tenga acceso tanto a Neon como a los archivos originales. El script omite los documentos que ya están en R2 e informa cuáles faltan o requieren revisión. Configura `DATABASE_URL` y, si los archivos no están en `backend/uploads`, `MUSKL_UPLOAD_DIR` para apuntar a la carpeta que los contiene. No borres el disco anterior hasta confirmar que los registros ya muestran `r2://` en `trainer_certifications.storage_key`.

Render Free usa disco efímero. Si los documentos antiguos solo existían en ese disco y ya se perdieron, no se pueden recuperar con el script: el entrenador deberá volver a subirlos. Las nuevas altas en producción fallan de forma segura si R2 no está configurado.

### Migrar fotos de perfil de Neon a R2

Las fotos de clientes, entrenadores y administradores se guardan en el bucket privado indicado por `MUSKL_R2_PRIVATE_BUCKET`. Usa en Render las mismas credenciales R2 que para certificados. Después de desplegar la migración `014_profile_photo_storage_key.sql`, ejecuta desde `backend` y en un entorno con acceso a Neon y R2: `python -m app.migrate_profile_photos_to_r2`. El script copia las fotos JPG/PNG antiguas de clientes, registra su clave R2 y limpia el binario de Neon en una transacción. Las fotos inválidas se reportan para revisión. La app muestra cada foto mediante un acceso temporal de 10 minutos.

Los scripts numerados de `db/` se ejecutan al inicializar un volumen vacío. Si ya tienes la base creada, aplica las migraciones pendientes desde la raíz del proyecto; Render también las aplica al iniciar el servicio:

```bash
docker compose --env-file backend/.env exec -T db psql -U muskl -d muskl < backend/db/002_client_workouts_and_account_rules.sql
docker compose --env-file backend/.env exec -T db psql -U muskl -d muskl < backend/db/003_trainer_preferences.sql
docker compose --env-file backend/.env exec -T db psql -U muskl -d muskl < backend/db/004_expired_account_deletion.sql
docker compose --env-file backend/.env exec -T db psql -U muskl -d muskl < backend/db/005_refresh_tokens.sql
docker compose --env-file backend/.env exec -T db psql -U muskl -d muskl < backend/db/006_admin_preferences.sql
docker compose --env-file backend/.env exec -T db psql -U muskl -d muskl < backend/db/007_group_memberships.sql
docker compose --env-file backend/.env exec -T db psql -U muskl -d muskl < backend/db/008_exercise_catalog.sql
docker compose --env-file backend/.env exec -T db psql -U muskl -d muskl < backend/db/009_client_profile_photo.sql
docker compose --env-file backend/.env exec -T db psql -U muskl -d muskl < backend/db/010_client_attendance_checkin.sql
docker compose --env-file backend/.env exec -T db psql -U muskl -d muskl < backend/db/011_workout_exercise_completions.sql
docker compose --env-file backend/.env exec -T db psql -U muskl -d muskl < backend/db/012_password_change_verification.sql
docker compose --env-file backend/.env exec -T db psql -U muskl -d muskl < backend/db/013_auth_security_hardening.sql
docker compose --env-file backend/.env exec -T db psql -U muskl -d muskl < backend/db/014_profile_photo_storage_key.sql
docker compose --env-file backend/.env exec -T db psql -U muskl -d muskl < backend/db/015_email_verification.sql
docker compose --env-file backend/.env exec -T db psql -U muskl -d muskl < backend/db/016_workout_progression.sql
```

Las migraciones son idempotentes; no borres el volumen para actualizar. Las migraciones `010_client_attendance_checkin.sql` y `011_workout_exercise_completions.sql` añaden el registro de asistencia desde la app y el progreso persistente de cada ejercicio; `012_password_change_verification.sql` separa códigos de recuperación y cambio de contraseña; `014_profile_photo_storage_key.sql` añade la clave de R2 para fotos de perfil; `015_email_verification.sql` agrega la verificación obligatoria de correo al registro; `016_workout_progression.sql` registra las sesiones recorridas, la finalización completa y las rachas. Render aplica las migraciones automáticamente al desplegar.
