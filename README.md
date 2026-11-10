# Restaurante — app tipo Soft Restaurant para iPhone

App SwiftUI para iPhone, para el restaurante y para el cliente. Sin servidor, sin cuenta de Apple Developer inventada: usa tu propia cuenta / equipo en Xcode.

## Diseño (estilo Loyverse POS, bonito, no plano)

- **Encabezado con gradiente naranja → rojo** en todas las pantallas: logo del negocio en círculo, nombre, fecha y **ventas del día en grande**.
- **Tarjetas blancas con esquinas grandes (20 pt) y sombra suave**, fondo gris claro, espaciado generoso.
- **Mesas como tarjetas de color:** libre en verde, ocupada en gradiente naranja/rojo, con total de la cuenta y hora desde la que está ocupada.
- **Menú como tarjetas** con icono por categoría (🌮🍲🥑🥤🍮), precio grande en rojo y botón **+** grande con relieve.
- **Cocina como kanban:** columnas Pendiente (ámbar) → En cocina (naranja) → Listo (verde), con contador por columna y tarjeta por pedido.
- **Ventas:** tarjeta grande verde con el total cobrado hoy, propinas, y contadores de cobrados/activos.
- **Inventario:** barra de progreso por producto (verde, roja si está bajo).
- **Botones principales con gradiente y sombra** (`botonPOS()`), propina con chips 0/10/15/20% que se marcan en naranja, ticket en tarjeta blanca con sombra.
- No cambia el modelo de datos ni `restaurante.json`: los datos viejos siguen cargando igual.

## Qué trae

- **Mesas:** mesas 1–8, libre / ocupada, comanda por mesa, botón Cobrar.
- **Menú / Comanda:** menú mexicano de ejemplo (tacos, enchiladas, pozole, bebidas, postres), precios en MXN. Agrega platillos y envía a cocina.
- **Cocina:** pedidos pendientes, en cocina, listos y cobrados. Botón para avanzar de estado.
- **Inventario:** stock por producto, alerta en rojo cuando llega al mínimo, botones +1 / −1, agregar producto nuevo.
- **Ventas del día:** total cobrado hoy, pedidos cobrados y activos.
- **Cliente:** el cliente pide desde su iPhone, en mesa o para llevar. Su pedido llega directo a cocina como pedido tipo "Cliente".
- **Cerrar cuenta:** en Mesas, botón grande "Cerrar cuenta" por mesa: resumen, propina (0% / 10% / 15% / 20% o cantidad manual en MXN), subtotal + propina + total. Al confirmar, la mesa queda libre, el pedido queda Cobrado y se registra en Ventas del día.
- **Ticket:** al cerrar cuenta, botón "Ver ticket" y "Compartir ticket". El ticket trae logo, nombre, dirección, fecha/hora, mesa, mesero, platillos con cantidad y precio, subtotal, propina, total y "Gracias por su visita".
- **Mi negocio:** pestaña nueva para poner nombre del restaurante, dirección, teléfono, mesero y elegir el logo desde la galería (PhotosPicker). El logo se guarda en local y sale arriba del ticket; sin logo, solo sale el nombre en grande.
- **Red local (WiFi, varios iPhones):** pestaña nueva "Red local". Todos los iPhones con la app, en el mismo WiFi, se encuentran por MultipeerConnectivity (Bonjour, servicio `tiki-comanda`), se conectan y se sincronizan pedidos, mesas, inventario y ventas en tiempo real: un mesero crea un pedido y cocina/caja lo ven; cocina marca Listo y el mesero lo ve. Sin internet y sin servidor. Último cambio gana (por timestamp).
- **Imprimir ticket (Bluetooth):** en el ticket, botón "Imprimir ticket". Usa `UIPrintInteractionController` (AirPrint) para imprimir el ticket como imagen, con el logo centrado y ajustado al ancho del papel. Se elige tamaño de papel (58mm o 80mm) y tamaño del logo (pequeño / mediano / grande), en el ticket y en Mi negocio.
- **Funciones estilo Loyverse (y más):** descuentos por pedido (% o $) en Menú y al cerrar cuenta, con forma de pago (efectivo / tarjeta / transferencia); devoluciones de pedidos cobrados con motivo (ya no suman en ventas); Caja con fondo inicial, entradas/salidas de efectivo y corte por forma de pago; Clientes y lealtad (1 punto por cada $20, historial por cliente); Reportes (hoy / 7 días, venta promedio, por pago, lo más vendido, exportar ventas a CSV); pedidos en mesa / para llevar / a domicilio (con dirección y teléfono); inventario con importar/exportar CSV; variantes por platillo (ej. "Grande, sin cebolla"); escáner de código de barras con la cámara para buscar un platillo por su código (o código manual); Cocina por estado (Pendiente / En cocina / Listo) con el tiempo que lleva cada pedido.

Datos de ejemplo incluidos. Todo se guarda en local, en `restaurante.json` en Documents del iPhone (JSON, con `FileManager` + `JSONEncoder`/`JSONDecoder`). Al cerrar y abrir la app, los pedidos y el inventario siguen ahí.

## Red local: sincronizar varios iPhones por WiFi

