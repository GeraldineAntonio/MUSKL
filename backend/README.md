# MUSKL API + PostgreSQL

Base real inicial del sistema. El API ya implementa autenticación con correo o número de socio, contraseñas Argon2, sesiones JWT revocables con refresh token rotativo de 30 días, alta de clientes, solicitudes de entrenador con archivo de certificación, solicitudes de admin mediante token, recuperación por correo, revisión de staff, ajustes básicos del gimnasio y planes, códigos de invitación y baja/reactivación con auditoría.

La base también define membresías, grupos de clientes con cuentas individuales y número de socio compartido, asignaciones de entrenador, onboarding, rutinas y fases de ocho semanas, ejercicios, asistencia, solicitudes de eliminación, notificaciones y auditoría. Las promociones soportan parejas, tres integrantes y grupos de cuatro a cincuenta personas. En los grupos cada persona usa su propio correo y contraseña, y completa individualmente su onboarding, preferencias y rutina; todos conservan el mismo plan y número de socio. Flutter conecta inicio de sesión, recuperación y registro de cliente, entrenador y admin (certificación obligatoria para entrenador; token solo para admin), onboarding, perfil y asistencia del cliente, listas de usuarios/solicitudes y métricas admin, además de clientes y rutinas. En el onboarding se puede elegir una rutina publicada compatible con el objetivo y los días disponibles. El entrenador puede crear rutinas, publicar fases y asignarlas a clientes; al completar ocho semanas, el backend avanza a la siguiente fase publicada y crea avisos internos para el cliente o el entrenador. El cliente ve su fase vigente y puede registrar la sesión del día. Los ajustes admin de gimnasio, planes, cuentas, invitaciones y preferencia para avisos de nuevas solicitudes, además de los ajustes del entrenador (datos personales, perfil, contraseña y preferencias), se guardan en PostgreSQL. Al registrarse un entrenador o admin, se crea un aviso interno para los admins activos que tengan habilitada esa preferencia; pueden consultarlo y marcarlo como leído en Solicitudes. Los tokens de invitación solo se muestran una vez; la base conserva su hash y permite revocarlos. Las bajas aprobadas por solicitud del socio conservan los datos hasta la fecha límite de reactivación (90 días); el API ejecuta una purga cada 12 horas y elimina entonces la cuenta y sus datos identificables, manteniendo la solicitud y auditoría desligadas de la cuenta. La entrega push al dispositivo y el envío de notificaciones operativas por correo aún requieren configurar sus proveedores.

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

El comando aplica `db/001_schema.sql` a `db/007_group_memberships.sql` en orden, guarda las versiones en `muskl_schema_migrations` y omite las ya aplicadas. Usa un bloqueo advisory para que dos despliegues no apliquen migraciones simultáneamente. La primera ejecución supone una base vacía. Si ya tienes datos locales que quieras conservar, primero hay que exportarlos e importarlos; crear la base en la nube no copia esos datos.

Configura también en el servicio del API `JWT_SECRET` con al menos 32 caracteres aleatorios, `MUSKL_ENV=production`, y las variables `MUSKL_SMTP_*` para recuperación de contraseña. Define `MUSKL_UPLOAD_DIR` sobre almacenamiento persistente/privado antes de aceptar certificaciones; el filesystem efímero de algunos planes gratuitos no sirve para conservar esos archivos. La URL pública del API debe ser HTTPS, y esa URL se compila en Flutter con `--dart-define=MUSKL_API_URL=https://...`.

El archivo `backend/.env` es para desarrollo local y está excluido de Git. En GitHub guarda secretos solo en la configuración de Actions/Deploy, nunca en commits, documentación ni en el APK.

El usuario admin inicial es el único que se crea automáticamente; no hay contraseñas demo en el código. Las contraseñas se almacenan como hash, nunca en texto plano.

### Despliegue de prueba con Render y Neon

