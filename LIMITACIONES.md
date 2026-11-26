# Limitaciones actuales

## iOS

- El proyecto tiene un target iOS y GitHub Actions genera un IPA sin firma. Ese archivo sirve para comprobar la compilación, pero no se instala directamente en un iPhone.
- **Las pruebas en iPhone y la distribución de iOS quedan pausadas por ahora.** Para instalar en un dispositivo se necesita firmar la app desde Xcode en una Mac. Una cuenta Apple gratuita permite pruebas personales limitadas: hasta tres dispositivos y perfiles que vencen cada siete días, por lo que hay que volver a firmar e instalar la app periódicamente.
- Para distribuir MUSKL a otras personas mediante TestFlight o App Store se necesita la membresía paga de Apple Developer Program. También se requiere configurar las capacidades y credenciales de Apple correspondientes.
- **Iniciar sesión con Apple no está disponible todavía.** Requiere una membresía activa de Apple Developer Program y activar Sign in with Apple en el App ID `mx.muskl.muskl`; hasta entonces, el botón permanece oculto en iOS.
- Las notificaciones push remotas de iOS también quedan pendientes de configurar con APNs y Firebase, lo que requiere las capacidades de Apple correspondientes.

El desarrollo y las pruebas de Android continúan disponibles. El código y el target de iOS se conservan en Flutter para retomarlos cuando se cuente con acceso a una Mac y se decida configurar la firma y distribución de Apple.