1. Todos los iPhones deben estar en el **mismo WiFi**, con **WiFi y Bluetooth prendidos**.
2. En cada iPhone, pestaña **Red local** → **Encender red local**.
3. La primera vez, acepta el permiso **"buscar dispositivos en tu red local"**. Si lo negaste, ve a Ajustes del iPhone → Restaurante → Red local → activarlo.
4. En uno de ellos, en "Dispositivos cercanos", toca **Conectar** en el otro iPhone. El otro acepta solo (en el restaurante, todos los iPhones con la app son de confianza).
5. Prueba: crea un pedido en un iPhone, tiene que aparecer en **Cocina** del otro en segundos. Si cocina marca Listo, el mesero lo ve.
6. Si no se ven: mismo WiFi, WiFi/Bluetooth prendidos, permiso de red local activado, y que los dos tengan la app abierta en primer plano al conectarse. La sincronización manda el estado completo en JSON por Multipeer; si dos editan a la vez, gana el cambio más nuevo (timestamp).

Permisos (ya en `project.yml`, en el Info.plist generado): `NSLocalNetworkUsageDescription` y `NSBonjourServices` con `_tiki-comanda._tcp`. Si Xcode te pide confirmarlos, están ahí.

## Compilar en terminal (Mac M1, Xcode 27.2, xcodegen)

Requisitos en tu Mac: Xcode 27.2, `xcodegen` (`brew install xcodegen`).

```bash
cd ~/restaurante-ios
xcodegen generate
xcodebuild -project Restaurante.xcodeproj -scheme Restaurante -destination 'generic/platform=iOS' -configuration Release build
```

Si el build termina en `** BUILD SUCCEEDED **`, ya está. Si te da un error, pégalo tal cual.

## Probar en tu iPhone (sin IPA)

```bash
cd ~/restaurante-ios
xcodegen generate
open Restaurante.xcodeproj
```

En Xcode: elige tu iPhone arriba, elige tu equipo (Team) en Signing & Capabilities, dale Run. Es el camino más rápido para probarla.

## Exportar IPA para AltStore

1. Archiva:
   ```bash
   cd ~/restaurante-ios
   xcodebuild -project Restaurante.xcodeproj -scheme Restaurante -destination 'generic/platform=iOS' -configuration Release archive -archivePath build/Restaurante.xcarchive
   ```
2. Exporta con el archivo `ExportOptions.plist` de este proyecto:
   ```bash
   xcodebuild -exportArchive -archivePath build/Restaurante.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath build/Export
   ```
3. El `.ipa` queda en `build/Export/`. Instálalo con AltStore Classic.

Nota sobre `ExportOptions.plist`: usa `method: development` y `signingStyle: automatic`. En Xcode tienes que elegir tu propio equipo (Team) y, si Xcode te lo pide, tu propio perfil de aprovisionamiento para `com.tiki.softrestaurant`. No hay una cuenta de Apple Developer incluida en este proyecto, y no se inventó ninguna.

## Imprimir el ticket (Bluetooth / AirPrint)

- En el ticket, botón **"Imprimir ticket"**: usa `UIPrintInteractionController` (AirPrint), que es lo que agarra cualquier impresora compatible con AirPrint / Bluetooth que iOS reconozca, sin depender de una marca (Epson, Star, Xprinter, etc.).
- El ticket se genera como **imagen** (`imagenTicket`), con el logo centrado y ajustado al ancho del papel, para que quede bien en térmicas de **58mm** (384 puntos de ancho) o **80mm** (576 puntos).
- Tamaño de papel y tamaño del logo (pequeño / mediano / grande) se eligen en el ticket mismo y en la pestaña **Mi negocio**, y se guardan en local.
- **Térmicas Bluetooth genéricas sin AirPrint:** iOS no deja hablar directo por Bluetooth con cualquier impresora sin su SDK. En ese caso, usa la app del fabricante de tu impresora (la que viene con ella) y comparte el ticket con **"Compartir ticket"**, o imprime la captura del ticket. No se prometió soporte directo por ESC/POS Bluetooth.

## Cambiar el menú / mesas

Edita `Sources/Restaurante/App.swift`, en la función `semilla()` dentro de `DataStore`: ahí están el menú, el inventario inicial y el pedido de ejemplo. Guarda, vuelve a compilar con los comandos de arriba.

## Archivos

- `project.yml` — proyecto xcodegen, target iOS, deploymentTarget 26.0, bundleId `com.tiki.softrestaurant`, permisos de red local (NSLocalNetworkUsageDescription + NSBonjourServices `_tiki-comanda._tcp`) y de cámara (NSCameraUsageDescription, para escanear códigos de barras)
- `Sources/Restaurante/App.swift` — toda la app (modelos, datos, vistas)
- `ExportOptions.plist` — exportar IPA
- `PASOS.md` — pasos cortos
- `README.md` — este archivo

## Aviso

Este proyecto **no se compiló en esta máquina**: aquí no hay Xcode ni Mac, solo se verificó sintaxis básica (conteo de llaves / paréntesis y estructura de archivos). La primera compilación real es en tu Mac con los comandos de arriba.
