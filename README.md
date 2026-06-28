# GPS Tracker Flutter

Aplicacion Flutter para seguimiento GPS en Android y simulacion web. La pantalla principal muestra contadores de actividad en primer plano y segundo plano, ultima ubicacion capturada, historial de seguimiento y controles para pausar, reanudar o limpiar registros.
<p align="center">
    <img width="30%" alt="icon" src="https://github.com/user-attachments/assets/26a98b79-bcd8-4eff-a851-d858559e5329" />
</p>

## Funciones

- Seguimiento GPS en primer plano mientras la app esta visible.
- Servicio Android en segundo plano usando foreground service de tipo `location`.
- Notificacion persistente en Android mientras el servicio de seguimiento esta activo.
- Simulador web para probar la experiencia sin servicio Android real.
- Historial de las ultimas lecturas de seguimiento, con origen, contador, hora y coordenadas si estan disponibles.
- Boton para limpiar historial, contadores y ultima ubicacion.

## Requisitos

- Flutter instalado y configurado.
- Android SDK configurado para compilar APK.
- Un dispositivo Android fisico para validar seguimiento real en segundo plano.
- GPS activo en el dispositivo.

## Ejecutar en web

1. Instala dependencias:

   ```bash
   flutter pub get
   ```

2. Ejecuta la app en Chrome:

   ```bash
   flutter run -d chrome
   ```

3. Presiona `Seguir con GPS`.
4. Acepta el permiso de ubicacion del navegador si aparece.
5. Observa el contador de `Primer plano`, el contador de `Segundo plano` como simulador web, la ultima ubicacion y el historial.

Nota: en web no existe el mismo servicio persistente de Android. Por eso el segundo plano web es una simulacion dentro de la sesion del navegador.

## Compilar e instalar en Android

1. Instala dependencias:

   ```bash
   flutter pub get
   ```

2. Genera APK debug:

   ```bash
   flutter build apk --debug
   ```

3. Instala el APK generado:

   ```bash
   flutter install
   ```

   O instala manualmente el archivo:

   ```text
   build/app/outputs/flutter-apk/app-debug.apk
   ```

## Permisos necesarios en Android

La app declara estos permisos en `android/app/src/main/AndroidManifest.xml`:

- `ACCESS_COARSE_LOCATION`
- `ACCESS_FINE_LOCATION`
- `ACCESS_BACKGROUND_LOCATION`
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_LOCATION`
- `POST_NOTIFICATIONS`
- `WAKE_LOCK`

Al abrir la app en Android:

1. Activa el GPS del telefono.
2. Presiona `Seguir con GPS`.
3. Acepta el permiso de ubicacion.
4. Acepta el permiso de notificaciones en Android 13 o superior.
5. Para seguimiento real en segundo plano, abre permisos de la app y cambia ubicacion a `Permitir todo el tiempo`.

Si solo se concede permiso mientras la app esta en uso, el contador de primer plano funcionara, pero Android puede limitar o bloquear lecturas reales en segundo plano.

## Uso de la pantalla principal

- `Primer plano`: cantidad de lecturas hechas mientras la app esta activa o visible.
- `Segundo plano`: lecturas del servicio Android en segundo plano o pulsos del simulador web.
- `Ultima ubicacion`: muestra latitud, longitud, precision y hora de la ultima lectura disponible.
- `Historial de seguimiento`: lista las ultimas lecturas, indicando si vienen de primer plano, segundo plano o simulador web.
- `Seguir con GPS`: inicia o reanuda el seguimiento.
- `Pausar GPS`: pausa temporizadores y servicio de seguimiento.
- `Abrir permisos de la app`: abre la configuracion del sistema para revisar permisos.
- `Limpiar registros y contadores`: reinicia contadores, historial y ultima ubicacion. En Android tambien reinicia el contador interno del servicio.

## Recomendaciones de prueba en Android

1. Instala el APK en un dispositivo fisico.
2. Concede ubicacion y notificaciones.
3. Cambia ubicacion a `Permitir todo el tiempo`.
4. Presiona `Seguir con GPS`.
5. Bloquea la pantalla o cambia a otra app.
6. Espera al menos 15 segundos.
7. Vuelve a abrir la app y revisa `Segundo plano` e `Historial de seguimiento`.

--------------------------

## Capturas del funcionamiento

--------------------------

## Pantalla de inicio
<p align="center">
   <img width="30%" alt="image" src="https://github.com/user-attachments/assets/c23c2c82-f0a5-488d-8263-c8711107a6ce" />
   <img width="30%" alt="image" src="https://github.com/user-attachments/assets/408bf5c3-2167-4f68-b76f-224318ea4f94" />
</p>

## Permisos
<img width="30%" alt="image" src="https://github.com/user-attachments/assets/11279dd4-9ede-4c47-a8f7-e25f3f4c2bd1" />

### Nota
Al fondo se visualiza el mensaje para permitir la ubicación en todo momento...

<img width="30%" alt="image" src="https://github.com/user-attachments/assets/a07a6181-9c5b-492a-8837-2a1d070484f5" />

## Notificación del uso del GPS en tiempo real
<img width="30%" alt="image" src="https://github.com/user-attachments/assets/e6d80f7f-33b7-48f4-a81a-d6f203153197" />

## Ubicaciones registradas en primer y segundo plano:
<img width="30%" alt="image" src="https://github.com/user-attachments/assets/0da28636-e3e5-41c7-baca-e2361bb6e005" />

## Visualización del historial de localizaciones
<img width="30%" alt="image" src="https://github.com/user-attachments/assets/5d19a9b9-f8b0-4805-8b60-734d12470d47" />