La raíz del repositorio contiene `render.yaml`, configurado para crear una API Docker gratuita en Render desde `main`. En Render, crea un Blueprint y conecta el repositorio `GeraldineAntonio/MUSKL`. Crea primero una base vacía PostgreSQL en Neon, selecciona **Pooled connection** en el panel y pega esa cadena como `DATABASE_URL` cuando Render la solicite; debe incluir `sslmode=require`. Render genera `JWT_SECRET` y define `MUSKL_ENV=production`.

El comando de inicio de Render aplica las migraciones con `python -m app.migrate` antes de arrancar Uvicorn en el puerto que Render asigne. Esto requiere una base Neon vacía la primera vez. El health check público será `https://NOMBRE.onrender.com/health`. Render Free puede dormir después de 15 minutos sin tráfico; la primera petición puede tardar cerca de un minuto en despertar. La app permite ese tiempo de conexión.

Cuando Render termine de arrancar y aplicar las migraciones, crea el primer administrador en la base Neon: instala las dependencias del backend en tu computadora (`python -m pip install -r requirements.txt`) y ejecuta `python -m app.bootstrap_admin_cloud` desde `backend`. El comando pide la URL de Neon sin mostrarla y después pide los datos del admin. No pegues la URL aquí ni la guardes en Git.

El plan gratuito de Render no conserva archivos en el disco local y bloquea SMTP saliente en sus puertos comunes. Por ahora, usa esta instalación para probar cuentas, rutinas y flujos internos; las certificaciones subidas no son almacenamiento duradero y la recuperación por correo necesita configurar un proveedor compatible. No uses esta configuración gratis para datos reales del gimnasio.

## Flutter contra el API

Arranca el API como arriba y obtén la IP local de esta computadora (por ejemplo con `ip addr`). En el teléfono, `localhost` apunta al teléfono, así que usa la IP LAN del equipo:

```bash
cd /home/geri/MUSKL/muskl
flutter pub get
flutter run -d R5GL839XY3P --dart-define=MUSKL_API_URL=http://IP_DE_TU_PC:8000
```

Flutter usa el API real por defecto en `http://127.0.0.1:8000`. En un emulador Android configura `--dart-define=MUSKL_API_URL=http://10.0.2.2:8000`; en un teléfono físico usa la IP LAN de la computadora como muestra el comando. El API no crea cuentas de prueba; utiliza el bootstrap admin y el registro para generar cuentas reales.

## Desarrollo y despliegue

En modo `development`, si no configuras SMTP, los códigos de recuperación se escriben en el log del contenedor API. Configura `MUSKL_SMTP_*` antes de usar recuperación por email fuera del desarrollo. Las certificaciones se guardan en el volumen local `backend/uploads`; para producción se debe conectar almacenamiento privado de objetos y HTTPS. Restringe `MUSKL_CORS_ORIGINS` al origen real si se añade una aplicación web.

Los scripts `db/001_schema.sql` a `db/007_group_memberships.sql` se ejecutan al inicializar un volumen vacío. Si ya tienes la base creada, aplica las migraciones pendientes desde la raíz del proyecto:

```bash
docker compose --env-file backend/.env exec -T db psql -U muskl -d muskl < backend/db/002_client_workouts_and_account_rules.sql
docker compose --env-file backend/.env exec -T db psql -U muskl -d muskl < backend/db/003_trainer_preferences.sql
docker compose --env-file backend/.env exec -T db psql -U muskl -d muskl < backend/db/004_expired_account_deletion.sql
docker compose --env-file backend/.env exec -T db psql -U muskl -d muskl < backend/db/005_refresh_tokens.sql
docker compose --env-file backend/.env exec -T db psql -U muskl -d muskl < backend/db/006_admin_preferences.sql
docker compose --env-file backend/.env exec -T db psql -U muskl -d muskl < backend/db/007_group_memberships.sql
```

Las migraciones son idempotentes; no borres el volumen para actualizar.
