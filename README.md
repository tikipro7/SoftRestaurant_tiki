# Bar — app tipo Soft Restaurant para iPhone (lado del staff)

App SwiftUI para iPhone, para un **bar**: mesas, barra, cocina, caja, inventario, ventas y clientes. Sin servidor: todo se guarda en local, en `restaurante.json` en Documents del iPhone. Sin cuenta de Apple Developer inventada: usa tu propia cuenta / equipo en Xcode.

> **Solo lado del staff.** La pestaña Cliente (que el cliente pidiera desde su iPhone) está **desactivada por ahora**: el código sigue ahí, pero no se muestra en el TabView. Tampoco hay **A domicilio**: solo **En mesa** y **Para llevar**.

## Diseño (estilo Loyverse POS, bonito, no plano)

- **Encabezado con gradiente naranja → rojo** en todas las pantallas: logo del negocio en círculo, nombre, fecha y **ventas del día en grande**.
- **Tarjetas blancas con esquinas grandes (20 pt) y sombra suave**, fondo gris claro, espaciado generoso. Nada se encima: el título va arriba solo y los filtros van abajo en una fila desplazable.
- **Mesas como tarjetas de color con el nombre completo** ("Mesa 1", nunca "Mes…"): libre en verde, ocupada en gradiente naranja/rojo, con total de la cuenta, hora desde la que está ocupada y **el mesero que la atiende** (o "Sin mesero").
- **Menú como tarjetas**: icono por categoría, precio grande en rojo, destino **Barra / Cocina**, código, y botón **Agregar** grande.
- **Barra y Cocina como kanban:** Pendiente (ámbar) → En barra / En cocina (naranja) → Listo (verde), con contador por columna y tiempo por pedido (⏱ min, en rojo si lleva 15 min o más).
- **Ventas:** tarjeta grande verde con el total cobrado hoy, propinas, y contadores de cobrados/activos.
- **Inventario:** barra de progreso por producto (verde, roja si está bajo).
- **Botones principales con gradiente y sombra** (`botonPOS()`), propina con chips 0/10/15/20% que se marcan en naranja, ticket en tarjeta blanca con sombra.
- **Modo claro forzado** (`.preferredColorScheme(.light)`): se ve igual en todos los iPhones, sin que el modo oscuro lo ponga negro.
- **Teclado con botón "Listo":** en todos los campos de texto/número hay una barra sobre el teclado con botón **Listo** que lo cierra; también se cierra al tocar fuera del campo.

## Pestañas

Mesas · Menú · Barra · Cocina · Caja · Inventario · Ventas · Clientes · Reportes · Mi negocio · Red local

## Flujo: tocar mesa → agregar → cerrar

1. **Mesas:** toca una mesa y se abre su **comanda** (detalle de la mesa): estado LIBRE/ABIERTA, mesero, total, pedidos activos y botón **"➕ Agregar a la cuenta"** con todos los productos del menú. La cuenta **queda abierta**: se le puede seguir agregando, no se cierra al pedir una vez.
2. **Agregar cantidad:** cada línea del pedido tiene un control grande **− cantidad +**: **+** agrega uno, **−** quita uno, y si llega a **0 el producto sale de la cuenta**. No hay que darle al botón Agregar una y otra vez ni usar un botón Quitar aparte. Está en el carrito de Menú, en Mesas, en Barra y en Cocina.
3. **Cuentas abiertas:** en Mesas hay una sección **"Cuentas abiertas"** con todas las cuentas, su total y botón Abrir. **Fusionar mesas:** elige 2 o más mesas y dale a "🔗 Fusionar en una cuenta" (quedan en una sola cuenta, ej. "Mesa 1 + Mesa 3"). También se puede **mover una mesa a otra cuenta** desde el detalle de la mesa.
4. **Barra / Cocina:** al enviar un pedido, se parte solo por categoría: las **bebidas van a Barra** (cervezas, cócteles, destilados, shots) y la **comida va a Cocina** (alitas, nachos, papas). En Barra y en Cocina, cada pedido tiene botón **"➕ Agregar"** para sumarle más productos a ese pedido ya enviado, sin volver a Mesas.
5. **Cerrar cuenta:** solo cuando tú decidas, en el detalle de la mesa o en Mesas, botón **"🧾 Cerrar cuenta"**: resumen, propina (0% / 10% / 15% / 20% o cantidad manual en MXN), descuento (% o $), forma de pago (efectivo / tarjeta / transferencia). Al confirmar, la mesa queda libre, el pedido queda Cobrado y se registra en Ventas del día.
6. **Ticket:** al cerrar, botón "Ver ticket" y "Compartir ticket". Trae logo, nombre, dirección, fecha/hora, mesa, **mesero**, productos con cantidad y precio, subtotal, propina, total y "Gracias por su visita". Botón **"Imprimir ticket"** por Bluetooth/AirPrint (ver abajo).

