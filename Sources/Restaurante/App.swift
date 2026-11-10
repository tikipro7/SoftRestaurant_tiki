import SwiftUI
import Foundation
import PhotosUI
import UIKit

// Restaurante — app tipo Soft Restaurant para iPhone.
// Para el restaurante: mesas, comandas, cocina, inventario y ventas.
// Para el cliente: pedir desde su iPhone (pestaña Cliente).
// Sin servidor: todo se guarda en local, en un JSON en Documents.

@main
struct RestauranteApp: App {
    @StateObject private var store = DataStore()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

// MARK: - Modelos

struct MenuItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var nombre: String
    var precio: Double
    var categoria: String
}

struct InventarioItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var nombre: String
    var unidad: String
    var stock: Double
    var minimo: Double
    var bajoStock: Bool { stock <= minimo }
}

struct PedidoItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var nombre: String
    var precio: Double
    var cantidad: Int
    var subtotal: Double { precio * Double(cantidad) }
}

enum EstadoPedido: String, Codable, CaseIterable {
    case pendiente = "pendiente"
    case cocina = "cocina"
    case listo = "listo"
    case cobrado = "cobrado"
    var titulo: String {
        switch self {
        case .pendiente: return "Pendiente"
        case .cocina: return "En cocina"
        case .listo: return "Listo"
        case .cobrado: return "Cobrado"
        }
    }
    var siguiente: EstadoPedido? {
        switch self {
        case .pendiente: return .cocina
        case .cocina: return .listo
        case .listo: return .cobrado
        case .cobrado: return nil
        }
    }
}

struct Pedido: Identifiable, Codable, Equatable {
    var id = UUID()
    var numero: Int
    var mesa: String // "Mesa 3", "Para llevar" o "Cliente"
    var tipo: String // "Mesa", "Para llevar", "Cliente"
    var items: [PedidoItem]
    var estado: EstadoPedido
    var fecha: Date = Date()
    var propina: Double = 0
    var mesero: String = "Mesero"
    var total: Double { items.reduce(0) { $0 + $1.subtotal } }
    var totalConPropina: Double { total + propina }
}

// Compatibilidad con restaurante.json viejo (sin propina/mesero)
extension Pedido {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        numero = try c.decodeIfPresent(Int.self, forKey: .numero) ?? 0
        mesa = try c.decodeIfPresent(String.self, forKey: .mesa) ?? ""
        tipo = try c.decodeIfPresent(String.self, forKey: .tipo) ?? "Mesa"
        items = try c.decodeIfPresent([PedidoItem].self, forKey: .items) ?? []
        estado = try c.decodeIfPresent(EstadoPedido.self, forKey: .estado) ?? .pendiente
        fecha = try c.decodeIfPresent(Date.self, forKey: .fecha) ?? Date()
        propina = try c.decodeIfPresent(Double.self, forKey: .propina) ?? 0
        mesero = try c.decodeIfPresent(String.self, forKey: .mesero) ?? "Mesero"
    }
}


// MARK: - Mi negocio y ticket

struct Negocio: Codable, Equatable {
    var nombre: String = "Mi Restaurante"
    var direccion: String = ""
    var telefono: String = ""
    var mesero: String = "Mesero"
    var logoData: Data? = nil
    // Impresora de tickets: papel térmico 58mm o 80mm, logo pequeño/mediano/grande.
    var papel: String = "80mm"
    var tamanoLogo: String = "mediano"
}

// Compatibilidad con restaurante.json viejo (sin papel/tamanoLogo)
extension Negocio {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nombre = try c.decodeIfPresent(String.self, forKey: .nombre) ?? "Mi Restaurante"
        direccion = try c.decodeIfPresent(String.self, forKey: .direccion) ?? ""
        telefono = try c.decodeIfPresent(String.self, forKey: .telefono) ?? ""
        mesero = try c.decodeIfPresent(String.self, forKey: .mesero) ?? "Mesero"
        logoData = try c.decodeIfPresent(Data.self, forKey: .logoData)
        papel = try c.decodeIfPresent(String.self, forKey: .papel) ?? "80mm"
        tamanoLogo = try c.decodeIfPresent(String.self, forKey: .tamanoLogo) ?? "mediano"
    }
}

/// Ancho del ticket en puntos según el papel térmico elegido.
func anchoPapel(_ papel: String) -> CGFloat { papel == "58mm" ? 384 : 576 }
/// Alto del logo en el ticket según el tamaño elegido.
func altoLogo(_ tamano: String) -> CGFloat {
    switch tamano {
    case "pequeño": return 60
    case "grande": return 160
    default: return 110
    }
}

