# Bar — PASOS

App para iPhone, lado del staff del bar. Mesas, Menú, Barra, Cocina, Caja, Inventario, Ventas, Clientes, Reportes, Mi negocio, Red local. Sin A domicilio (solo En mesa y Para llevar) y sin pestaña Cliente (desactivada por ahora). Diseño estilo Loyverse POS: encabezado con gradiente, tarjetas con sombra, colores por estado, botones grandes, modo claro forzado.

## 1. Compilar y hacer el IPA

1. En tu Mac, en la carpeta del repo:
   ```bash
   cd ~/Downloads/SoftRestaurant_tiki
   git pull
   xcodegen generate
   xcodebuild -project Restaurante.xcodeproj -scheme Restaurante -destination 'generic/platform=iOS' -configuration Release build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
   ```
2. Si sale `** BUILD SUCCEEDED **`, haz el IPA con la carpeta **exacta** de DerivedData de ese día (el comodín `Restaurante-*` copia la app vieja y el IPA sale de 127K):
   ```bash
   ls ~/Library/Developer/Xcode/DerivedData/Restaurante-*/Build/Products/Release-iphoneos/
   mkdir -p Payload
   cp -R ~/Library/Developer/Xcode/DerivedData/Restaurante-bynybdxffsqmvggjknisnldexnju/Build/Products/Release-iphoneos/Restaurante.app Payload/
   zip -r Restaurante.ipa Payload
   ls -lh Restaurante.ipa
   ```
   El IPA nuevo pesa ~421K. Borra la app vieja del iPhone e instala el nuevo con **AltStore Classic**.

## 2. Flujo: tocar mesa → agregar → cerrar

3. **Mesas:** toca una mesa y se abre su comanda: estado, mesero, total y pedidos. Dale a **"➕ Agregar a la cuenta"** y toca productos: la cuenta **queda abierta**, se le puede seguir agregando.
4. **Cantidad:** cada línea del pedido tiene **− cantidad +** grande: **+** suma uno, **−** quita uno, y si llega a **0** el producto sale de la cuenta. Está en el carrito de Menú, en Mesas, en Barra y en Cocina.
5. **Cuentas abiertas y fusionar:** en Mesas, sección **"Cuentas abiertas"**: total y botón Abrir. Para juntar mesas, elige 2 o más y dale a **"🔗 Fusionar en una cuenta"**. Para mover una mesa a otra cuenta, usa el selector en el detalle de la mesa.
6. **Barra y Cocina:** al enviar, las bebidas van a **Barra** y la comida a **Cocina**, solas por categoría. En cada pedido de Barra/Cocina hay botón **"➕ Agregar"** para sumarle más a ese pedido sin volver a Mesas.
7. **Mesero:** en el detalle de la mesa elige el mesero; en **Mi negocio → "Meseros del bar"** agregas meseros nuevos por nombre. La tarjeta de la mesa muestra 👤 el mesero (o "Sin mesero") y sale también en el ticket.
8. **Cerrar cuenta:** solo cuando tú decidas: botón **"🧾 Cerrar cuenta"** en el detalle de la mesa. Elige propina (0/10/15/20% o manual), descuento y forma de pago, confirma. La mesa queda libre y se registra en Ventas del día.
9. **Ticket:** al cerrar sale el ticket (logo, mesa, mesero, productos, subtotal, propina, total). **"Compartir ticket"** o **"Imprimir ticket"** (Bluetooth/AirPrint, papel 58mm/80mm, tamaño de logo en Mi negocio).

## 3. Menú e inventario por CSV