## Mesero por mesa

- En el detalle de una mesa hay un **selector de mesero**. En **Mi negocio → "Meseros del bar"** agregas meseros nuevos por nombre (o los quitas).
- La tarjeta de cada mesa muestra **👤 <mesero>**; si no tiene, dice **"Sin mesero"**. El mesero también sale en la comanda y en el **ticket**. Al cerrar cuenta, el mesero de la mesa ya viene puesto.

## Menú de ejemplo (bar, precios en MXN)

Cervezas (Corona, Modelo, Victoria, artesanal 355 ml, $40–65), Michelada $65, Chelada $55, Mojito $120, Margarita $120, Piña colada $130, Gin tonic $110, Tequila shot $60, Tequila reposado (copa) $90, Whisky (copa) $110, Ron con coca $95, Vodka con jugo $95, Shot de Jägermeister $70, Alitas BBQ / buffalo (6) $110, Nachos con queso $95, Papas a la francesa $60, Papas con queso $75, Refresco 600 ml $30, Agua mineral $30. Sin tacos: es menú de bar.

## Menú e inventario por CSV (importar y exportar)

En **Menú** y en **Inventario** hay botones **"📥 Importar CSV"** (abre el picker de archivos, `.csv`) y **"📤 Exportar CSV"** (comparte el archivo). Al importar **no se duplica por nombre**: si el nombre ya existe, se actualiza; si no, se agrega. Al final muestra cuántos se agregaron, cuántos se actualizaron y los errores por línea. También se puede pegar el CSV en el campo de texto de Inventario (respaldo).

### Menú CSV — `Nombre,Precio,Categoria,Codigo`

La categoría decide a dónde va el producto: **Cervezas, Cocteles, Destilados, Shots y Bebidas → Barra**; **Botanas y Comida → Cocina**. Copia y pega esto en un archivo `menu.csv`:

```csv
nombre,precio,categoria,codigo
Mojito,120,Cocteles,MOJ01
Margarita,120,Cocteles,MAR01
Cerveza Corona 355 ml,45,Cervezas,COR01
Cerveza Modelo 355 ml,45,Cervezas,MOD01
Michelada,65,Cervezas,MIC01
Tequila shot,60,Shots,TEQ01
Whisky (copa),110,Destilados,WHI01
Alitas BBQ (6),110,Botanas,ALI01
Nachos con queso,95,Botanas,NAC01
Papas a la francesa,60,Botanas,PAP01
Refresco 600 ml,30,Bebidas,REF01
```

### Inventario CSV — `Nombre,Unidad,Stock,Minimo`

Copia y pega esto en un archivo `inventario.csv`:

```csv
nombre,unidad,stock,minimo
Cerveza Corona,pzas,48,12
Cerveza Modelo,pzas,48,12
Ron blanco,botella,12,2
Tequila,botella,8,2
Whisky,botella,6,1
Vodka,botella,6,1
Ginebra,botella,4,1
Limones,kg,5,1
Hierbabuena,manojo,4,1
Alitas,kg,10,2
Queso,kg,5,1
Papas,kg,8,2
Hielo,kg,20,5
Refresco,pzas,24,6
```