/// Dibuja el ticket como imagen, con el logo centrado y ajustado al ancho
/// del papel (58mm o 80mm). Así se imprime bien en cualquier impresora
/// térmica, sin depender de la marca.
func imagenTicket(_ ticket: Ticket, negocio: Negocio) -> UIImage {
    let ancho = anchoPapel(negocio.papel)
    let altoLogoImg = altoLogo(negocio.tamanoLogo)
    let lineas = textoTicket(ticket, negocio: negocio).components(separatedBy: "\n")
    let fuente = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    let fuenteNegrita = UIFont.monospacedSystemFont(ofSize: 16, weight: .bold)
    let altoTexto = CGFloat(lineas.count) * 20 + 20
    let alto = altoLogoImg + altoTexto + 20
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: ancho, height: alto))
    return renderer.image { ctx in
        UIColor.white.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: ancho, height: alto))
        var y: CGFloat = 10
        if let data = negocio.logoData, let logo = UIImage(data: data) {
            // Logo centrado, ajustado al ancho del papel, sin deformar.
            let escala = min(1, (ancho - 40) / logo.size.width)
            let w = logo.size.width * escala
            let h = min(altoLogoImg, logo.size.height * escala)
            logo.draw(in: CGRect(x: (ancho - w) / 2, y: y, width: w, height: h))
            y += h + 10
        }
        let parrafo = NSMutableParagraphStyle()
        parrafo.alignment = .center
        for (i, linea) in lineas.enumerated() {
            let esTotal = linea.hasPrefix("TOTAL:")
            let attrs: [NSAttributedString.Key: Any] = [
                .font: esTotal ? fuenteNegrita : fuente,
                .foregroundColor: UIColor.black,
                .paragraphStyle: parrafo
            ]
            let texto = NSAttributedString(string: linea, attributes: attrs)
            texto.draw(in: CGRect(x: 10, y: y, width: ancho - 20, height: 20))
            y += 20
            _ = i
        }
    }
}

/// Imprime el ticket con UIPrintInteractionController (AirPrint).
/// Agarra cualquier impresora compatible con AirPrint / Bluetooth que
/// iOS reconozca, sin depender de una marca. Para térmicas genéricas
/// Bluetooth sin AirPrint, usa la app del fabricante y comparte la
/// imagen del ticket.
func imprimirTicket(_ ticket: Ticket, negocio: Negocio) {
    let imagen = imagenTicket(ticket, negocio: negocio)
    let info = UIPrintInfo(dictionary: nil)
    info.jobName = "Ticket #\(ticket.numero) - \(negocio.nombre)"
    info.outputType = .general
    let controlador = UIPrintInteractionController.shared
    controlador.printInfo = info
    controlador.printingItem = imagen
    controlador.present(animated: true, completionHandler: nil)
}

struct Ticket: Identifiable, Equatable {
    var id = UUID()
    var numero: Int
    var mesa: String
    var mesero: String
    var fecha: Date
    var items: [PedidoItem]
    var subtotal: Double
    var propina: Double
    var total: Double { subtotal + propina }
}

func textoTicket(_ ticket: Ticket, negocio: Negocio) -> String {
    var lineas: [String] = []
    lineas.append(negocio.nombre)
    if !negocio.direccion.isEmpty { lineas.append(negocio.direccion) }
    if !negocio.telefono.isEmpty { lineas.append("Tel. \(negocio.telefono)") }
    lineas.append("--------------------------------")
    let f = DateFormatter()
    f.dateStyle = .short; f.timeStyle = .short
    lineas.append("Fecha: \(f.string(from: ticket.fecha))")
    lineas.append("\(ticket.mesa) · Mesero: \(ticket.mesero)")
    lineas.append("Ticket #\(ticket.numero)")
    lineas.append("--------------------------------")
    for item in ticket.items {
        lineas.append("\(item.cantidad) x \(item.nombre)  \(mxn(item.subtotal))")
    }
    lineas.append("--------------------------------")
    lineas.append("Subtotal: \(mxn(ticket.subtotal))")
    lineas.append("Propina:  \(mxn(ticket.propina))")
    lineas.append("TOTAL:    \(mxn(ticket.total))")
    lineas.append("")
    lineas.append("¡Gracias por su visita!")
    return lineas.joined(separator: "\n")
}

// MARK: - Datos (persistencia local en JSON)

struct DatosGuardados: Codable {
    var menu: [MenuItem]
    var inventario: [InventarioItem]
    var pedidos: [Pedido]
    var siguienteNumero: Int
    var negocio: Negocio = Negocio()
}

