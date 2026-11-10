# Restaurante — PASOS

App tipo Soft Restaurant para iPhone. Mesas, comanda, cocina, inventario, ventas y pedido del cliente. Diseño estilo Loyverse POS: encabezado con gradiente, tarjetas con sombra, colores por estado, botones grandes.

1. Copia esta carpeta a tu Mac: `~/restaurante-ios`
2. En terminal, compila:
   ```bash
   cd ~/restaurante-ios
   xcodegen generate
   xcodebuild -project Restaurante.xcodeproj -scheme Restaurante -destination 'generic/platform=iOS' -configuration Release build
   ```
3. Para probar en tu iPhone: en Xcode, abre el proyecto, elige tu iPhone y dale Run.
4. Para IPA (AltStore): primero archiva, luego exporta con `ExportOptions.plist` (ver README.md).
5. Los datos se guardan solos en el iPhone, en `restaurante.json` dentro de Documents. Sin servidor, sin cuenta.

Cambiar el menú: edita `Sources/Restaurante/App.swift`, en `semilla()`, y vuelve a compilar.

## Cerrar cuenta, ticket e impresora
6. En Mesas, toca una mesa ocupada y dale a "Cerrar cuenta": elige propina (0/10/15/20% o manual), revisa el total y confirma. La mesa queda libre.
7. Al cerrar sale el ticket: logo, nombre, dirección, fecha, mesa, mesero, platillos, subtotal, propina y total. Dale a "Compartir ticket" o a "Imprimir ticket".
8. Pon tu logo en la pestaña "Mi negocio": nombre, dirección, teléfono y "Elegir logo de la galería". Ahí también eliges papel (58mm / 80mm) y tamaño del logo.

## Impresora Bluetooth (térmica genérica)
- La app imprime con AirPrint (`UIPrintInteractionController`): agarra cualquier impresora que iOS reconozca como AirPrint / Bluetooth compatible, sin depender de una marca.
- El ticket se genera como imagen, con el logo centrado y ajustado al ancho del papel (58mm = 384 puntos, 80mm = 576 puntos), para que no salga cortado ni chiquito.
- Si tu térmica Bluetooth genérica no aparece en AirPrint, usa la app del fabricante de tu impresora y comparte el ticket desde "Compartir ticket" (texto) o toma captura del ticket en pantalla.

## Funciones estilo Loyverse (y más)
12. **Descuentos:** en Menú, al armar el pedido, y en Cerrar cuenta: descuento en % o en $, se reparte entre los pedidos de la mesa y sale en el ticket y en Ventas.
13. **Devoluciones:** en Ventas, en cada pedido cobrado, escribe el motivo y dale a "Devolver". Queda marcado, ya no suma en ventas, y se ve en la sección Devoluciones.
14. **Caja:** pestaña Caja: fondo inicial, entradas/salidas de efectivo con concepto, y corte de caja con total por pago (efectivo / tarjeta / transferencia) y efectivo en caja.
15. **Clientes y lealtad:** pestaña Clientes: registra por nombre/teléfono, 1 punto por cada $20 al cobrar. Toca un cliente para ver su historial y sus pedidos.
16. **Reportes:** pestaña Reportes: ventas de hoy y de 7 días, venta promedio, por forma de pago, lo más vendido, y exportar ventas a CSV (Excel) con "Exportar ventas a CSV".
17. **En mesa / para llevar / a domicilio:** en Menú y en Cliente, elige el tipo. A domicilio pide dirección y teléfono, y Cocina lo muestra con 📍.
18. **Inventario CSV:** en Inventario, "Exportar inventario a CSV" y "Importar CSV" pegando líneas `Nombre,unidad,stock,minimo`.
19. **Escanear código:** en Menú, "Escanear código" abre la cámara (acepta el permiso la primera vez) y busca el platillo por su código; o escríbelo en "Código manual". Para que un platillo tenga código, edítalo en `semilla()` con `codigo: "7501234567890"`.
20. **Cocina por estado:** Cocina ahora muestra Pendiente / En cocina / Listo por separado, con el tiempo que lleva cada pedido (⏱ min, en rojo si lleva 15 min o más).
21. **Variantes:** en Menú, escribe la variante antes de agregar (ej. "Grande, sin cebolla") y sale en el pedido y en cocina.

## Red local (varios iPhones por WiFi)
9. En cada iPhone: pestaña "Red local" → Encender red local. Acepta el permiso de red local la primera vez.
10. Todos en el mismo WiFi, con WiFi y Bluetooth prendidos. En uno, toca Conectar en el otro iPhone.
11. Crea un pedido en un iPhone: tiene que aparecer en Cocina del otro. Si cocina marca Listo, el mesero lo ve. Si no se ven, revisa el permiso en Ajustes del iPhone → Restaurante → Red local.