### Editar y eliminar

- **Menú:** cada producto tiene **"✏️ Editar"** (nombre, precio, categoría, código y a dónde va: Barra/Cocina) y **"🗑️ Eliminar"**, más el botón **"➕ Agregar"** para un producto nuevo.
- **Inventario:** cada producto tiene **"✏️ Editar"** (nombre, unidad, stock, mínimo) y **"🗑️ Eliminar"**, más el formulario para agregar producto nuevo. Alerta en rojo cuando llega al mínimo, con botones −1 / +1.

## Qué más trae

- **Cerrar cuenta + propina + ticket con logo** (ver flujo arriba).
- **Mi negocio:** nombre del bar, dirección, teléfono, mesero y logo desde la galería (PhotosPicker). El logo se guarda en local y sale arriba del ticket; sin logo, solo sale el nombre en grande. Ahí también se elige papel (58mm / 80mm) y tamaño del logo, y se agregan los **meseros del bar**.
- **Imprimir ticket (Bluetooth):** en el ticket, botón "Imprimir ticket". Usa `UIPrintInteractionController` (AirPrint) para imprimir el ticket como imagen, con el logo centrado y ajustado al ancho del papel. Se elige tamaño de papel (58mm o 80mm) y tamaño del logo (pequeño / mediano / grande). **Térmicas Bluetooth genéricas sin AirPrint:** iOS no deja hablar directo por Bluetooth con cualquier impresora sin su SDK; en ese caso, usa la app del fabricante y comparte el ticket con "Compartir ticket".
- **Caja:** fondo inicial, entradas/salidas de efectivo con concepto, y corte de caja con total por pago (efectivo / tarjeta / transferencia) y efectivo en caja.
- **Clientes y lealtad:** pestaña Clientes (distinta de la pestaña Cliente desactivada): registra clientes por nombre/teléfono, 1 punto por cada $20 al cobrar. Toca un cliente para ver su historial y sus pedidos.
- **Reportes:** ventas de hoy y de 7 días, venta promedio, por forma de pago, lo más vendido, y exportar ventas a CSV.
- **Devoluciones:** en Ventas, en cada pedido cobrado, escribe el motivo y dale a "Devolver". Queda marcado, ya no suma en ventas, y se ve en la sección Devoluciones.
- **Descuentos:** por pedido (% o $) en Menú y al cerrar cuenta, se reparte entre los pedidos de la mesa y sale en el ticket y en Ventas.
- **Escanear código:** en Menú, "Escanear código" abre la cámara (acepta el permiso la primera vez) y busca el producto por su código; o escríbelo en "Código manual". Para que un producto tenga código, edítalo (o impórtalo por CSV con su código).
- **Variantes:** en Menú, escribe la variante antes de agregar (ej. "Doble, sin hielo") y sale en el pedido, en Barra/Cocina y en lo más vendido.
- **Red local (WiFi, varios iPhones):** pestaña "Red local". Todos los iPhones con la app, en el mismo WiFi, se encuentran por MultipeerConnectivity (Bonjour, servicio `tiki-comanda`), se conectan y se sincronizan pedidos, mesas, inventario y ventas en tiempo real. Sin internet y sin servidor. Último cambio gana (por timestamp).
  1. Todos en el **mismo WiFi**, con **WiFi y Bluetooth prendidos**.
  2. En cada iPhone, pestaña **Red local** → **Encender red local**.
  3. La primera vez, acepta el permiso **"buscar dispositivos en tu red local"**. Si lo negaste, ve a Ajustes del iPhone → Restaurante → Red local → activarlo.
  4. En uno de ellos, en "Dispositivos cercanos", toca **Conectar** en el otro iPhone.
  5. Prueba: crea un pedido en un iPhone, tiene que aparecer en **Barra/Cocina** del otro en segundos.
  Permisos (ya en `project.yml`, en el Info.plist generado): `NSLocalNetworkUsageDescription` y `NSBonjourServices` con `_tiki-comanda._tcp`.