// Compatibilidad con restaurante.json viejo (sin negocio)
extension DatosGuardados {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        menu = try c.decodeIfPresent([MenuItem].self, forKey: .menu) ?? []
        inventario = try c.decodeIfPresent([InventarioItem].self, forKey: .inventario) ?? []
        pedidos = try c.decodeIfPresent([Pedido].self, forKey: .pedidos) ?? []
        siguienteNumero = try c.decodeIfPresent(Int.self, forKey: .siguienteNumero) ?? 1
        negocio = try c.decodeIfPresent(Negocio.self, forKey: .negocio) ?? Negocio()
    }
}

final class DataStore: ObservableObject {
    @Published var menu: [MenuItem] = []
    @Published var inventario: [InventarioItem] = []
    @Published var pedidos: [Pedido] = []
    @Published var siguienteNumero: Int = 1
    @Published var negocio: Negocio = Negocio()

    private var archivo: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("restaurante.json")
    }

    init() { cargar() }

    var ventasDelDia: Double {
        pedidos.filter { $0.estado == .cobrado }.reduce(0) { $0 + $1.totalConPropina }
    }
    var propinasDelDia: Double {
        pedidos.filter { $0.estado == .cobrado }.reduce(0) { $0 + $1.propina }
    }
    var pedidosActivos: [Pedido] {
        pedidos.filter { $0.estado != .cobrado }
    }
    func pedidosDeMesa(_ mesa: String) -> [Pedido] {
        pedidos.filter { $0.mesa == mesa && $0.estado != .cobrado }
    }
    func mesaOcupada(_ numero: Int) -> Bool {
        !pedidosDeMesa("Mesa \(numero)").isEmpty
    }

    func crearPedido(mesa: String, tipo: String, items: [PedidoItem]) {
        guard !items.isEmpty else { return }
        let pedido = Pedido(numero: siguienteNumero, mesa: mesa, tipo: tipo, items: items, estado: .pendiente)
        siguienteNumero += 1
        pedidos.append(pedido)
        // Descontar inventario simple: 1 unidad por cada producto vendido, si coincide el nombre.
        for item in items {
            if let i = inventario.firstIndex(where: { $0.nombre.lowercased() == item.nombre.lowercased() }) {
                inventario[i].stock = max(0, inventario[i].stock - Double(item.cantidad))
            }
        }
        guardar()
    }

    func avanzar(_ pedido: Pedido) {
        guard let i = pedidos.firstIndex(of: pedido), let sig = pedido.estado.siguiente else { return }
        pedidos[i].estado = sig
        guardar()
    }

    func cobrar(_ pedido: Pedido) { cobrar(pedido, propina: 0, mesero: negocio.mesero) }

    /// Cobra un pedido con propina. Guarda la propina y el mesero en el pedido.
    func cobrar(_ pedido: Pedido, propina: Double, mesero: String) {
        guard let i = pedidos.firstIndex(of: pedido) else { return }
        pedidos[i].estado = .cobrado
        pedidos[i].propina = propina
        pedidos[i].mesero = mesero
        guardar()
    }

    /// Ticket (sin cobrar) de una mesa: todos sus pedidos activos juntos.
    func ticketParaMesa(_ mesa: String) -> Ticket? {
        let lista = pedidosDeMesa(mesa)
        guard !lista.isEmpty else { return nil }
        let items = lista.flatMap { $0.items }
        let subtotal = lista.reduce(0) { $0 + $1.total }
        return Ticket(numero: lista.first!.numero, mesa: mesa, mesero: negocio.mesero,
                      fecha: Date(), items: items, subtotal: subtotal, propina: 0)
    }

    /// Cierra la cuenta de una mesa: reparte la propina entre sus pedidos,
    /// los marca como Cobrado, deja la mesa libre y devuelve el ticket.
    func cerrarMesa(_ mesa: String, propina: Double, mesero: String) -> Ticket? {
        guard let ticket = ticketParaMesa(mesa) else { return nil }
        let lista = pedidosDeMesa(mesa)
        let subtotal = ticket.subtotal
        for pedido in lista {
            let parte = subtotal > 0 ? propina * (pedido.total / subtotal) : 0
            cobrar(pedido, propina: parte, mesero: mesero)
        }
        var ticketFinal = ticket
        ticketFinal.propina = propina
        ticketFinal.mesero = mesero
        return ticketFinal
    }

    func guardarNegocio() { guardar() }

    func cambiarStock(_ item: InventarioItem, delta: Double) {
        guard let i = inventario.firstIndex(of: item) else { return }
        inventario[i].stock = max(0, inventario[i].stock + delta)
        guardar()
    }

    func agregarInventario(nombre: String, unidad: String, stock: Double, minimo: Double) {
        inventario.append(InventarioItem(nombre: nombre, unidad: unidad, stock: stock, minimo: minimo))
        guardar()
    }

    func guardar() {
        let datos = DatosGuardados(menu: menu, inventario: inventario, pedidos: pedidos, siguienteNumero: siguienteNumero, negocio: negocio)
        if let data = try? JSONEncoder().encode(datos) {
            try? data.write(to: archivo)
        }
    }

    private func cargar() {
        if let data = try? Data(contentsOf: archivo),
           let datos = try? JSONDecoder().decode(DatosGuardados.self, from: data) {
            menu = datos.menu
            inventario = datos.inventario
            pedidos = datos.pedidos
            siguienteNumero = datos.siguienteNumero
            negocio = datos.negocio
            return
        }
        semilla()
    }

    private func semilla() {
        menu = [
            MenuItem(nombre: "Tacos al pastor (3)", precio: 75, categoria: "Tacos"),
            MenuItem(nombre: "Tacos de carnitas (3)", precio: 80, categoria: "Tacos"),
            MenuItem(nombre: "Tacos de barbacoa (3)", precio: 85, categoria: "Tacos"),
            MenuItem(nombre: "Quesadilla de queso", precio: 45, categoria: "Tacos"),
            MenuItem(nombre: "Enchiladas verdes (3)", precio: 95, categoria: "Platos"),
            MenuItem(nombre: "Pozole rojo", precio: 110, categoria: "Platos"),
            MenuItem(nombre: "Mole poblano con pollo", precio: 120, categoria: "Platos"),
            MenuItem(nombre: "Sopa de tortilla", precio: 70, categoria: "Entradas"),
            MenuItem(nombre: "Guacamole", precio: 65, categoria: "Entradas"),
            MenuItem(nombre: "Refresco 600 ml", precio: 30, categoria: "Bebidas"),
            MenuItem(nombre: "Agua de horchata 1 L", precio: 35, categoria: "Bebidas"),
            MenuItem(nombre: "Cerveza", precio: 45, categoria: "Bebidas"),
            MenuItem(nombre: "Flan napolitano", precio: 40, categoria: "Postres"),
            MenuItem(nombre: "Churros con chocolate", precio: 50, categoria: "Postres"),
        ]
        inventario = [
            InventarioItem(nombre: "Tortillas", unidad: "kg", stock: 12, minimo: 5),
            InventarioItem(nombre: "Carne al pastor", unidad: "kg", stock: 8, minimo: 3),
            InventarioItem(nombre: "Carnitas", unidad: "kg", stock: 4, minimo: 3),
            InventarioItem(nombre: "Queso", unidad: "kg", stock: 2, minimo: 3),
            InventarioItem(nombre: "Refresco 600 ml", unidad: "pzas", stock: 24, minimo: 12),
            InventarioItem(nombre: "Cerveza", unidad: "pzas", stock: 18, minimo: 12),
            InventarioItem(nombre: "Aguacate", unidad: "kg", stock: 3, minimo: 2),
            InventarioItem(nombre: "Maíz pozolero", unidad: "kg", stock: 6, minimo: 4),
        ]
        pedidos = [
            Pedido(numero: 1, mesa: "Mesa 2", tipo: "Mesa",
                   items: [PedidoItem(nombre: "Tacos al pastor (3)", precio: 75, cantidad: 2),
                           PedidoItem(nombre: "Refresco 600 ml", precio: 30, cantidad: 2)],
                   estado: .cocina),
        ]
        siguienteNumero = 2
        guardar()
    }
}

