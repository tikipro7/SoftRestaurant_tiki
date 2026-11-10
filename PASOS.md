# Restaurante — PASOS

App tipo Soft Restaurant para iPhone. Mesas, comanda, cocina, inventario, ventas y pedido del cliente.

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