Datos de ejemplo incluidos (menú e inventario de bar). Todo se guarda en local, en `restaurante.json` en Documents del iPhone (JSON, con `FileManager` + `JSONEncoder`/`JSONDecoder`). Al cerrar y abrir la app, los pedidos y el inventario siguen ahí. Los datos viejos siguen cargando igual.

## Compilar en terminal (Mac, Xcode 27.2, xcodegen)

Requisitos en tu Mac: Xcode 27.2, `xcodegen` (`brew install xcodegen`). El repo está en GitHub: https://github.com/tikipro7/SoftRestaurant_tiki

```bash
cd ~/Downloads/SoftRestaurant_tiki
git pull
xcodegen generate
xcodebuild -project Restaurante.xcodeproj -scheme Restaurante -destination 'generic/platform=iOS' -configuration Release build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

Si el build termina en `** BUILD SUCCEEDED **`, ya está. Si te da un error, pégalo tal cual.

## Hacer el IPA e instalarlo con AltStore

El build solo deja el `.app` en DerivedData; el `.ipa` se hace con Payload + zip. **Ojo: usa la carpeta exacta de DerivedData de ese día** (hay varias carpetas `Restaurante-*`; el comodín `Restaurante-*` copia la vieja y el IPA sale de 127K, el viejo):

```bash
cd ~/Downloads/SoftRestaurant_tiki
ls ~/Library/Developer/Xcode/DerivedData/Restaurante-*/Build/Products/Release-iphoneos/
# copia con la ruta EXACTA que salió (ej. Restaurante-bynybdxffsqmvggjknisnldexnju):
mkdir -p Payload
cp -R ~/Library/Developer/Xcode/DerivedData/Restaurante-bynybdxffsqmvggjknisnldexnju/Build/Products/Release-iphoneos/Restaurante.app Payload/
zip -r Restaurante.ipa Payload
ls -lh Restaurante.ipa
```

El IPA nuevo pesa ~421K (no 127K). **Borra la app vieja del iPhone** e instala el IPA nuevo con **AltStore Classic** (AltStore lo firma con tu Apple ID al instalar).

## Probar en tu iPhone (sin IPA)

```bash
cd ~/Downloads/SoftRestaurant_tiki
xcodegen generate
open Restaurante.xcodeproj
```

En Xcode: elige tu iPhone arriba, elige tu equipo (Team) en Signing & Capabilities, dale Run.

## Cambiar el menú / mesas

- Sin compilar: usa **Importar CSV** en Menú / Inventario (ver ejemplos arriba), o Editar/Agregar en la app.
- Con código: edita `Sources/Restaurante/App.swift`, en la función `semilla()` dentro de `DataStore`: ahí están el menú, el inventario inicial y el pedido de ejemplo. Guarda, vuelve a compilar.

## Archivos

- `project.yml` — proyecto xcodegen, target iOS, deploymentTarget 26.0, bundleId `com.tiki.softrestaurant`, permisos de red local (NSLocalNetworkUsageDescription + NSBonjourServices `_tiki-comanda._tcp`) y de cámara (NSCameraUsageDescription, para escanear códigos)
- `Sources/Restaurante/App.swift` — toda la app (modelos, datos, vistas) — ~3,238 líneas
- `ExportOptions.plist` — exportar IPA
- `PASOS.md` — pasos cortos
- `README.md` — este archivo

## Aviso

Este proyecto **no se compiló en esta máquina**: aquí no hay Xcode ni Mac, solo se verificó sintaxis básica (llaves 847/847, paréntesis 2476/2476, corchetes 257/257, sin structs duplicados, sin `foregroundStyle(.pos…)` sin `Color.`). La primera compilación real de esta versión es en tu Mac con los comandos de arriba.