10. **Importar menú:** en Menú, **"📥 Importar CSV"**, elige el archivo `.csv`. Formato `Nombre,Precio,Categoria,Codigo`. Ejemplo (`menu.csv`):
    ```csv
    nombre,precio,categoria,codigo
    Mojito,120,Cocteles,MOJ01
    Margarita,120,Cocteles,MAR01
    Cerveza Corona 355 ml,45,Cervezas,COR01
    Michelada,65,Cervezas,MIC01
    Tequila shot,60,Shots,TEQ01
    Whisky (copa),110,Destilados,WHI01
    Alitas BBQ (6),110,Botanas,ALI01
    Nachos con queso,95,Botanas,NAC01
    Papas a la francesa,60,Botanas,PAP01
    Refresco 600 ml,30,Bebidas,REF01
    ```
    Categorías **Cervezas, Cocteles, Destilados, Shots, Bebidas → Barra**; **Botanas, Comida → Cocina**.
11. **Importar inventario:** en Inventario, **"📥 Importar CSV"**. Formato `Nombre,Unidad,Stock,Minimo`. Ejemplo (`inventario.csv`):
    ```csv
    nombre,unidad,stock,minimo
    Cerveza Corona,pzas,48,12
    Ron blanco,botella,12,2
    Tequila,botella,8,2
    Limones,kg,5,1
    Alitas,kg,10,2
    Hielo,kg,20,5
    Refresco,pzas,24,6
    ```
12. Al importar **no se duplica por nombre**: si ya existe se actualiza, si no se agrega. Te dice cuántos se agregaron, cuántos se actualizaron y los errores por línea.
13. **Exportar:** en Menú e Inventario, **"📤 Exportar CSV"** (ShareLink). En Reportes, exportar ventas a CSV.
14. **Editar / eliminar:** en Menú, cada producto tiene **"✏️ Editar"** (nombre, precio, categoría, código, Barra/Cocina) y **"🗑️ Eliminar"**, más **"➕ Agregar"**. En Inventario, **"✏️ Editar"** (nombre, unidad, stock, mínimo) y **"🗑️ Eliminar"**, más el formulario para agregar.

## 4. Teclado

15. En cualquier campo de texto o número, arriba del teclado sale una barra con botón **"Listo"** que lo cierra. También se cierra al **tocar fuera del campo**. Si se te atora el teclado numérico en Inventario, dale a **Listo**.

## 5. Lo demás

16. **Caja:** fondo inicial, entradas/salidas de efectivo con concepto, y corte de caja por forma de pago.
17. **Clientes y lealtad:** pestaña Clientes: registra por nombre/teléfono, 1 punto por cada $20 al cobrar. Toca un cliente para ver su historial.
18. **Reportes:** ventas de hoy y de 7 días, venta promedio, por forma de pago, lo más vendido, exportar ventas a CSV.
19. **Devoluciones:** en Ventas, en cada pedido cobrado, escribe el motivo y dale a "Devolver". Ya no suma en ventas.
20. **Descuentos:** en Menú y al cerrar cuenta, en % o en $, salen en el ticket y en Ventas.
21. **Escanear código:** en Menú, "Escanear código" abre la cámara y busca el producto por su código; o escríbelo en "Código manual".
22. **Variantes:** en Menú, escribe la variante antes de agregar (ej. "Doble, sin hielo").
23. **Mi negocio:** nombre del bar, dirección, teléfono, logo de la galería, papel (58mm/80mm), tamaño del logo y meseros del bar.
24. **Red local (varios iPhones por WiFi):** en cada iPhone, pestaña "Red local" → Encender red local. Mismo WiFi, WiFi y Bluetooth prendidos, acepta el permiso de red local. En uno, toca Conectar en el otro iPhone. Crea un pedido en un iPhone: tiene que aparecer en Barra/Cocina del otro.

## 6. Si algo falla

25. Si el build falla, pega el error tal cual (las primeras líneas del error, con el archivo y la línea, ej. `App.swift:123:45: error: ...`).
26. Si instalaste el IPA y se ve la versión vieja: borra la app del iPhone, revisa que el IPA pese ~421K (no 127K) y que la carpeta de DerivedData que copiaste sea la del build de hoy.