func mxn(_ valor: Double) -> String {
    String(format: "$%.2f MXN", valor)
}

// MARK: - Vista principal

struct ContentView: View {
    var body: some View {
        TabView {
            MesasView()
                .tabItem { Label("Mesas", systemImage: "table.furniture") }
            MenuView()
                .tabItem { Label("Menú", systemImage: "menucard") }
            CocinaView()
                .tabItem { Label("Cocina", systemImage: "flame") }
            InventarioView()
                .tabItem { Label("Inventario", systemImage: "shippingbox") }
            VentasView()
                .tabItem { Label("Ventas", systemImage: "banknote") }
            ClienteView()
                .tabItem { Label("Cliente", systemImage: "person") }
            NegocioView()
                .tabItem { Label("Mi negocio", systemImage: "storefront") }
        }
    }
}

// MARK: - Mesas (1 a 8)

struct MesasView: View {
    @EnvironmentObject var store: DataStore
    @State private var mesaSeleccionada: Int = 1
    @State private var mostrarCerrar = false
    @State private var ticketCerrado: Ticket? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("1. Toca una mesa  2. Revisa su cuenta  3. Cierra y cobra")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 12) {
                    ForEach(1...8, id: \.self) { n in
                        Button {
                            mesaSeleccionada = n
                        } label: {
                            VStack {
                                Text("Mesa \(n)").font(.headline)
                                Text(store.mesaOcupada(n) ? "Ocupada" : "Libre")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity, minHeight: 84)
                            .background(store.mesaOcupada(n) ? Color.orange.opacity(0.25) : Color.green.opacity(0.2))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(mesaSeleccionada == n ? Color.blue : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                List {
                    Section("Mesa \(mesaSeleccionada)") {
                        let lista = store.pedidosDeMesa("Mesa \(mesaSeleccionada)")
                        if lista.isEmpty {
                            Text("Sin comanda. Agrega platillos en la pestaña Menú.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(lista) { pedido in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Pedido #\(pedido.numero) · \(pedido.estado.titulo)")
                                    .font(.headline)
                                ForEach(pedido.items) { item in
                                    Text("\(item.cantidad) × \(item.nombre) — \(mxn(item.subtotal))")
                                }
                                Text("Total: \(mxn(pedido.total))").bold()
                            }
                            .padding(.vertical, 4)
                        }
                        if !lista.isEmpty {
                            let subtotal = lista.reduce(0) { $0 + $1.total }
                            Text("Cuenta total: \(mxn(subtotal))").font(.title3).bold()
                            Button("🧾 Cerrar cuenta") { mostrarCerrar = true }
                                .font(.title3).bold()
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .navigationTitle("Mesas")
            .sheet(isPresented: $mostrarCerrar) {
                CerrarCuentaView(mesa: "Mesa \(mesaSeleccionada)") { ticket in
                    ticketCerrado = ticket
                }
            }
            .sheet(item: $ticketCerrado) { ticket in
                TicketView(ticket: ticket)
            }
        }
    }
}

// MARK: - Menú / Comanda

struct MenuView: View {
    @EnvironmentObject var store: DataStore
    @State private var mesa: Int = 1
    @State private var carrito: [PedidoItem] = []
    @State private var mensaje = ""

    var total: Double { carrito.reduce(0) { $0 + $1.subtotal } }

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Mesa", selection: $mesa) {
                    ForEach(1...8, id: \.self) { n in Text("Mesa \(n)").tag(n) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                List {
                    ForEach(Array(Dictionary(grouping: store.menu, by: { $0.categoria }).keys.sorted()), id: \.self) { cat in
                        Section(cat) {
                            ForEach(store.menu.filter { $0.categoria == cat }) { plato in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(plato.nombre)
                                        Text(mxn(plato.precio)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Agregar") { agregar(plato) }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }

                if !carrito.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(carrito) { item in
                            HStack {
                                Text("\(item.cantidad) × \(item.nombre)")
                                Spacer()
                                Text(mxn(item.subtotal))
                            }
                            .font(.callout)
                        }
                        Text("Total: \(mxn(total))").bold()
                        Button("Enviar a cocina — Mesa \(mesa)") {
                            store.crearPedido(mesa: "Mesa \(mesa)", tipo: "Mesa", items: carrito)
                            mensaje = "Pedido enviado a cocina."
                            carrito = []
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        if !mensaje.isEmpty {
                            Text(mensaje).font(.callout).foregroundStyle(.green)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                }
            }
            .navigationTitle("Menú / Comanda")
        }
    }

    private func agregar(_ plato: MenuItem) {
        if let i = carrito.firstIndex(where: { $0.nombre == plato.nombre }) {
            carrito[i].cantidad += 1
        } else {
            carrito.append(PedidoItem(nombre: plato.nombre, precio: plato.precio, cantidad: 1))
        }
        mensaje = ""
    }
}

// MARK: - Cocina

struct CocinaView: View {
    @EnvironmentObject var store: DataStore
    var body: some View {
        NavigationStack {
            List {
                ForEach(store.pedidosActivos) { pedido in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Pedido #\(pedido.numero) · \(pedido.mesa)")
                                .font(.headline)
                            Spacer()
                            Text(pedido.estado.titulo)
                                .font(.caption).bold()
                                .padding(6)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(8)
                        }
                        ForEach(pedido.items) { item in
                            Text("\(item.cantidad) × \(item.nombre)")
                        }
                        if let sig = pedido.estado.siguiente {
                            Button(sig == .cobrado ? "Marcar cobrado" : "Pasar a \(sig.titulo)") {
                                store.avanzar(pedido)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if store.pedidosActivos.isEmpty {
                    Text("No hay pedidos en cocina.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Cocina")
        }
    }
}

// MARK: - Inventario

struct InventarioView: View {
    @EnvironmentObject var store: DataStore
    @State private var nombre = ""
    @State private var unidad = "kg"
    @State private var stockTexto = ""
    @State private var minimoTexto = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Alertas de bajo stock") {
                    let bajos = store.inventario.filter { $0.bajoStock }
                    if bajos.isEmpty {
                        Text("Todo bien, nada en bajo stock.").foregroundStyle(.secondary)
                    }
                    ForEach(bajos) { item in
                        Text("⚠️ \(item.nombre): \(item.stock, specifier: "%.0f") \(item.unidad) (mínimo \(item.minimo, specifier: "%.0f"))")
                            .foregroundStyle(.red)
                    }
                }
                Section("Productos") {
                    ForEach(store.inventario) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.nombre).font(.headline)
                                Text("\(item.stock, specifier: "%.0f") \(item.unidad) · mínimo \(item.minimo, specifier: "%.0f")")
                                    .font(.caption)
                                    .foregroundStyle(item.bajoStock ? .red : .secondary)
                            }
                            Spacer()
                            Button("-1") { store.cambiarStock(item, delta: -1) }
                                .buttonStyle(.bordered)
                            Button("+1") { store.cambiarStock(item, delta: 1) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                Section("Agregar producto") {
                    TextField("Nombre (ej. Tomate)", text: $nombre)
                    TextField("Unidad (kg / pzas / L)", text: $unidad)
                    TextField("Stock inicial", text: $stockTexto)
                        .keyboardType(.decimalPad)
                    TextField("Mínimo", text: $minimoTexto)
                        .keyboardType(.decimalPad)
                    Button("Agregar al inventario") {
                        guard !nombre.isEmpty,
                              let stock = Double(stockTexto),
                              let minimo = Double(minimoTexto) else { return }
                        store.agregarInventario(nombre: nombre, unidad: unidad, stock: stock, minimo: minimo)
                        nombre = ""; stockTexto = ""; minimoTexto = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Inventario")
        }
    }
}

// MARK: - Ventas del día

struct VentasView: View {
    @EnvironmentObject var store: DataStore
    var body: some View {
        NavigationStack {
            List {
                Section("Hoy") {
                    Text("Total cobrado: \(mxn(store.ventasDelDia))")
                        .font(.title2).bold()
                    Text("Propinas: \(mxn(store.propinasDelDia))")
                    Text("Pedidos cobrados: \(store.pedidos.filter { $0.estado == .cobrado }.count)")
                    Text("Pedidos activos: \(store.pedidosActivos.count)")
                }
                Section("Pedidos cobrados") {
                    let cobrados = store.pedidos.filter { $0.estado == .cobrado }
                    if cobrados.isEmpty {
                        Text("Aún no hay ventas cobradas hoy.").foregroundStyle(.secondary)
                    }
                    ForEach(cobrados) { pedido in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Pedido #\(pedido.numero) · \(pedido.mesa)")
                                Spacer()
                                Text(mxn(pedido.totalConPropina)).bold()
                            }
                            Text("Comida \(mxn(pedido.total)) + propina \(mxn(pedido.propina))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Ventas del día")
        }
    }
}

// MARK: - Cliente (pedido desde su iPhone)

struct ClienteView: View {
    @EnvironmentObject var store: DataStore
    @State private var modo = "Mesa"
    @State private var mesaCliente = 1
    @State private var carrito: [PedidoItem] = []
    @State private var mensaje = ""

    var total: Double { carrito.reduce(0) { $0 + $1.subtotal } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Pide desde tu iPhone. Tu pedido llega directo a cocina.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Picker("¿Dónde estás?", selection: $modo) {
                    Text("En mesa").tag("Mesa")
                    Text("Para llevar").tag("Para llevar")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                if modo == "Mesa" {
                    Picker("Mesa", selection: $mesaCliente) {
                        ForEach(1...8, id: \.self) { n in Text("Mesa \(n)").tag(n) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }
                List {
                    ForEach(store.menu) { plato in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(plato.nombre)
                                Text(mxn(plato.precio)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Agregar") {
                                if let i = carrito.firstIndex(where: { $0.nombre == plato.nombre }) {
                                    carrito[i].cantidad += 1
                                } else {
                                    carrito.append(PedidoItem(nombre: plato.nombre, precio: plato.precio, cantidad: 1))
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                if !carrito.isEmpty {
                    VStack(spacing: 8) {
                        Text("Tu pedido: \(mxn(total))").bold()
                        Button("Enviar mi pedido") {
                            let mesa = modo == "Mesa" ? "Mesa \(mesaCliente)" : "Para llevar"
                            store.crearPedido(mesa: mesa, tipo: "Cliente", items: carrito)
                            mensaje = "¡Pedido enviado! Llega a cocina en un momento."
                            carrito = []
                        }
                        .buttonStyle(.borderedProminent)
                        if !mensaje.isEmpty {
                            Text(mensaje).foregroundStyle(.green).font(.callout)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Pedir (Cliente)")
        }
    }
}

// MARK: - Cerrar cuenta (con propina)

// Botones grandes, 3 pasos claros: revisa, elige propina, cierra.
struct CerrarCuentaView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss
    var mesa: String
    var alCerrar: (Ticket) -> Void
    @State private var porcentaje = 15
    @State private var propinaManual = ""
    @State private var usarManual = false
    @State private var mesero = ""

    var ticketBase: Ticket? { store.ticketParaMesa(mesa) }
    var subtotal: Double { ticketBase?.subtotal ?? 0 }
    var propina: Double {
        if usarManual { return Double(propinaManual) ?? 0 }
        return subtotal * Double(porcentaje) / 100
    }
    var total: Double { subtotal + propina }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let ticket = ticketBase {
                        Text(ticket.mesa).font(.largeTitle).bold()
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(ticket.items) { item in
                                HStack {
                                    Text("\(item.cantidad) × \(item.nombre)")
                                    Spacer()
                                    Text(mxn(item.subtotal))
                                }.font(.title3)
                            }
                        }
                        Text("Subtotal: \(mxn(subtotal))").font(.title2).bold()
                    } else {
                        Text("Esta mesa no tiene cuenta abierta.").foregroundStyle(.secondary)
                    }

                    Text("2. Propina").font(.title2).bold()
                    Picker("Propina", selection: $porcentaje) {
                        Text("Sin propina").tag(0)
                        Text("10%").tag(10)
                        Text("15%").tag(15)
                        Text("20%").tag(20)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: porcentaje) { usarManual = false }
                    Toggle("Otra cantidad", isOn: $usarManual)
                    if usarManual {
                        TextField("Propina en pesos (ej. 25)", text: $propinaManual)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                    }
                    Text("Propina: \(mxn(propina))").font(.title3)

                    Text("3. ¿Quién atiende?").font(.title2).bold()
                    TextField("Mesero", text: $mesero)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)

                    Divider()
                    Text("TOTAL A COBRAR: \(mxn(total))").font(.title).bold()
                    Button("✅ Cerrar cuenta y ver ticket") {
                        let ticket = store.cerrarMesa(mesa, propina: propina, mesero: mesero.isEmpty ? store.negocio.mesero : mesero)
                        if let ticket = ticket {
                            alCerrar(ticket)
                            dismiss()
                        }
                    }
                    .font(.title3).bold()
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .buttonStyle(.borderedProminent)
                    .disabled(ticketBase == nil)
                    Button("Cancelar") { dismiss() }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding()
            }
            .navigationTitle("Cerrar cuenta")
            .onAppear { mesero = store.negocio.mesero }
        }
    }
}

// MARK: - Ticket (con logo del negocio)

struct TicketView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss
    var ticket: Ticket

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    // Logo arriba, si Luis ya puso uno en Mi negocio.
                    if let data = store.negocio.logoData, let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 110)
                            .cornerRadius(12)
                    }
                    Text(store.negocio.nombre).font(.largeTitle).bold()
                        .multilineTextAlignment(.center)
                    if !store.negocio.direccion.isEmpty {
                        Text(store.negocio.direccion).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    if !store.negocio.telefono.isEmpty {
                        Text("Tel. \(store.negocio.telefono)").foregroundStyle(.secondary)
                    }
                    Divider()
                    Text("Fecha: \(fechaTicket(ticket.fecha))")
                    Text("\(ticket.mesa) · Mesero: \(ticket.mesero)")
                    Text("Ticket #\(ticket.numero)")
                    Divider()
                    ForEach(ticket.items) { item in
                        HStack {
                            Text("\(item.cantidad) × \(item.nombre)")
                            Spacer()
                            Text(mxn(item.subtotal))
                        }
                    }
                    Divider()
                    HStack { Text("Subtotal"); Spacer(); Text(mxn(ticket.subtotal)) }
                    HStack { Text("Propina"); Spacer(); Text(mxn(ticket.propina)) }
                    HStack {
                        Text("TOTAL").font(.title2).bold()
                        Spacer()
                        Text(mxn(ticket.total)).font(.title2).bold()
                    }
                    Text("¡Gracias por su visita!").font(.title3).bold().padding(.top, 8)

                    Text("Impresora").font(.title2).bold()
                    Picker("Papel", selection: $store.negocio.papel) {
                        Text("58mm").tag("58mm")
                        Text("80mm").tag("80mm")
                    }
                    .pickerStyle(.segmented)
                    Picker("Logo", selection: $store.negocio.tamanoLogo) {
                        Text("Pequeño").tag("pequeño")
                        Text("Mediano").tag("mediano")
                        Text("Grande").tag("grande")
                    }
                    .pickerStyle(.segmented)
                    Text("El logo sale centrado y ajustado al ancho del papel.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("🖨️ Imprimir ticket") { imprimirTicket(ticket, negocio: store.negocio) }
                        .font(.title3).bold()
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .buttonStyle(.borderedProminent)
                    ShareLink(item: textoTicket(ticket, negocio: store.negocio)) {
                        Label("Compartir ticket", systemImage: "square.and.arrow.up")
                    }
                    .font(.title3).bold()
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .buttonStyle(.borderedProminent)
                    Button("Cerrar") { dismiss() }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding()
            }
            .navigationTitle("Ticket")
        }
    }
    private func fechaTicket(_ fecha: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: fecha)
    }
}

// MARK: - Mi negocio (nombre, datos y logo)

struct NegocioView: View {
    @EnvironmentObject var store: DataStore
    @State private var foto: PhotosPickerItem? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Tu restaurante") {
                    Text("Esto es lo que sale arriba del ticket.")
                        .font(.callout).foregroundStyle(.secondary)
                    TextField("Nombre del restaurante", text: $store.negocio.nombre)
                        .font(.title3)
                    TextField("Dirección", text: $store.negocio.direccion)
                    TextField("Teléfono", text: $store.negocio.telefono)
                        .keyboardType(.phonePad)
                    TextField("Mesero por defecto", text: $store.negocio.mesero)
                }
                Section("Logo del ticket") {
                    if let data = store.negocio.logoData, let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 140)
                            .cornerRadius(12)
                    } else {
                        Text("Sin logo. El ticket solo muestra el nombre en grande.")
                            .foregroundStyle(.secondary)
                    }
                    PhotosPicker(selection: $foto, matching: .images) {
                        Label("Elegir logo de la galería", systemImage: "photo")
                            .font(.title3)
                    }
                    if store.negocio.logoData != nil {
                        Button("Quitar logo", role: .destructive) {
                            store.negocio.logoData = nil
                            store.guardarNegocio()
                        }
                    }
                }
                Section("Impresora de tickets (Bluetooth / AirPrint)") {
                    Text("Agarra cualquier impresora térmica 58mm o 80mm que iOS reconozca. El ticket se imprime como imagen, con el logo centrado.")
                        .font(.callout).foregroundStyle(.secondary)
                    Picker("Tamaño de papel", selection: $store.negocio.papel) {
                        Text("58mm").tag("58mm")
                        Text("80mm").tag("80mm")
                    }
                    .pickerStyle(.segmented)
                    Picker("Tamaño del logo", selection: $store.negocio.tamanoLogo) {
                        Text("Pequeño").tag("pequeño")
                        Text("Mediano").tag("mediano")
                        Text("Grande").tag("grande")
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button("💾 Guardar") { store.guardarNegocio() }
                        .font(.title3).bold()
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
            }
            .navigationTitle("Mi negocio")
            .onChange(of: foto) { item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        store.negocio.logoData = data
                        store.guardarNegocio()
                    }
                }
            }
            .onChange(of: store.negocio.nombre) { store.guardarNegocio() }
            .onChange(of: store.negocio.direccion) { store.guardarNegocio() }
            .onChange(of: store.negocio.telefono) { store.guardarNegocio() }
            .onChange(of: store.negocio.mesero) { store.guardarNegocio() }
            .onChange(of: store.negocio.papel) { store.guardarNegocio() }
            .onChange(of: store.negocio.tamanoLogo) { store.guardarNegocio() }
        }
    }
}
