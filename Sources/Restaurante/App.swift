import SwiftUI
import Foundation
import PhotosUI
import UIKit
import MultipeerConnectivity
import AVFoundation
import UniformTypeIdentifiers

// Bar — app tipo Soft Restaurant para iPhone, adaptada para un bar.
// Para el bar: mesas, comandas, barra y cocina, inventario y ventas.
// Para el cliente: pedir desde su iPhone (pestaña Cliente).
// Sin servidor: todo se guarda en local, en un JSON en Documents.
// Sincronización por WiFi local: MultipeerConnectivity (Bonjour),
// sin internet y sin servidor. Todos los iPhones con la app, en el
// mismo WiFi, se encuentran y se pasan pedidos, mesas e inventario.

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
    var codigo: String? = nil
    var variante: String? = nil
    /// Destino explícito: "Barra" o "Cocina". Si es nil, se deduce de la categoría.
    var destino: String? = nil
    /// ¿Este producto va a Barra (bebidas) o a Cocina (comida)?
    var vaABarra: Bool {
        if let d = destino { return d.lowercased() == "barra" }
        return MenuItem.categoriaEsBebida(categoria)
    }
    var vaACocina: Bool { !vaABarra }
    static func categoriaEsBebida(_ categoria: String) -> Bool {
        ["cervezas", "cocteles", "cócteles", "destilados", "shots", "bebidas", "barra"].contains(categoria.lowercased())
    }
    static func destinoDeCategoria(_ categoria: String) -> String {
        categoriaEsBebida(categoria) ? "Barra" : "Cocina"
    }
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
    var variante: String? = nil
    var codigo: String? = nil
    var subtotal: Double { precio * Double(cantidad) }
    var nombreCompleto: String {
        if let v = variante, !v.isEmpty { return "\(nombre) (\(v))" }
        return nombre
    }
}

enum EstadoPedido: String, Codable, CaseIterable {
    case pendiente = "pendiente"
    case cocina = "cocina"
    case listo = "listo"
    case cobrado = "cobrado"
    var titulo: String {
        switch self {
        case .pendiente: return "Pendiente"
        case .cocina: return "En barra"
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
    var descuento: Double = 0
    var formaPago: String = "Efectivo"
    var tipoPedido: String = "Mesa"
    var clienteId: UUID? = nil
    var clienteNombre: String = ""
    var direccionEntrega: String = ""
    var telefonoEntrega: String = ""
    var devuelto: Bool = false
    var motivoDevolucion: String = ""
    var total: Double { items.reduce(0) { $0 + $1.subtotal } }
    var totalConDescuento: Double { max(0, total - descuento) }
    var totalConPropina: Double { totalConDescuento + propina }
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
        descuento = try c.decodeIfPresent(Double.self, forKey: .descuento) ?? 0
        formaPago = try c.decodeIfPresent(String.self, forKey: .formaPago) ?? "Efectivo"
        tipoPedido = try c.decodeIfPresent(String.self, forKey: .tipoPedido) ?? "Mesa"
        clienteId = try c.decodeIfPresent(UUID.self, forKey: .clienteId)
        clienteNombre = try c.decodeIfPresent(String.self, forKey: .clienteNombre) ?? ""
        direccionEntrega = try c.decodeIfPresent(String.self, forKey: .direccionEntrega) ?? ""
        telefonoEntrega = try c.decodeIfPresent(String.self, forKey: .telefonoEntrega) ?? ""
        devuelto = try c.decodeIfPresent(Bool.self, forKey: .devuelto) ?? false
        motivoDevolucion = try c.decodeIfPresent(String.self, forKey: .motivoDevolucion) ?? ""
    }
}


// MARK: - Mi negocio y ticket

struct Negocio: Codable, Equatable {
    var nombre: String = "Mi Bar"
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
        nombre = try c.decodeIfPresent(String.self, forKey: .nombre) ?? "Mi Bar"
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
    var descuento: Double = 0
    var formaPago: String = "Efectivo"
    var total: Double { max(0, subtotal - descuento) + propina }
}

// MARK: - Clientes y lealtad + movimientos de caja (estilo Loyverse)

struct Cliente: Identifiable, Codable, Equatable {
    var id = UUID()
    var nombre: String
    var telefono: String = ""
    var puntos: Int = 0
    var totalGastado: Double = 0
    var visitas: Int = 0
}

/// Cuenta abierta de bar: queda ABIERTA, se le sigue agregando, y puede
/// juntar varias mesas en una sola cuenta. No se cierra sola al pedir.
struct CuentaAbierta: Identifiable, Codable, Equatable {
    var id = UUID()
    var nombre: String
    var mesas: [String] = []
    var creada: Date = Date()
    var titulo: String {
        mesas.isEmpty ? nombre : mesas.joined(separator: " + ")
    }
}

struct MovimientoCaja: Identifiable, Codable, Equatable {
    var id = UUID()
    var fecha: Date = Date()
    var tipo: String // "entrada" o "salida"
    var concepto: String
    var monto: Double
    var formaPago: String = "Efectivo"
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
    if ticket.descuento > 0 { lineas.append("Descuento: -\(mxn(ticket.descuento))") }
    lineas.append("Propina:  \(mxn(ticket.propina))")
    lineas.append("Pago: \(ticket.formaPago)")
    lineas.append("TOTAL:    \(mxn(ticket.total))")
    lineas.append("")
    lineas.append("¡Gracias por su visita!")
    return lineas.joined(separator: "\n")
}


// MARK: - Sincronización por WiFi local (MultipeerConnectivity)

/// Lo que se manda por la red local: el estado completo, con fecha.
/// Último cambio gana: el que tenga el timestamp más nuevo se queda.
struct SyncPayload: Codable {
    var timestamp: Date
    var dispositivo: String
    var menu: [MenuItem]
    var inventario: [InventarioItem]
    var pedidos: [Pedido]
    var siguienteNumero: Int
    var negocio: Negocio
    var clientes: [Cliente] = []
    var movimientos: [MovimientoCaja] = []
    var fondoInicial: Double = 0
    var cuentas: [CuentaAbierta] = []
    var meseros: [String] = ["Mesero"]
    var meseroPorMesa: [String: String] = [:]
}
extension SyncPayload {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        dispositivo = try c.decodeIfPresent(String.self, forKey: .dispositivo) ?? ""
        menu = try c.decodeIfPresent([MenuItem].self, forKey: .menu) ?? []
        inventario = try c.decodeIfPresent([InventarioItem].self, forKey: .inventario) ?? []
        pedidos = try c.decodeIfPresent([Pedido].self, forKey: .pedidos) ?? []
        siguienteNumero = try c.decodeIfPresent(Int.self, forKey: .siguienteNumero) ?? 1
        negocio = try c.decodeIfPresent(Negocio.self, forKey: .negocio) ?? Negocio()
        clientes = try c.decodeIfPresent([Cliente].self, forKey: .clientes) ?? []
        movimientos = try c.decodeIfPresent([MovimientoCaja].self, forKey: .movimientos) ?? []
        fondoInicial = try c.decodeIfPresent(Double.self, forKey: .fondoInicial) ?? 0
        cuentas = try c.decodeIfPresent([CuentaAbierta].self, forKey: .cuentas) ?? []
        meseros = try c.decodeIfPresent([String].self, forKey: .meseros) ?? ["Mesero"]
        meseroPorMesa = try c.decodeIfPresent([String: String].self, forKey: .meseroPorMesa) ?? [:]
    }
}

/// Servicio Bonjour. Máximo 15 caracteres, minúsculas y guion.
/// Debe coincidir con NSBonjourServices en project.yml / Info.plist.
let servicioRedLocal = "tiki-comanda"

final class RedLocalSync: NSObject, ObservableObject {
    @Published var activa: Bool = false
    @Published var conectados: [String] = []
    @Published var encontrados: [String] = []
    @Published var estado: String = "Apagada"
    @Published var ultimaSync: Date? = nil

    var alRecibir: ((SyncPayload) -> Void)?

    private let peerID = MCPeerID(displayName: UIDevice.current.name)
    private var sesion: MCSession!
    private var anunciante: MCNearbyServiceAdvertiser?
    private var buscador: MCNearbyServiceBrowser?
    private var paresEncontrados: [MCPeerID] = []

    override init() {
        super.init()
        sesion = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        sesion.delegate = self
    }

    var nombreDispositivo: String { UIDevice.current.name }

    func encender() {
        guard !activa else { return }
        anunciante = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: servicioRedLocal)
        anunciante?.delegate = self
        anunciante?.startAdvertisingPeer()
        buscador = MCNearbyServiceBrowser(peer: peerID, serviceType: servicioRedLocal)
        buscador?.delegate = self
        buscador?.startBrowsingForPeers()
        activa = true
        estado = "Buscando iPhones cercanos…"
    }

    func apagar() {
        anunciante?.stopAdvertisingPeer()
        buscador?.stopBrowsingForPeers()
        anunciante = nil
        buscador = nil
        sesion.disconnect()
        activa = false
        conectados = []
        encontrados = []
        paresEncontrados = []
        estado = "Apagada"
    }

    func invitar(_ nombre: String) {
        guard let par = paresEncontrados.first(where: { $0.displayName == nombre }) else { return }
        buscador?.invitePeer(par, to: sesion, withContext: nil, timeout: 30)
        estado = "Conectando con \(nombre)…"
    }

    func enviar(_ datos: Data) {
        guard activa, !sesion.connectedPeers.isEmpty else { return }
        try? sesion.send(datos, toPeers: sesion.connectedPeers, with: .reliable)
    }
}

extension RedLocalSync: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.conectados = session.connectedPeers.map { $0.displayName }
            self.estado = session.connectedPeers.isEmpty
                ? "Buscando iPhones cercanos…"
                : "Conectado a \(session.connectedPeers.count) dispositivo(s)"
        }
    }
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let payload = try? JSONDecoder().decode(SyncPayload.self, from: data) else { return }
        DispatchQueue.main.async {
            self.ultimaSync = Date()
            self.alRecibir?(payload)
        }
    }
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension RedLocalSync: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Aceptar solo: en el restaurante, todos los iPhones con la app son de confianza.
        invitationHandler(true, sesion)
    }
}

extension RedLocalSync: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            if !self.paresEncontrados.contains(peerID) { self.paresEncontrados.append(peerID) }
            self.encontrados = self.paresEncontrados.map { $0.displayName }
        }
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.paresEncontrados.removeAll { $0 == peerID }
            self.encontrados = self.paresEncontrados.map { $0.displayName }
        }
    }
}

// MARK: - Datos (persistencia local en JSON)

struct DatosGuardados: Codable {
    var menu: [MenuItem]
    var inventario: [InventarioItem]
    var pedidos: [Pedido]
    var siguienteNumero: Int
    var negocio: Negocio = Negocio()
    var clientes: [Cliente] = []
    var movimientos: [MovimientoCaja] = []
    var fondoInicial: Double = 0
    var cuentas: [CuentaAbierta] = []
    var meseros: [String] = ["Mesero"]
    var meseroPorMesa: [String: String] = [:]
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
        clientes = try c.decodeIfPresent([Cliente].self, forKey: .clientes) ?? []
        movimientos = try c.decodeIfPresent([MovimientoCaja].self, forKey: .movimientos) ?? []
        fondoInicial = try c.decodeIfPresent(Double.self, forKey: .fondoInicial) ?? 0
        cuentas = try c.decodeIfPresent([CuentaAbierta].self, forKey: .cuentas) ?? []
        meseros = try c.decodeIfPresent([String].self, forKey: .meseros) ?? ["Mesero"]
        meseroPorMesa = try c.decodeIfPresent([String: String].self, forKey: .meseroPorMesa) ?? [:]
    }
}

final class DataStore: ObservableObject {
    @Published var menu: [MenuItem] = []
    @Published var inventario: [InventarioItem] = []
    @Published var pedidos: [Pedido] = []
    @Published var siguienteNumero: Int = 1
    @Published var negocio: Negocio = Negocio()
    @Published var clientes: [Cliente] = []
    @Published var movimientos: [MovimientoCaja] = []
    @Published var fondoInicial: Double = 0
    @Published var cuentas: [CuentaAbierta] = []
    @Published var meseros: [String] = ["Mesero"]
    @Published var meseroPorMesa: [String: String] = [:]

    // Red local WiFi: un solo objeto, compartido por todas las vistas.
    let red = RedLocalSync()
    // Fecha del último cambio local y del último sync aplicado.
    // Último cambio gana: si llega un estado más viejo que el nuestro, se ignora.
    private var ultimoCambioLocal: Date = Date()
    private var ultimoSyncAplicado: Date = Date.distantPast
    private var aplicandoSync = false

    /// Manda el estado completo por WiFi local a los iPhones conectados.
    func enviarSync() {
        guard red.activa, !aplicandoSync else { return }
        let payload = SyncPayload(timestamp: Date(), dispositivo: red.nombreDispositivo,
                                  menu: menu, inventario: inventario, pedidos: pedidos,
                                  siguienteNumero: siguienteNumero, negocio: negocio,
                                  clientes: clientes, movimientos: movimientos, fondoInicial: fondoInicial,
                                  cuentas: cuentas, meseros: meseros, meseroPorMesa: meseroPorMesa)
        if let data = try? JSONEncoder().encode(payload) { red.enviar(data) }
    }

    /// Aplica un estado recibido por WiFi. No lo reenvía (evita bucles).
    func aplicarSync(_ payload: SyncPayload) {
        guard payload.dispositivo != red.nombreDispositivo else { return }
        guard payload.timestamp > ultimoSyncAplicado else { return }
        guard payload.timestamp >= ultimoCambioLocal else { return }
        aplicandoSync = true
        ultimoSyncAplicado = payload.timestamp
        menu = payload.menu
        inventario = payload.inventario
        pedidos = payload.pedidos
        siguienteNumero = payload.siguienteNumero
        negocio = payload.negocio
        clientes = payload.clientes
        movimientos = payload.movimientos
        fondoInicial = payload.fondoInicial
        cuentas = payload.cuentas
        meseros = payload.meseros
        meseroPorMesa = payload.meseroPorMesa
        guardarLocal()
        aplicandoSync = false
    }

    private var archivo: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("restaurante.json")
    }

    init() {
        cargar()
        red.alRecibir = { [weak self] payload in self?.aplicarSync(payload) }
    }

    var pedidosCobrados: [Pedido] {
        pedidos.filter { $0.estado == .cobrado && !$0.devuelto }
    }
    var ventasDelDia: Double {
        pedidosCobrados.reduce(0) { $0 + $1.totalConPropina }
    }
    var propinasDelDia: Double {
        pedidosCobrados.reduce(0) { $0 + $1.propina }
    }
    var descuentosDelDia: Double {
        pedidosCobrados.reduce(0) { $0 + $1.descuento }
    }
    var devolucionesDelDia: Double {
        pedidos.filter { $0.estado == .cobrado && $0.devuelto }.reduce(0) { $0 + $1.totalConPropina }
    }
    /// Ventas de los últimos 7 días (cobrados, sin devueltos).
    var ventasSemana: Double {
        let hace7 = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return pedidosCobrados.filter { $0.fecha >= hace7 }.reduce(0) { $0 + $1.totalConPropina }
    }
    var ventaPromedio: Double {
        pedidosCobrados.isEmpty ? 0 : ventasDelDia / Double(pedidosCobrados.count)
    }
    /// Total cobrado por forma de pago.
    func ventasPorPago() -> [(String, Double)] {
        let formas = ["Efectivo", "Tarjeta", "Transferencia"]
        return formas.map { forma in
            (forma, pedidosCobrados.filter { $0.formaPago == forma }.reduce(0) { $0 + $1.totalConPropina })
        }
    }
    /// Lo más vendido: nombre -> cantidad, ordenado.
    func masVendidos() -> [(String, Int)] {
        var conteo: [String: Int] = [:]
        for pedido in pedidosCobrados {
            for item in pedido.items { conteo[item.nombreCompleto, default: 0] += item.cantidad }
        }
        return conteo.sorted { $0.value > $1.value }
    }
    /// Minutos que lleva un pedido activo desde que se creó (pantalla de Barra / Cocina).
    func minutosPedido(_ pedido: Pedido) -> Int {
        max(0, Int(Date().timeIntervalSince(pedido.fecha) / 60))
    }
    /// Corte de caja: fondo + ventas en efectivo + entradas - salidas - devoluciones en efectivo.
    var efectivoEnCaja: Double {
        let ventasEfectivo = pedidosCobrados.filter { $0.formaPago == "Efectivo" }.reduce(0) { $0 + $1.totalConPropina }
        let entradas = movimientos.filter { $0.tipo == "entrada" }.reduce(0) { $0 + $1.monto }
        let salidas = movimientos.filter { $0.tipo == "salida" }.reduce(0) { $0 + $1.monto }
        return fondoInicial + ventasEfectivo + entradas - salidas
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

    /// ¿Este item va a Barra (bebida) o a Cocina (comida)? Se busca en el menú
    /// por nombre/código; si no está, se decide por el nombre.
    func esBebidaItem(_ item: PedidoItem) -> Bool {
        if let plato = menu.first(where: { $0.nombre.lowercased() == item.nombre.lowercased() }) { return plato.vaABarra }
        if let codigo = item.codigo, let plato = menu.first(where: { ($0.codigo ?? "").lowercased() == codigo.lowercased() }) { return plato.vaABarra }
        let n = item.nombre.lowercased()
        let bebidas = ["cerveza", "mojito", "margarita", "tequila", "whisky", "ron", "vodka", "gin", "shot", "michelada", "chelada", "piña", "piña colada", "refresco", "agua mineral", "jäger", "jager", "mezcal", "brandy", "copa"]
        return bebidas.contains { n.contains($0) }
    }
    /// Items de un pedido que van a Barra / a Cocina.
    func itemsDeBarra(_ pedido: Pedido) -> [PedidoItem] { pedido.items.filter { esBebidaItem($0) } }
    func itemsDeCocina(_ pedido: Pedido) -> [PedidoItem] { pedido.items.filter { !esBebidaItem($0) } }
    func pedidoTieneBarra(_ pedido: Pedido) -> Bool { !itemsDeBarra(pedido).isEmpty }
    func pedidoTieneCocina(_ pedido: Pedido) -> Bool { !itemsDeCocina(pedido).isEmpty }

    func crearPedido(mesa: String, tipo: String, items: [PedidoItem]) {
        crearPedidoCompleto(mesa: mesa, tipo: tipo, tipoPedido: "Mesa", items: items, descuento: 0, clienteId: nil, clienteNombre: "", direccion: "", telefono: "")
    }

    /// Crea un pedido con descuento y cliente (en mesa o para llevar).
    /// Se parte solo: las bebidas van a Barra y la comida va a Cocina, como dos
    /// pedidos del mismo grupo (cada estación avanza el suyo). La cuenta queda
    /// ABIERTA: no se cierra sola, se le sigue agregando hasta que Luis decida.
    func crearPedidoCompleto(mesa: String, tipo: String, tipoPedido: String, items: [PedidoItem], descuento: Double, clienteId: UUID?, clienteNombre: String, direccion: String, telefono: String) {
        guard !items.isEmpty else { return }
        let bebidas = items.filter { esBebidaItem($0) }
        let comida = items.filter { !esBebidaItem($0) }
        let total = items.reduce(0) { $0 + $1.subtotal }
        if !bebidas.isEmpty && !comida.isEmpty {
            let subB = bebidas.reduce(0) { $0 + $1.subtotal }
            crearUnPedido(mesa: mesa, tipo: tipo, tipoPedido: tipoPedido, items: bebidas, descuento: total > 0 ? descuento * subB / total : 0, clienteId: clienteId, clienteNombre: clienteNombre, direccion: direccion, telefono: telefono)
            crearUnPedido(mesa: mesa, tipo: tipo, tipoPedido: tipoPedido, items: comida, descuento: total > 0 ? descuento * (total - subB) / total : 0, clienteId: clienteId, clienteNombre: clienteNombre, direccion: direccion, telefono: telefono)
        } else {
            crearUnPedido(mesa: mesa, tipo: tipo, tipoPedido: tipoPedido, items: items, descuento: descuento, clienteId: clienteId, clienteNombre: clienteNombre, direccion: direccion, telefono: telefono)
        }
        for item in items {
            if let i = inventario.firstIndex(where: { $0.nombre.lowercased() == item.nombre.lowercased() }) {
                inventario[i].stock = max(0, inventario[i].stock - Double(item.cantidad))
            }
        }
        asegurarCuenta(mesa: mesa)
        guardar()
    }

    private func crearUnPedido(mesa: String, tipo: String, tipoPedido: String, items: [PedidoItem], descuento: Double, clienteId: UUID?, clienteNombre: String, direccion: String, telefono: String) {
        var pedido = Pedido(numero: siguienteNumero, mesa: mesa, tipo: tipo, items: items, estado: .pendiente)
        pedido.descuento = descuento
        pedido.tipoPedido = tipoPedido
        pedido.clienteId = clienteId
        pedido.clienteNombre = clienteNombre
        pedido.direccionEntrega = direccion
        pedido.telefonoEntrega = telefono
        siguienteNumero += 1
        pedidos.append(pedido)
    }

    // MARK: - Meseros por mesa

    /// Mesero que atiende una mesa, o "Sin mesero" si no se le asignó uno.
    func meseroDeMesa(_ mesa: String) -> String {
        meseroPorMesa[mesa] ?? "Sin mesero"
    }
    func tieneMesero(_ mesa: String) -> Bool {
        meseroPorMesa[mesa] != nil
    }
    func asignarMesero(_ nombre: String, a mesa: String) {
        if nombre.isEmpty || nombre == "Sin mesero" {
            meseroPorMesa.removeValue(forKey: mesa)
        } else {
            meseroPorMesa[mesa] = nombre
            if !meseros.contains(nombre) { meseros.append(nombre) }
        }
        guardar()
    }
    func agregarMesero(_ nombre: String) {
        let n = nombre.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !meseros.contains(n) else { return }
        meseros.append(n)
        guardar()
    }
    func eliminarMesero(_ nombre: String) {
        meseros.removeAll { $0 == nombre }
        for mesa in meseroPorMesa.keys where meseroPorMesa[mesa] == nombre {
            meseroPorMesa.removeValue(forKey: mesa)
        }
        guardar()
    }

    // MARK: - Cuentas abiertas (bar): fusionar y mover mesas

    /// Cuentas abiertas (no cobradas). Una cuenta = una o varias mesas juntas.
    var cuentasAbiertas: [CuentaAbierta] {
        cuentas.filter { cuenta in
            !pedidosDeCuenta(cuenta).isEmpty
        }
    }
    func pedidosDeCuenta(_ cuenta: CuentaAbierta) -> [Pedido] {
        pedidos.filter { cuenta.mesas.contains($0.mesa) && $0.estado != .cobrado }
    }
    func totalDeCuenta(_ cuenta: CuentaAbierta) -> Double {
        pedidosDeCuenta(cuenta).reduce(0) { $0 + $1.total }
    }
    func cuentaDeMesa(_ mesa: String) -> CuentaAbierta? {
        cuentas.first { $0.mesas.contains(mesa) }
    }
    /// Al pedir por primera vez en una mesa, su cuenta queda abierta.
    func asegurarCuenta(mesa: String) {
        guard mesa.hasPrefix("Mesa"), cuentaDeMesa(mesa) == nil else { return }
        cuentas.append(CuentaAbierta(nombre: mesa, mesas: [mesa]))
    }
    /// Fusionar 2+ mesas en una sola cuenta: sus pedidos se cobran juntos.
    /// Devuelve la cuenta resultante (o nil si hay menos de 2 mesas).
    @discardableResult
    func fusionarMesas(_ mesas: [String]) -> CuentaAbierta? {
        let unicas = Array(Set(mesas)).sorted()
        guard unicas.count >= 2 else { return nil }
        cuentas.removeAll { cuenta in !Set(cuenta.mesas).isDisjoint(with: Set(unicas)) }
        let cuenta = CuentaAbierta(nombre: unicas.joined(separator: " + "), mesas: unicas)
        cuentas.append(cuenta)
        guardar()
        return cuenta
    }
    /// Mover una mesa a otra cuenta/mesa: sus pedidos activos cambian de mesa.
    func moverMesa(_ origen: String, a destino: String) {
        guard origen != destino else { return }
        for i in pedidos.indices where pedidos[i].mesa == origen && pedidos[i].estado != .cobrado {
            pedidos[i].mesa = destino
        }
        if let ci = cuentas.firstIndex(where: { $0.mesas.contains(origen) }) {
            cuentas[ci].mesas.removeAll { $0 == origen }
            if !cuentas[ci].mesas.contains(destino) { cuentas[ci].mesas.append(destino) }
            if cuentas[ci].mesas.isEmpty { cuentas.remove(at: ci) }
        }
        asegurarCuenta(mesa: destino)
        guardar()
    }
    /// Ticket de una cuenta fusionada (todas sus mesas juntas).
    func ticketParaCuenta(_ cuenta: CuentaAbierta) -> Ticket? {
        let lista = pedidosDeCuenta(cuenta)
        guard !lista.isEmpty else { return nil }
        let items = lista.flatMap { $0.items }
        let subtotal = lista.reduce(0) { $0 + $1.total }
        let meseroCuenta = cuenta.mesas.first.map { meseroDeMesa($0) } ?? "Sin mesero"
        return Ticket(numero: lista.first!.numero, mesa: cuenta.titulo, mesero: meseroCuenta == "Sin mesero" ? negocio.mesero : meseroCuenta,
                      fecha: Date(), items: items, subtotal: subtotal, propina: 0)
    }
    /// Cierra una cuenta fusionada (solo cuando Luis decide) y devuelve el ticket.
    func cerrarCuenta(_ cuenta: CuentaAbierta, propina: Double, mesero: String, descuento: Double = 0, formaPago: String = "Efectivo") -> Ticket? {
        guard let ticket = ticketParaCuenta(cuenta) else { return nil }
        let lista = pedidosDeCuenta(cuenta)
        let subtotal = ticket.subtotal
        for pedido in lista {
            let parte = subtotal > 0 ? propina * (pedido.total / subtotal) : 0
            let descParte = subtotal > 0 ? descuento * (pedido.total / subtotal) : 0
            if let idx = pedidos.firstIndex(of: pedido) { pedidos[idx].descuento = descParte }
            cobrar(pedido, propina: parte, mesero: mesero, formaPago: formaPago)
        }
        cuentas.removeAll { $0.id == cuenta.id }
        var ticketFinal = ticket
        ticketFinal.propina = propina
        ticketFinal.mesero = mesero
        ticketFinal.descuento = descuento
        ticketFinal.formaPago = formaPago
        return ticketFinal
    }

    /// Cambia la cantidad de un item en un pedido ya enviado: + suma uno,
    /// − quita uno, y si llega a 0 el item sale de la cuenta. Si el pedido
    /// se queda sin items, se quita el pedido.
    func cambiarCantidadEnPedido(_ pedido: Pedido, item: PedidoItem, delta: Int) {
        guard let i = pedidos.firstIndex(of: pedido),
              let j = pedidos[i].items.firstIndex(of: item) else { return }
        pedidos[i].items[j].cantidad += delta
        if pedidos[i].items[j].cantidad <= 0 { pedidos[i].items.remove(at: j) }
        if pedidos[i].items.isEmpty { pedidos.remove(at: i) }
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
        cobrar(pedido, propina: propina, mesero: mesero, formaPago: "Efectivo")
    }

    /// Cobra con forma de pago y suma puntos de lealtad al cliente (1 punto por cada $20).
    func cobrar(_ pedido: Pedido, propina: Double, mesero: String, formaPago: String) {
        guard let i = pedidos.firstIndex(of: pedido) else { return }
        pedidos[i].estado = .cobrado
        pedidos[i].propina = propina
        pedidos[i].mesero = mesero
        pedidos[i].formaPago = formaPago
        if let clienteId = pedidos[i].clienteId,
           let ci = clientes.firstIndex(where: { $0.id == clienteId }) {
            let puntos = Int(pedidos[i].totalConDescuento / 20)
            clientes[ci].puntos += puntos
            clientes[ci].totalGastado += pedidos[i].totalConPropina
            clientes[ci].visitas += 1
        }
        guardar()
    }

    /// Devuelve / cancela un pedido ya cobrado, con motivo. No se borra:
    /// queda marcado como devuelto y ya no suma en ventas del día.
    func devolverPedido(_ pedido: Pedido, motivo: String) {
        guard let i = pedidos.firstIndex(of: pedido) else { return }
        pedidos[i].devuelto = true
        pedidos[i].motivoDevolucion = motivo.isEmpty ? "Sin motivo" : motivo
        guardar()
    }

    /// Ticket (sin cobrar) de una mesa: todos sus pedidos activos juntos.
    func ticketParaMesa(_ mesa: String) -> Ticket? {
        let lista = pedidosDeMesa(mesa)
        guard !lista.isEmpty else { return nil }
        let items = lista.flatMap { $0.items }
        let subtotal = lista.reduce(0) { $0 + $1.total }
        let meseroMesa = meseroDeMesa(mesa)
        return Ticket(numero: lista.first!.numero, mesa: mesa, mesero: meseroMesa == "Sin mesero" ? negocio.mesero : meseroMesa,
                      fecha: Date(), items: items, subtotal: subtotal, propina: 0)
    }

    /// Cierra la cuenta de una mesa: reparte propina y descuento entre sus pedidos,
    /// los marca como Cobrado, deja la mesa libre y devuelve el ticket.
    func cerrarMesa(_ mesa: String, propina: Double, mesero: String, descuento: Double = 0, formaPago: String = "Efectivo") -> Ticket? {
        guard let ticket = ticketParaMesa(mesa) else { return nil }
        let lista = pedidosDeMesa(mesa)
        let subtotal = ticket.subtotal
        for pedido in lista {
            let parte = subtotal > 0 ? propina * (pedido.total / subtotal) : 0
            let descParte = subtotal > 0 ? descuento * (pedido.total / subtotal) : 0
            if let idx = pedidos.firstIndex(of: pedido) { pedidos[idx].descuento = descParte }
            cobrar(pedido, propina: parte, mesero: mesero, formaPago: formaPago)
        }
        cuentas.removeAll { $0.mesas.contains(mesa) && $0.mesas.count == 1 }
        for ci in cuentas.indices { cuentas[ci].mesas.removeAll { $0 == mesa } }
        cuentas.removeAll { $0.mesas.isEmpty }
        var ticketFinal = ticket
        ticketFinal.propina = propina
        ticketFinal.mesero = mesero
        ticketFinal.descuento = descuento
        ticketFinal.formaPago = formaPago
        return ticketFinal
    }

    // MARK: Clientes, caja y CSV

    func agregarCliente(nombre: String, telefono: String) {
        guard !nombre.isEmpty else { return }
        clientes.append(Cliente(nombre: nombre, telefono: telefono))
        guardar()
    }

    func registrarMovimiento(tipo: String, concepto: String, monto: Double, formaPago: String = "Efectivo") {
        guard monto > 0 else { return }
        movimientos.append(MovimientoCaja(tipo: tipo, concepto: concepto, monto: monto, formaPago: formaPago))
        guardar()
    }

    /// CSV de ventas cobradas (sin devueltos) para compartir / Excel.
    func exportarVentasCSV() -> String {
        var lineas = ["numero,fecha,mesa,tipo,forma_pago,subtotal,descuento,propina,total,cliente"]
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        for pedido in pedidosCobrados {
            let fecha = f.string(from: pedido.fecha)
            lineas.append("\(pedido.numero),\(fecha),\"\(pedido.mesa)\",\(pedido.tipoPedido),\(pedido.formaPago),\(pedido.total),\(pedido.descuento),\(pedido.propina),\(pedido.totalConPropina),\"\(pedido.clienteNombre)\"")
        }
        return lineas.joined(separator: "\n")
    }

    /// CSV del inventario: nombre,unidad,stock,minimo (una línea por producto).
    func exportarInventarioCSV() -> String {
        var lineas = ["nombre,unidad,stock,minimo"]
        for item in inventario {
            lineas.append("\"\(item.nombre)\",\(item.unidad),\(item.stock),\(item.minimo)")
        }
        return lineas.joined(separator: "\n")
    }

    /// CSV del menú: nombre,precio,categoria,codigo (una línea por platillo/bebida).
    func exportarMenuCSV() -> String {
        var lineas = ["nombre,precio,categoria,codigo"]
        for item in menu {
            lineas.append("\"\(item.nombre)\",\(item.precio),\"\(item.categoria)\",\"\(item.codigo ?? "")\"")
        }
        return lineas.joined(separator: "\n")
    }

    /// Parte una línea CSV respetando comillas: "Mojito,120,Bebidas,MOJ01".
    func camposCSV(_ linea: String) -> [String] {
        var campos: [String] = []
        var actual = ""
        var entreComillas = false
        for ch in linea {
            if ch == "\"" { entreComillas.toggle(); continue }
            if ch == "," && !entreComillas { campos.append(actual.trimmingCharacters(in: .whitespaces)); actual = "" }
            else { actual.append(ch) }
        }
        campos.append(actual.trimmingCharacters(in: .whitespaces))
        return campos
    }

    /// Importa menú desde CSV (nombre,precio,categoria,codigo).
    /// Sin duplicar por nombre: si el nombre ya existe, actualiza precio/categoría/código.
    /// Devuelve (agregados, actualizados, errores por línea).
    func importarMenuCSVDetallado(_ texto: String) -> (Int, Int, [String]) {
        var agregados = 0; var actualizados = 0; var errores: [String] = []
        for (n, linea) in texto.components(separatedBy: .newlines).enumerated() {
            let limpia = linea.trimmingCharacters(in: .whitespaces)
            guard !limpia.isEmpty else { continue }
            let partes = camposCSV(limpia)
            guard partes.count >= 2, partes[0].lowercased() != "nombre",
                  let precio = Double(partes[1]) else {
                errores.append("Línea \(n + 1): revisa nombre y precio — \(limpia)")
                continue
            }
            let nombre = partes[0]
            let categoria = partes.count >= 3 && !partes[2].isEmpty ? partes[2] : "Bar"
            let codigo = partes.count >= 4 && !partes[3].isEmpty ? partes[3] : nil
            // La categoría decide a dónde va: Bebidas -> Barra, Comida -> Cocina.
            // "Bebidas" y "Comida" son categorías genéricas válidas en el CSV.
            let destino: String? = (categoria.lowercased() == "bebidas" || categoria.lowercased() == "comida") ? (categoria.lowercased() == "bebidas" ? "Barra" : "Cocina") : nil
            if let i = menu.firstIndex(where: { $0.nombre.lowercased() == nombre.lowercased() }) {
                menu[i].precio = precio; menu[i].categoria = categoria; menu[i].codigo = codigo; menu[i].destino = destino
                actualizados += 1
            } else {
                menu.append(MenuItem(nombre: nombre, precio: precio, categoria: categoria, codigo: codigo, destino: destino))
                agregados += 1
            }
        }
        if agregados > 0 || actualizados > 0 { guardar() }
        return (agregados, actualizados, errores)
    }

    /// Importa inventario desde CSV con detalle (nombre,unidad,stock,minimo).
    /// Sin duplicar por nombre: si ya existe, actualiza unidad/stock/mínimo.
    func importarInventarioCSVDetallado(_ texto: String) -> (Int, Int, [String]) {
        var agregados = 0; var actualizados = 0; var errores: [String] = []
        for (n, linea) in texto.components(separatedBy: .newlines).enumerated() {
            let limpia = linea.trimmingCharacters(in: .whitespaces)
            guard !limpia.isEmpty else { continue }
            let partes = camposCSV(limpia)
            guard partes.count >= 4, partes[0].lowercased() != "nombre",
                  let stock = Double(partes[2]), let minimo = Double(partes[3]) else {
                errores.append("Línea \(n + 1): revisa nombre, unidad, stock y mínimo — \(limpia)")
                continue
            }
            if let i = inventario.firstIndex(where: { $0.nombre.lowercased() == partes[0].lowercased() }) {
                inventario[i].unidad = partes[1]; inventario[i].stock = stock; inventario[i].minimo = minimo
                actualizados += 1
            } else {
                inventario.append(InventarioItem(nombre: partes[0], unidad: partes[1], stock: stock, minimo: minimo))
                agregados += 1
            }
        }
        if agregados > 0 || actualizados > 0 { guardar() }
        return (agregados, actualizados, errores)
    }

    /// Agrega un platillo/bebida al menú, o lo actualiza si ya existe ese nombre.
    func agregarMenu(nombre: String, precio: Double, categoria: String, codigo: String?, destino: String? = nil) {
        guard !nombre.isEmpty else { return }
        if let i = menu.firstIndex(where: { $0.nombre.lowercased() == nombre.lowercased() }) {
            menu[i].precio = precio; menu[i].categoria = categoria; menu[i].codigo = codigo; menu[i].destino = destino
        } else {
            menu.append(MenuItem(nombre: nombre, precio: precio, categoria: categoria, codigo: codigo, destino: destino))
        }
        guardar()
    }
    func actualizarMenu(_ item: MenuItem, nombre: String, precio: Double, categoria: String, codigo: String?, destino: String? = nil) {
        guard let i = menu.firstIndex(of: item) else { return }
        menu[i].nombre = nombre; menu[i].precio = precio; menu[i].categoria = categoria; menu[i].codigo = codigo; menu[i].destino = destino
        guardar()
    }
    func eliminarMenu(_ item: MenuItem) {
        menu.removeAll { $0.id == item.id }
        guardar()
    }
    func actualizarInventario(_ item: InventarioItem, nombre: String, unidad: String, stock: Double, minimo: Double) {
        guard let i = inventario.firstIndex(of: item) else { return }
        inventario[i].nombre = nombre; inventario[i].unidad = unidad; inventario[i].stock = stock; inventario[i].minimo = minimo
        guardar()
    }
    func eliminarInventario(_ item: InventarioItem) {
        inventario.removeAll { $0.id == item.id }
        guardar()
    }

    /// Agrega un platillo/bebida a la comanda de una mesa: si ya tiene un pedido
    /// activo de esa estación (Barra o Cocina), lo suma a ese pedido; si no,
    /// crea un pedido nuevo. La cuenta queda ABIERTA.
    func agregarItemAMesa(_ mesa: String, plato: MenuItem) {
        let item = PedidoItem(nombre: plato.nombre, precio: plato.precio, cantidad: 1, codigo: plato.codigo)
        let aBarra = plato.vaABarra
        if let i = pedidos.firstIndex(where: { $0.mesa == mesa && $0.estado != .cobrado && (aBarra ? pedidoTieneBarra($0) : pedidoTieneCocina($0)) }) {
            if let j = pedidos[i].items.firstIndex(where: { $0.nombre == plato.nombre }) {
                pedidos[i].items[j].cantidad += 1
            } else {
                pedidos[i].items.append(item)
            }
        } else {
            var pedido = Pedido(numero: siguienteNumero, mesa: mesa, tipo: "Mesa", items: [item], estado: .pendiente)
            pedido.tipoPedido = "Mesa"
            siguienteNumero += 1
            pedidos.append(pedido)
        }
        asegurarCuenta(mesa: mesa)
        guardar()
    }

    /// Agrega un item a un pedido ya enviado (desde Barra o Cocina), sin
    /// tener que volver a Mesas. El pedido sigue abierto.
    func agregarItemAPedido(_ pedido: Pedido, plato: MenuItem) {
        guard let i = pedidos.firstIndex(of: pedido), pedidos[i].estado != .cobrado else { return }
        let item = PedidoItem(nombre: plato.nombre, precio: plato.precio, cantidad: 1, codigo: plato.codigo)
        if let j = pedidos[i].items.firstIndex(where: { $0.nombre == plato.nombre }) {
            pedidos[i].items[j].cantidad += 1
        } else {
            pedidos[i].items.append(item)
        }
        guardar()
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

    /// Guarda en local y avisa por WiFi a los demás iPhones.
    func guardar() {
        ultimoCambioLocal = Date()
        guardarLocal()
        enviarSync()
    }

    /// Solo guarda en local, sin avisar por WiFi (para aplicar un sync).
    func guardarLocal() {
        let datos = DatosGuardados(menu: menu, inventario: inventario, pedidos: pedidos, siguienteNumero: siguienteNumero, negocio: negocio, clientes: clientes, movimientos: movimientos, fondoInicial: fondoInicial, cuentas: cuentas, meseros: meseros, meseroPorMesa: meseroPorMesa)
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
            clientes = datos.clientes
            movimientos = datos.movimientos
            fondoInicial = datos.fondoInicial
            cuentas = datos.cuentas
            meseros = datos.meseros.isEmpty ? ["Mesero"] : datos.meseros
            meseroPorMesa = datos.meseroPorMesa
            return
        }
        semilla()
    }

    private func semilla() {
        menu = [
            MenuItem(nombre: "Cerveza Corona 355 ml", precio: 45, categoria: "Cervezas", codigo: "COR01"),
            MenuItem(nombre: "Cerveza Modelo 355 ml", precio: 45, categoria: "Cervezas", codigo: "MOD01"),
            MenuItem(nombre: "Cerveza Victoria 355 ml", precio: 40, categoria: "Cervezas", codigo: "VIC01"),
            MenuItem(nombre: "Cerveza artesanal 355 ml", precio: 65, categoria: "Cervezas", codigo: "ART01"),
            MenuItem(nombre: "Michelada", precio: 65, categoria: "Cervezas", codigo: "MIC01"),
            MenuItem(nombre: "Chelada", precio: 55, categoria: "Cervezas", codigo: "CHE01"),
            MenuItem(nombre: "Mojito", precio: 120, categoria: "Cocteles", codigo: "MOJ01"),
            MenuItem(nombre: "Margarita", precio: 120, categoria: "Cocteles", codigo: "MAR01"),
            MenuItem(nombre: "Piña colada", precio: 130, categoria: "Cocteles", codigo: "PIN01"),
            MenuItem(nombre: "Gin tonic", precio: 110, categoria: "Cocteles", codigo: "GIN01"),
            MenuItem(nombre: "Tequila shot", precio: 60, categoria: "Shots", codigo: "TEQ01"),
            MenuItem(nombre: "Tequila reposado (copa)", precio: 90, categoria: "Destilados", codigo: "TEQ02"),
            MenuItem(nombre: "Whisky (copa)", precio: 110, categoria: "Destilados", codigo: "WHI01"),
            MenuItem(nombre: "Ron con coca", precio: 95, categoria: "Destilados", codigo: "RON01"),
            MenuItem(nombre: "Vodka con jugo", precio: 95, categoria: "Destilados", codigo: "VOD01"),
            MenuItem(nombre: "Shot de Jägermeister", precio: 70, categoria: "Shots", codigo: "JAG01"),
            MenuItem(nombre: "Alitas BBQ (6 pzas)", precio: 110, categoria: "Botanas", codigo: "ALI01"),
            MenuItem(nombre: "Alitas buffalo (6 pzas)", precio: 110, categoria: "Botanas", codigo: "ALI02"),
            MenuItem(nombre: "Nachos con queso", precio: 95, categoria: "Botanas", codigo: "NAC01"),
            MenuItem(nombre: "Papas a la francesa", precio: 60, categoria: "Botanas", codigo: "PAP01"),
            MenuItem(nombre: "Papas con queso", precio: 75, categoria: "Botanas", codigo: "PAP02"),
            MenuItem(nombre: "Refresco 600 ml", precio: 30, categoria: "Bebidas", codigo: "REF01"),
            MenuItem(nombre: "Agua mineral 600 ml", precio: 30, categoria: "Bebidas", codigo: "AGU01"),
        ]
        inventario = [
            InventarioItem(nombre: "Cerveza Corona", unidad: "pzas", stock: 48, minimo: 12),
            InventarioItem(nombre: "Cerveza Modelo", unidad: "pzas", stock: 48, minimo: 12),
            InventarioItem(nombre: "Ron blanco", unidad: "botella", stock: 12, minimo: 2),
            InventarioItem(nombre: "Tequila", unidad: "botella", stock: 8, minimo: 2),
            InventarioItem(nombre: "Whisky", unidad: "botella", stock: 6, minimo: 2),
            InventarioItem(nombre: "Vodka", unidad: "botella", stock: 6, minimo: 2),
            InventarioItem(nombre: "Ginebra", unidad: "botella", stock: 4, minimo: 1),
            InventarioItem(nombre: "Limones", unidad: "kg", stock: 5, minimo: 2),
            InventarioItem(nombre: "Hierbabuena", unidad: "manojo", stock: 10, minimo: 3),
            InventarioItem(nombre: "Alitas", unidad: "kg", stock: 8, minimo: 3),
            InventarioItem(nombre: "Queso", unidad: "kg", stock: 4, minimo: 2),
            InventarioItem(nombre: "Papas", unidad: "kg", stock: 10, minimo: 3),
            InventarioItem(nombre: "Hielo", unidad: "kg", stock: 20, minimo: 5),
            InventarioItem(nombre: "Refresco 600 ml", unidad: "pzas", stock: 24, minimo: 12),
        ]
        clientes = [Cliente(nombre: "Cliente frecuente", telefono: "", puntos: 10, totalGastado: 200, visitas: 2)]
        fondoInicial = 500
        pedidos = [
            Pedido(numero: 1, mesa: "Mesa 2", tipo: "Mesa",
                   items: [PedidoItem(nombre: "Mojito", precio: 120, cantidad: 2),
                           PedidoItem(nombre: "Cerveza Corona 355 ml", precio: 45, cantidad: 2)],
                   estado: .cocina),
        ]
        siguienteNumero = 2
        guardar()
    }
}

func mxn(_ valor: Double) -> String {
    String(format: "$%.2f MXN", valor)
}

// MARK: - Diseño POS (estilo Loyverse: bonito, no plano)

// Paleta cálida de punto de venta: naranja/rojo para vender, verde para
// libre/listo, ámbar para pendiente. Todo en tarjetas blancas con sombra.
extension Color {
    static let posNaranja = Color(red: 0.98, green: 0.45, blue: 0.10)
    static let posRojo = Color(red: 0.92, green: 0.25, blue: 0.20)
    static let posVerde = Color(red: 0.15, green: 0.68, blue: 0.35)
    static let posAmbar = Color(red: 0.95, green: 0.65, blue: 0.05)
    static let posFondo = Color(red: 0.96, green: 0.96, blue: 0.98)
    static let posTinta = Color(red: 0.12, green: 0.12, blue: 0.18)
}

/// Tarjeta blanca con esquinas grandes y sombra suave (no plana).
struct TarjetaPOS: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Color.white)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
    }
}
/// Control grande − cantidad + : el − quita uno, y si llega a 0 quita el
/// producto de la cuenta. Sin botón Quitar aparte.
struct CantidadStepperView: View {
    var cantidad: Int
    var onCambiar: (Int) -> Void
    var body: some View {
        HStack(spacing: 8) {
            Button("−") { onCambiar(-1) }
                .font(.title).bold()
                .frame(width: 52, height: 52)
                .background(Color.gray.opacity(0.18))
                .foregroundStyle(Color.posTinta)
                .cornerRadius(14)
            Text("\(cantidad)")
                .font(.title2).bold()
                .frame(minWidth: 36)
                .lineLimit(1)
            Button("+") { onCambiar(1) }
                .font(.title).bold()
                .frame(width: 52, height: 52)
                .background(LinearGradient(colors: [.posNaranja, .posRojo], startPoint: .leading, endPoint: .trailing))
                .foregroundStyle(.white)
                .cornerRadius(14)
                .shadow(color: Color.posRojo.opacity(0.3), radius: 6, x: 0, y: 3)
        }
    }
}

/// Cierra el teclado (para la barra "Listo" y para tocar fuera del campo).
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
extension View {
    /// Barra sobre el teclado con botón "Listo" que lo cierra. Poner en
    /// todas las pantallas con campos de texto/número.
    func barraTecladoListo() -> some View {
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { hideKeyboard() }.bold()
            }
        }
    }
    func tarjetaPOS() -> some View { modifier(TarjetaPOS()) }
    /// Botón grande con relieve: gradiente + sombra.
    func botonPOS() -> some View {
        self
            .font(.title3).bold()
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(LinearGradient(colors: [.posNaranja, .posRojo], startPoint: .leading, endPoint: .trailing))
            .foregroundStyle(.white)
            .cornerRadius(16)
            .shadow(color: Color.posRojo.opacity(0.35), radius: 8, x: 0, y: 4)
    }
}

/// Gradiente por estado de pedido / mesa.
func gradienteEstado(_ estado: EstadoPedido) -> LinearGradient {
    switch estado {
    case .pendiente: return LinearGradient(colors: [.posAmbar, Color(red: 0.98, green: 0.55, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
    case .cocina: return LinearGradient(colors: [.posNaranja, .posRojo], startPoint: .topLeading, endPoint: .bottomTrailing)
    case .listo: return LinearGradient(colors: [.posVerde, Color(red: 0.10, green: 0.55, blue: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
    case .cobrado: return LinearGradient(colors: [Color.gray, Color(red: 0.45, green: 0.45, blue: 0.50)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
func colorEstado(_ estado: EstadoPedido) -> Color {
    switch estado {
    case .pendiente: return .posAmbar
    case .cocina: return .posNaranja
    case .listo: return .posVerde
    case .cobrado: return .gray
    }
}
func iconoCategoria(_ categoria: String) -> String {
    switch categoria {
    case "Cervezas": return "🍺"
    case "Cocteles": return "🍹"
    case "Destilados": return "🥃"
    case "Shots": return "🥃"
    case "Botanas": return "🍗"
    case "Bebidas": return "🥤"
    case "Tacos": return "🌮"
    case "Platos": return "🍲"
    case "Entradas": return "🥑"
    case "Postres": return "🍮"
    default: return "🍺"
    }
}
func fechaHoy() -> String {
    let f = DateFormatter()
    f.dateStyle = .full; f.timeStyle = .none
    return f.string(from: Date())
}

/// Encabezado del negocio: logo, nombre, fecha y ventas del día en grande.
struct EncabezadoPOS: View {
    @EnvironmentObject var store: DataStore
    var body: some View {
        HStack(spacing: 12) {
            if let data = store.negocio.logoData, let ui = UIImage(data: data) {
                Image(uiImage: ui).resizable().scaledToFill()
                    .frame(width: 52, height: 52).clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(radius: 4)
            } else {
                ZStack {
                    Circle().fill(Color.white.opacity(0.25)).frame(width: 52, height: 52)
                    Image(systemName: "storefront.fill").font(.title2).foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(store.negocio.nombre).font(.title2).bold().foregroundStyle(.white).lineLimit(1)
                Text(fechaHoy()).font(.caption).foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Hoy").font(.caption).bold().foregroundStyle(.white.opacity(0.85))
                Text(mxn(store.ventasDelDia)).font(.headline).bold().foregroundStyle(.white)
            }
        }
        .padding(16)
        .background(LinearGradient(colors: [.posNaranja, .posRojo, Color(red: 0.75, green: 0.15, blue: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

// MARK: - Vista principal

struct ContentView: View {
    @EnvironmentObject var store: DataStore
    var body: some View {
        VStack(spacing: 0) {
            EncabezadoPOS()
            TabView {
                MesasView()
                    .tabItem { Label("Mesas", systemImage: "table.furniture") }
                MenuView()
                    .tabItem { Label("Menú", systemImage: "menucard") }
                BarraView()
                    .tabItem { Label("Barra", systemImage: "flame") }
                CocinaView()
                    .tabItem { Label("Cocina", systemImage: "fork.knife") }
                CajaView()
                    .tabItem { Label("Caja", systemImage: "banknote.fill") }
                InventarioView()
                    .tabItem { Label("Inventario", systemImage: "shippingbox") }
                VentasView()
                    .tabItem { Label("Ventas", systemImage: "banknote") }
                // Cliente desactivado por ahora: el cliente NO pide desde su
                // iPhone en esta versión. Solo lado del staff/bar.
                // ClienteView() .tabItem { Label("Cliente", systemImage: "person") }
                ClientesView()
                    .tabItem { Label("Clientes", systemImage: "person.2.fill") }
                ReportesView()
                    .tabItem { Label("Reportes", systemImage: "chart.bar.fill") }
                NegocioView()
                    .tabItem { Label("Mi negocio", systemImage: "storefront") }
                RedLocalView(red: store.red)
                    .tabItem { Label("Red local", systemImage: "wifi") }
            }
        }
        .background(Color.posFondo)
        .preferredColorScheme(.light)
    }
}

// MARK: - Mesas (1 a 8)

struct MesasView: View {
    @EnvironmentObject var store: DataStore
    @State private var mesaSeleccionada: Int = 1
    @State private var mesaAbierta: MesaIdentidad? = nil
    @State private var mostrarFusionar = false
    @State private var mostrarCerrar = false
    @State private var ticketCerrado: Ticket? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.tap.fill").foregroundStyle(Color.posNaranja)
                        Text("Toca una mesa para abrir su cuenta")
                            .font(.callout).bold().foregroundStyle(Color.posTinta)
                            .lineLimit(2).minimumScaleFactor(0.85)
                    }
                    .tarjetaPOS()
                    .padding(.horizontal)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(1...8, id: \.self) { n in
                            let ocupada = store.mesaOcupada(n)
                            let lista = store.pedidosDeMesa("Mesa \(n)")
                            let totalMesa = lista.reduce(0) { $0 + $1.total }
                            let fusionada = (store.cuentaDeMesa("Mesa \(n)")?.mesas.count ?? 0) > 1
                            Button {
                                mesaSeleccionada = n
                                mesaAbierta = MesaIdentidad(numero: n)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: ocupada ? "person.2.fill" : "chair.fill")
                                            .font(.title3)
                                        Spacer()
                                        Text(ocupada ? "OCUPADA" : "LIBRE")
                                            .font(.caption2).bold()
                                            .lineLimit(1)
                                            .padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(Color.white.opacity(0.30))
                                            .cornerRadius(20)
                                    }
                                    Text("Mesa \(n)")
                                        .font(.title3).bold()
                                        .lineLimit(1).minimumScaleFactor(0.75)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("👤 \(store.meseroDeMesa("Mesa \(n)"))")
                                        .font(.caption).bold()
                                        .lineLimit(1).minimumScaleFactor(0.8)
                                    if fusionada {
                                        Text("🔗 Fusionada").font(.caption2).bold().lineLimit(1)
                                    }
                                    if ocupada {
                                        Text(mxn(totalMesa)).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                                        if let fecha = lista.first?.fecha {
                                            Text("desde \(horaCorta(fecha))").font(.caption).lineLimit(1)
                                        }
                                    } else {
                                        Text("Lista para recibir").font(.caption).lineLimit(1)
                                    }
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(ocupada
                                    ? LinearGradient(colors: [.posNaranja, .posRojo], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [.posVerde, Color(red: 0.10, green: 0.55, blue: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .cornerRadius(20)
                                .shadow(color: (ocupada ? Color.posRojo : Color.posVerde).opacity(0.35), radius: 10, x: 0, y: 5)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)

                    // Cuentas abiertas: quedan abiertas, se les sigue agregando.
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("🧾 Cuentas abiertas").font(.title2).bold().lineLimit(1).minimumScaleFactor(0.8)
                            Spacer()
                            Button("Fusionar mesas") { mostrarFusionar = true }
                                .buttonStyle(.bordered)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        if store.cuentasAbiertas.isEmpty {
                            Text("No hay cuentas abiertas. Toca una mesa y pide algo.")
                                .foregroundStyle(.secondary).font(.callout)
                        }
                        ForEach(store.cuentasAbiertas) { cuenta in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cuenta.titulo).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                                    Text("\(store.pedidosDeCuenta(cuenta).count) pedido(s) · \(mxn(store.totalDeCuenta(cuenta)))")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Button("Abrir") {
                                    if let primera = cuenta.mesas.first, let n = Int(primera.replacingOccurrences(of: "Mesa ", with: "")) {
                                        mesaSeleccionada = n; mesaAbierta = MesaIdentidad(numero: n)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            Divider()
                        }
                        Text("Una cuenta NO se cierra al pedir una vez: queda abierta y se le sigue agregando. Se cierra solo cuando tú decides, en Cerrar cuenta.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tarjetaPOS()
                    .padding(.horizontal)

                    // Resumen de la mesa seleccionada (sin abrirla).
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "receipt.fill").foregroundStyle(Color.posNaranja)
                            Text("Mesa \(mesaSeleccionada)").font(.title2).bold().lineLimit(1).minimumScaleFactor(0.8)
                            Spacer()
                            let lista = store.pedidosDeMesa("Mesa \(mesaSeleccionada)")
                            Text("\(lista.count) pedido(s)").font(.caption).bold()
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.posNaranja.opacity(0.15)).cornerRadius(20)
                        }
                        let lista = store.pedidosDeMesa("Mesa \(mesaSeleccionada)")
                        if lista.isEmpty {
                            Text("Sin comanda. Toca la mesa para abrir su cuenta y agregar bebidas.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(lista) { pedido in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Pedido #\(pedido.numero)").font(.headline).lineLimit(1)
                                    Spacer()
                                    Text(pedido.estado.titulo).font(.caption).bold()
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(colorEstado(pedido.estado).opacity(0.20))
                                        .foregroundStyle(colorEstado(pedido.estado))
                                        .cornerRadius(20)
                                }
                                ForEach(pedido.items) { item in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.nombre).lineLimit(2)
                                            Text(mxn(item.subtotal)).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        CantidadStepperView(cantidad: item.cantidad) { delta in
                                            store.cambiarCantidadEnPedido(pedido, item: item, delta: delta)
                                        }
                                    }
                                }
                                Text("Total: \(mxn(pedido.total))").bold()
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                        if !lista.isEmpty {
                            let subtotal = lista.reduce(0) { $0 + $1.total }
                            Text("Cuenta total: \(mxn(subtotal))").font(.title2).bold().lineLimit(1).minimumScaleFactor(0.8)
                            Button("🧾 Cerrar cuenta") { mostrarCerrar = true }
                                .botonPOS()
                        } else {
                            Button("🍺 Abrir cuenta de la Mesa \(mesaSeleccionada)") { mesaAbierta = MesaIdentidad(numero: mesaSeleccionada) }
                                .botonPOS()
                        }
                    }
                    .tarjetaPOS()
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color.posFondo)
            .navigationTitle("Mesas")
            .navigationBarTitleDisplayMode(.inline)
            .barraTecladoListo()
            .onTapGesture { hideKeyboard() }
            .sheet(item: $mesaAbierta) { identidad in
                MesaDetalleView(numero: identidad.numero)
            }
            .sheet(isPresented: $mostrarFusionar) { FusionarMesasView() }
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
    private func horaCorta(_ fecha: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short
        return f.string(from: fecha)
    }
}

struct MesaIdentidad: Identifiable {
    var id: Int { numero }
    var numero: Int
}

/// Detalle de una mesa: su cuenta ABIERTA. Tocar una mesa abre esto:
/// ver la cuenta, agregar bebidas/botanas, mover la mesa y cerrar cuando tú decidas.
struct MesaDetalleView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss
    var numero: Int
    @State private var mostrarCerrar = false
    @State private var ticketCerrado: Ticket? = nil
    @State private var mesaDestino = 1
    @State private var mensaje = ""

    var mesa: String { "Mesa \(numero)" }
    var lista: [Pedido] { store.pedidosDeMesa(mesa) }
    var total: Double { lista.reduce(0) { $0 + $1.total } }
    var cuenta: CuentaAbierta? { store.cuentaDeMesa(mesa) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(mesa).font(.largeTitle).bold().lineLimit(1).minimumScaleFactor(0.7)
                        Spacer()
                        Text(lista.isEmpty ? "LIBRE" : "ABIERTA").font(.headline).bold()
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(lista.isEmpty ? Color.posVerde.opacity(0.2) : Color.posNaranja.opacity(0.2))
                            .cornerRadius(20)
                    }
                    if let cuenta = cuenta, cuenta.mesas.count > 1 {
                        Text("🔗 Cuenta fusionada: \(cuenta.titulo)")
                            .font(.callout).bold().foregroundStyle(Color.posNaranja)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("👤 Mesero que atiende").font(.headline)
                        Picker("Mesero", selection: Binding(
                            get: { store.meseroPorMesa[mesa] ?? "Sin mesero" },
                            set: { store.asignarMesero($0, a: mesa) }
                        )) {
                            Text("Sin mesero").tag("Sin mesero")
                            ForEach(store.meseros, id: \.self) { m in Text(m).tag(m) }
                        }
                        .pickerStyle(.menu)
                        Text("Mesero actual: \(store.meseroDeMesa(mesa))")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .tarjetaPOS()
                    Text("Cuenta total: \(mxn(total))").font(.title2).bold().lineLimit(1).minimumScaleFactor(0.8)
                    if lista.isEmpty {
                        Text("Sin comanda todavía. Agrega bebidas o botanas abajo, la cuenta queda abierta.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(lista) { pedido in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Pedido #\(pedido.numero)").font(.headline).lineLimit(1)
                                Spacer()
                                Text(pedido.estado.titulo).font(.caption).bold()
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(colorEstado(pedido.estado).opacity(0.20))
                                    .foregroundStyle(colorEstado(pedido.estado))
                                    .cornerRadius(20)
                            }
                            ForEach(pedido.items) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.nombre).lineLimit(2)
                                        Text(mxn(item.subtotal)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    CantidadStepperView(cantidad: item.cantidad) { delta in
                                        store.cambiarCantidadEnPedido(pedido, item: item, delta: delta)
                                    }
                                }
                            }
                            Text("Total: \(mxn(pedido.total))").bold()
                        }
                        .tarjetaPOS()
                    }
                    Text("➕ Agregar a la cuenta").font(.title2).bold()
                    Text("Toca un producto y se suma a la cuenta, sin cerrarla.")
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(store.menu) { plato in
                        HStack(spacing: 10) {
                            Text(iconoCategoria(plato.categoria)).font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plato.nombre).font(.headline).lineLimit(2)
                                Text("\(mxn(plato.precio)) · \(plato.vaABarra ? "Barra" : "Cocina")")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button("Agregar") {
                                store.agregarItemAMesa(mesa, plato: plato)
                                mensaje = "Agregado a \(mesa): \(plato.nombre)"
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .tarjetaPOS()
                    }
                    if !mensaje.isEmpty {
                        Text(mensaje).font(.callout).foregroundStyle(.green)
                    }
                    Text("Mover esta mesa a otra cuenta").font(.title2).bold()
                    HStack {
                        Picker("Mover a", selection: $mesaDestino) {
                            ForEach(1...8, id: \.self) { n in Text("Mesa \(n)").tag(n) }
                        }
                        .pickerStyle(.menu)
                        Button("Mover") {
                            store.moverMesa(mesa, a: "Mesa \(mesaDestino)")
                            mensaje = "Mesa movida a Mesa \(mesaDestino)."
                        }
                        .buttonStyle(.bordered)
                    }
                    if !lista.isEmpty {
                        Button("🧾 Cerrar cuenta") { mostrarCerrar = true }
                            .botonPOS()
                        Text("Cerrar es solo cuando tú decides. Mientras tanto la cuenta sigue abierta.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Cerrar") { dismiss() }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.gray.opacity(0.15)).cornerRadius(14)
                }
                .padding()
            }
            .background(Color.posFondo)
            .navigationTitle(mesa)
            .navigationBarTitleDisplayMode(.inline)
            .barraTecladoListo()
            .onTapGesture { hideKeyboard() }
            .sheet(isPresented: $mostrarCerrar) {
                CerrarCuentaView(mesa: mesa) { ticket in
                    ticketCerrado = ticket
                }
            }
            .sheet(item: $ticketCerrado) { ticket in
                TicketView(ticket: ticket)
            }
        }
    }
}

/// Fusionar mesas: elige 2 o más y se cobran en una sola cuenta.
struct FusionarMesasView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss
    @State private var seleccionadas: Set<Int> = []
    @State private var mensaje = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Elige 2 o más mesas para juntarlas en una sola cuenta.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(1...8, id: \.self) { n in
                    Button {
                        if seleccionadas.contains(n) { seleccionadas.remove(n) } else { seleccionadas.insert(n) }
                    } label: {
                        HStack {
                            Image(systemName: seleccionadas.contains(n) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(seleccionadas.contains(n) ? Color.posNaranja : .gray)
                            Text("Mesa \(n)").font(.headline)
                            Spacer()
                            Text(store.mesaOcupada(n) ? mxn(store.pedidosDeMesa("Mesa \(n)").reduce(0) { $0 + $1.total }) : "Libre")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.white).cornerRadius(14)
                    }
                    .buttonStyle(.plain)
                }
                if !mensaje.isEmpty { Text(mensaje).font(.callout).foregroundStyle(.green) }
                Button("🔗 Fusionar en una cuenta") {
                    let mesas = seleccionadas.sorted().map { "Mesa \($0)" }
                    if let cuenta = store.fusionarMesas(mesas) {
                        mensaje = "Fusionadas: \(cuenta.titulo). Se cobran juntas."
                    } else {
                        mensaje = "Elige al menos 2 mesas."
                    }
                }
                .botonPOS()
                Button("Cerrar") { dismiss() }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.gray.opacity(0.15)).cornerRadius(14)
                Spacer()
            }
            .padding()
            .background(Color.posFondo)
            .navigationTitle("Fusionar mesas")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Menú / Comanda (en mesa o para llevar, con descuento, cliente y escáner)

// MARK: - Menú / Comanda (ordenado: tipo, mesa, buscar, platillos, carrito)

struct MenuView: View {
    @EnvironmentObject var store: DataStore
    @State private var mesa: Int = 1
    @State private var tipoPedido = "Mesa"
    @State private var filtroDestino = "Todo"
    @State private var busqueda = ""
    @State private var carrito: [PedidoItem] = []
    @State private var mensaje = ""
    @State private var variante = ""
    @State private var descuentoTexto = ""
    @State private var descuentoEsPorcentaje = true
    @State private var clienteSeleccionado: UUID? = nil
    @State private var direccion = ""
    @State private var telefono = ""
    @State private var mostrarEscaner = false
    @State private var codigoManual = ""
    @State private var mostrarImportarMenu = false
    @State private var resultadoImport = ""
    @State private var menuEditando: MenuItem? = nil
    @State private var mostrarAgregarMenu = false

    var subtotal: Double { carrito.reduce(0) { $0 + $1.subtotal } }
    var descuento: Double {
        let v = Double(descuentoTexto) ?? 0
        return descuentoEsPorcentaje ? subtotal * v / 100 : v
    }
    var total: Double { max(0, subtotal - descuento) }

    var menuFiltrado: [MenuItem] {
        store.menu.filter { plato in
            let porDestino: Bool = {
                switch filtroDestino {
                case "Bebidas": return plato.vaABarra
                case "Comida": return plato.vaACocina
                default: return true
                }
            }()
            let porBusqueda: Bool = {
                let q = busqueda.trimmingCharacters(in: .whitespaces).lowercased()
                guard !q.isEmpty else { return true }
                return plato.nombre.lowercased().contains(q) || (plato.codigo ?? "").lowercased().contains(q)
            }()
            return porDestino && porBusqueda
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 1. Tipo de pedido (fila desplazable, texto completo, sin cortar)
                    Text("1. Tipo de pedido").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(["Mesa", "Para llevar"], id: \.self) { tipo in
                                Button(tipo == "Mesa" ? "🍽️ En mesa" : "🛍️ Para llevar") {
                                    tipoPedido = tipo
                                }
                                .font(.callout).bold()
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(tipoPedido == tipo ? LinearGradient(colors: [.posNaranja, .posRojo], startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [Color.white, Color.white], startPoint: .leading, endPoint: .trailing))
                                .foregroundStyle(tipoPedido == tipo ? .white : .posTinta)
                                .cornerRadius(20)
                                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    // 2. Mesa (chips con nombre completo, sin "Mes...")
                    if tipoPedido == "Mesa" {
                        Text("2. Mesa").font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(1...8, id: \.self) { n in
                                    Button("Mesa \(n)") { mesa = n }
                                        .font(.callout).bold()
                                        .lineLimit(1)
                                        .padding(.horizontal, 16).padding(.vertical, 10)
                                        .background(mesa == n ? Color.posNaranja : Color.white)
                                        .foregroundStyle(mesa == n ? .white : .posTinta)
                                        .cornerRadius(20)
                                        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    } else {
                        Text("2. Para llevar").font(.headline)
                        Text("El pedido se prepara para llevar. Sin entrega a domicilio por ahora.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    // 3. Buscar / escanear (en vertical, botones completos)
                    Text("3. Buscar o escanear").font(.headline)
                    TextField("Buscar por nombre o código", text: $busqueda)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 10) {
                        Button("📷 Escanear código") { mostrarEscaner = true }
                            .buttonStyle(.bordered)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                        Button("Buscar") { buscarPorCodigo(codigoManual.isEmpty ? busqueda : codigoManual) }
                            .buttonStyle(.borderedProminent)
                            .lineLimit(1)
                    }
                    TextField("Variante (ej. Doble, sin hielo)", text: $variante)
                        .textFieldStyle(.roundedBorder)
                    Picker("Cliente (lealtad)", selection: $clienteSeleccionado) {
                        Text("Sin cliente").tag(nil as UUID?)
                        ForEach(store.clientes) { cliente in
                            Text("\(cliente.nombre) · \(cliente.puntos) pts").tag(cliente.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                    // Filtro Bebidas / Comida (la categoría decide Barra o Cocina)
                    Text("Ver").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(["Todo", "Bebidas", "Comida"], id: \.self) { f in
                                Button(f == "Todo" ? "Todo el menú" : f == "Bebidas" ? "🍹 Bebidas → Barra" : "🍗 Comida → Cocina") {
                                    filtroDestino = f
                                }
                                .font(.callout).bold()
                                .lineLimit(1).minimumScaleFactor(0.8)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(filtroDestino == f ? Color.posNaranja : Color.white)
                                .foregroundStyle(filtroDestino == f ? .white : .posTinta)
                                .cornerRadius(20)
                                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    // Acciones del menú: agregar, importar CSV, exportar CSV
                    HStack(spacing: 10) {
                        Button("➕ Agregar") { mostrarAgregarMenu = true }
                            .buttonStyle(.borderedProminent)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                        Button("📥 Importar CSV") { mostrarImportarMenu = true }
                            .buttonStyle(.bordered)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                        ShareLink(item: store.exportarMenuCSV(), subject: Text("Menú")) {
                            Text("📤 Exportar CSV")
                                .font(.callout).bold()
                                .lineLimit(1).minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.bordered)
                    }
                    if !resultadoImport.isEmpty {
                        Text(resultadoImport).font(.callout).foregroundStyle(.green)
                    }
                    // 4. Platillos en tarjetas (una por renglón, nada cortado)
                    Text("4. Bebidas y botanas").font(.headline)
                    if menuFiltrado.isEmpty {
                        Text("No hay nada con ese filtro. Quita la búsqueda o importa el menú por CSV.")
                            .foregroundStyle(.secondary).font(.callout)
                    }
                    ForEach(Array(Dictionary(grouping: menuFiltrado, by: { $0.categoria }).keys.sorted()), id: \.self) { cat in
                        Text(cat).font(.title3).bold()
                        ForEach(menuFiltrado.filter { $0.categoria == cat }) { plato in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 10) {
                                    Text(iconoCategoria(cat)).font(.title2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(plato.nombre).font(.headline).lineLimit(2)
                                        Text("\(mxn(plato.precio)) · \(plato.vaABarra ? "Barra" : "Cocina")\(plato.codigo.map { " · \($0)" } ?? "")")
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Button("Agregar") { agregar(plato) }
                                        .buttonStyle(.borderedProminent)
                                        .lineLimit(1)
                                }
                                HStack(spacing: 12) {
                                    Button("✏️ Editar") { menuEditando = plato }
                                        .font(.callout)
                                    Button("🗑️ Eliminar", role: .destructive) { store.eliminarMenu(plato) }
                                        .font(.callout)
                                    Spacer()
                                    Text(plato.categoria).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .tarjetaPOS()
                        }
                    }
                    // 5. Carrito con total grande
                    if !carrito.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("🧾 Tu comanda").font(.title2).bold()
                        ForEach(carrito) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.nombreCompleto).lineLimit(2)
                                    Text(mxn(item.subtotal)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                CantidadStepperView(cantidad: item.cantidad) { delta in
                                    cambiarCantidadCarrito(item, delta: delta)
                                }
                            }
                            .font(.callout)
                        }
                            HStack {
                                Text("Descuento")
                                Picker("", selection: $descuentoEsPorcentaje) {
                                    Text("%").tag(true)
                                    Text("$").tag(false)
                                }
                                .pickerStyle(.segmented).frame(width: 110)
                                TextField("0", text: $descuentoTexto)
                                    .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(width: 80)
                                Spacer()
                                Text("-\(mxn(descuento))")
                            }
                            Text("Total: \(mxn(total))").font(.largeTitle).bold().lineLimit(1).minimumScaleFactor(0.7)
                            Button(enviarTexto()) {
                                let mesaTexto = tipoPedido == "Mesa" ? "Mesa \(mesa)" : tipoPedido
                                let cliente = store.clientes.first { $0.id == clienteSeleccionado }
                                store.crearPedidoCompleto(mesa: mesaTexto, tipo: "Mesa", tipoPedido: tipoPedido, items: carrito, descuento: descuento, clienteId: clienteSeleccionado, clienteNombre: cliente?.nombre ?? "", direccion: direccion, telefono: telefono)
                                mensaje = "Pedido enviado a Barra y Cocina. La cuenta queda abierta."
                                carrito = []; descuentoTexto = ""; direccion = ""; telefono = ""
                            }
                            .botonPOS()
                            if !mensaje.isEmpty {
                                Text(mensaje).font(.callout).foregroundStyle(.green)
                            }
                        }
                        .tarjetaPOS()
                    }
                }
                .padding()
            }
            .background(Color.posFondo)
            .navigationTitle("Menú / Comanda")
            .navigationBarTitleDisplayMode(.inline)
            .barraTecladoListo()
            .onTapGesture { hideKeyboard() }
            .sheet(isPresented: $mostrarEscaner) {
                EscanerCodigoView { codigo in
                    mostrarEscaner = false
                    buscarPorCodigo(codigo)
                }
            }
            .sheet(item: $menuEditando) { plato in
                MenuEditorView(plato: plato)
            }
            .sheet(isPresented: $mostrarAgregarMenu) {
                MenuEditorView(plato: nil)
            }
            .fileImporter(isPresented: $mostrarImportarMenu, allowedContentTypes: [.commaSeparatedText], allowsMultipleSelection: false) { resultado in
                importarMenuDesdeArchivo(resultado)
            }
        }
    }

    private func enviarTexto() -> String {
        switch tipoPedido {
        case "Mesa": return "Enviar a Barra y Cocina — Mesa \(mesa)"
        default: return "Enviar a Barra y Cocina — Para llevar"
        }
    }

    private func cambiarCantidadCarrito(_ item: PedidoItem, delta: Int) {
        guard let i = carrito.firstIndex(of: item) else { return }
        carrito[i].cantidad += delta
        if carrito[i].cantidad <= 0 { carrito.remove(at: i) }
    }

    private func agregar(_ plato: MenuItem) {
        let v = variante.trimmingCharacters(in: .whitespaces)
        if let i = carrito.firstIndex(where: { $0.nombre == plato.nombre && ($0.variante ?? "") == v }) {
            carrito[i].cantidad += 1
        } else {
            carrito.append(PedidoItem(nombre: plato.nombre, precio: plato.precio, cantidad: 1, variante: v.isEmpty ? nil : v, codigo: plato.codigo))
        }
        mensaje = ""
    }

    private func buscarPorCodigo(_ codigo: String) {
        let limpio = codigo.trimmingCharacters(in: .whitespaces)
        guard !limpio.isEmpty else { return }
        if let plato = store.menu.first(where: { ($0.codigo ?? "").lowercased() == limpio.lowercased() }) {
            agregar(plato)
            mensaje = "Encontrado por código: \(plato.nombre)"
        } else if let plato = store.menu.first(where: { $0.nombre.lowercased().contains(limpio.lowercased()) }) {
            agregar(plato)
            mensaje = "Encontrado: \(plato.nombre)"
        } else {
            mensaje = "No hay producto con el código \(limpio). Agrégalo en el menú con ese código."
        }
        codigoManual = ""
    }

    private func importarMenuDesdeArchivo(_ resultado: Result<[URL], Error>) {
        guard let url = try? resultado.get().first,
              url.startAccessingSecurityScopedResource(),
              let data = try? Data(contentsOf: url),
              let texto = String(data: data, encoding: .utf8) else {
            resultadoImport = "No se pudo leer el CSV. Revisa el archivo."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        let (agregados, actualizados, errores) = store.importarMenuCSVDetallado(texto)
        resultadoImport = "Menú: \(agregados) agregados, \(actualizados) actualizados." + (errores.isEmpty ? "" : " Errores: \(errores.joined(separator: " | "))")
    }
}

/// Editor de un producto del menú: nombre, precio, categoría, código y destino.
/// La categoría decide a dónde va: Bebidas/Cervezas/Cocteles -> Barra, Comida/Botanas -> Cocina.
struct MenuEditorView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss
    var plato: MenuItem?
    @State private var nombre = ""
    @State private var precioTexto = ""
    @State private var categoria = "Cervezas"
    @State private var codigo = ""
    @State private var destino = "Barra"
    let categorias = ["Cervezas", "Cocteles", "Destilados", "Shots", "Bebidas", "Botanas", "Comida"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Producto del bar") {
                    TextField("Nombre (ej. Mojito)", text: $nombre)
                    TextField("Precio en MXN", text: $precioTexto).keyboardType(.decimalPad)
                    Picker("Categoría", selection: $categoria) {
                        ForEach(categorias, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Código (ej. MOJ01, opcional)", text: $codigo)
                    Picker("Va a", selection: $destino) {
                        Text("🍹 Barra (bebidas)").tag("Barra")
                        Text("🍗 Cocina (comida)").tag("Cocina")
                    }
                    .pickerStyle(.segmented)
                    Text("Destino: \(destino). Si la categoría es de bebidas va a Barra, si es de comida va a Cocina.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(plato == nil ? "Agregar al menú" : "Guardar cambios") {
                    guard let precio = Double(precioTexto), !nombre.isEmpty else { return }
                    let dest: String? = (categoria.lowercased() == "bebidas" || categoria.lowercased() == "comida") ? destino : nil
                    if let plato = plato {
                        store.actualizarMenu(plato, nombre: nombre, precio: precio, categoria: categoria, codigo: codigo.isEmpty ? nil : codigo, destino: dest ?? destino)
                    } else {
                        store.agregarMenu(nombre: nombre, precio: precio, categoria: categoria, codigo: codigo.isEmpty ? nil : codigo, destino: dest ?? destino)
                    }
                    dismiss()
                }
                .botonPOS()
                .listRowBackground(Color.clear)
            }
            .navigationTitle(plato == nil ? "Agregar producto" : "Editar producto")
            .navigationBarTitleDisplayMode(.inline)
            .barraTecladoListo()
            .onAppear {
                if let plato = plato {
                    nombre = plato.nombre; precioTexto = String(format: "%.0f", plato.precio)
                    categoria = plato.categoria; codigo = plato.codigo ?? ""
                    destino = plato.vaABarra ? "Barra" : "Cocina"
                }
            }
        }
    }
}

// MARK: - Escáner de código de barras (cámara, AVFoundation)

struct EscanerCodigoView: View {
    var alEncontrar: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var codigo = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Apunta la cámara al código de barras del platillo.")
                    .multilineTextAlignment(.center).padding()
                EscanerCamaraView(alEncontrar: alEncontrar)
                    .frame(height: 320).cornerRadius(16).padding(.horizontal)
                Text("O escríbelo a mano:")
                HStack {
                    TextField("Código", text: $codigo).textFieldStyle(.roundedBorder)
                    Button("Buscar") { if !codigo.isEmpty { alEncontrar(codigo) } }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                Button("Cancelar") { dismiss() }.padding()
            }
            .navigationTitle("Escanear código")
        }
    }
}

struct EscanerCamaraView: UIViewControllerRepresentable {
    var alEncontrar: (String) -> Void
    func makeUIViewController(context: Context) -> EscanerVC {
        EscanerVC(alEncontrar: alEncontrar)
    }
    func updateUIViewController(_ vc: EscanerVC, context: Context) {}
}

final class EscanerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var alEncontrar: (String) -> Void
    private let sesion = AVCaptureSession()
    private var yaEncontro = false

    init(alEncontrar: @escaping (String) -> Void) {
        self.alEncontrar = alEncontrar
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) no usado") }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let camara = AVCaptureDevice.default(for: .video),
              let entrada = try? AVCaptureDeviceInput(device: camara),
              sesion.canAddInput(entrada) else { return }
        sesion.addInput(entrada)
        let salida = AVCaptureMetadataOutput()
        guard sesion.canAddOutput(salida) else { return }
        sesion.addOutput(salida)
        salida.setMetadataObjectsDelegate(self, queue: .main)
        salida.metadataObjectTypes = [.ean8, .ean13, .code128, .qr, .upce]
        let capa = AVCaptureVideoPreviewLayer(session: sesion)
        capa.frame = view.bounds
        capa.videoGravity = .resizeAspectFill
        view.layer.addSublayer(capa)
        sesion.startRunning()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.layer.sublayers?.first?.frame = view.bounds
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !yaEncontro,
              let objeto = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let codigo = objeto.stringValue else { return }
        yaEncontro = true
        sesion.stopRunning()
        alEncontrar(codigo)
    }
}

// MARK: - Barra (solo bebidas) y Cocina (solo comida)

/// Una estación: Barra muestra solo los items de bebidas de cada pedido,
/// Cocina solo los de comida. Al enviar, el pedido se parte solo por categoría.
struct EstacionView: View {
    @EnvironmentObject var store: DataStore
    var esBarra: Bool
    @State private var pedidoParaAgregar: Pedido? = nil

    var titulo: String { esBarra ? "Barra" : "Cocina" }
    var icono: String { esBarra ? "flame" : "fork.knife" }
    var pedidos: [Pedido] {
        store.pedidosActivos.filter { esBarra ? store.pedidoTieneBarra($0) : store.pedidoTieneCocina($0) }
    }
    func itemsDe(_ pedido: Pedido) -> [PedidoItem] {
        esBarra ? store.itemsDeBarra(pedido) : store.itemsDeCocina(pedido)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach([EstadoPedido.pendiente, .cocina, .listo], id: \.self) { estado in
                    let lista = pedidos.filter { $0.estado == estado }
                    Section("\(estado.titulo) (\(lista.count))") {
                        if lista.isEmpty {
                            Text("Nada \(estado.titulo.lowercased()) en \(titulo.lowercased()).").foregroundStyle(.secondary)
                        }
                        ForEach(lista) { pedido in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Pedido #\(pedido.numero) · \(pedido.mesa)")
                                        .font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                                    Spacer()
                                    Text("⏱ \(store.minutosPedido(pedido)) min")
                                        .font(.caption).bold()
                                        .padding(6)
                                        .background(store.minutosPedido(pedido) >= 15 ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
                                        .cornerRadius(8)
                                }
                                Text(pedido.tipoPedido)
                                    .font(.caption).foregroundStyle(.secondary)
                                if !pedido.clienteNombre.isEmpty {
                                    Text("Cliente: \(pedido.clienteNombre)").font(.caption).lineLimit(1)
                                }
                                ForEach(itemsDe(pedido)) { item in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.nombreCompleto).lineLimit(2)
                                            Text(mxn(item.subtotal)).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        CantidadStepperView(cantidad: item.cantidad) { delta in
                                            store.cambiarCantidadEnPedido(pedido, item: item, delta: delta)
                                        }
                                    }
                                }
                                HStack(spacing: 10) {
                                    Button("➕ Agregar") { pedidoParaAgregar = pedido }
                                        .buttonStyle(.bordered)
                                        .lineLimit(1).minimumScaleFactor(0.8)
                                    if let sig = pedido.estado.siguiente {
                                        Button(sig == .cobrado ? "Marcar cobrado" : "Pasar a \(sig.titulo)") {
                                            store.avanzar(pedido)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .lineLimit(1).minimumScaleFactor(0.8)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle(titulo)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $pedidoParaAgregar) { pedido in
                AgregarAPedidoView(pedido: pedido, soloBebidas: esBarra)
            }
        }
    }
}

struct BarraView: View {
    var body: some View { EstacionView(esBarra: true) }
}

struct CocinaView: View {
    var body: some View { EstacionView(esBarra: false) }
}

/// Agregar a un pedido ya enviado, desde Barra o Cocina, sin volver a Mesas.
/// Solo muestra los productos de esa estación (bebidas en Barra, comida en Cocina).
struct AgregarAPedidoView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss
    var pedido: Pedido
    var soloBebidas: Bool
    @State private var mensaje = ""

    var productos: [MenuItem] {
        store.menu.filter { $0.vaABarra == soloBebidas }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pedido #\(pedido.numero) · \(pedido.mesa)")
                        .font(.title2).bold().lineLimit(1).minimumScaleFactor(0.8)
                    Text(soloBebidas ? "Solo bebidas (Barra)" : "Solo comida (Cocina)")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Lo que ya lleva:").font(.headline)
                    ForEach(pedido.items) { item in
                        Text("\(item.cantidad) × \(item.nombre)").lineLimit(1)
                    }
                    Text("➕ Agregar").font(.headline)
                    if productos.isEmpty {
                        Text("No hay productos de esta estación en el menú. Agrégalos en Menú o por CSV.")
                            .foregroundStyle(.secondary).font(.callout)
                    }
                    ForEach(productos) { plato in
                        HStack(spacing: 10) {
                            Text(iconoCategoria(plato.categoria)).font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plato.nombre).font(.headline).lineLimit(2)
                                Text(mxn(plato.precio)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Agregar") {
                                store.agregarItemAPedido(pedido, plato: plato)
                                mensaje = "Agregado al pedido #\(pedido.numero): \(plato.nombre)"
                            }
                            .buttonStyle(.borderedProminent)
                            .lineLimit(1)
                        }
                        .tarjetaPOS()
                    }
                    if !mensaje.isEmpty {
                        Text(mensaje).font(.callout).foregroundStyle(.green)
                    }
                    Button("Listo") { dismiss() }
                        .botonPOS()
                }
                .padding()
            }
            .background(Color.posFondo)
            .navigationTitle("Agregar al pedido")
            .navigationBarTitleDisplayMode(.inline)
            .barraTecladoListo()
        }
    }
}

// MARK: - Inventario


struct InventarioView: View {
    @EnvironmentObject var store: DataStore
    @State private var nombre = ""
    @State private var unidad = "pzas"
    @State private var stockTexto = ""
    @State private var minimoTexto = ""
    @State private var csvTexto = ""
    @State private var mensajeImport = ""
    @State private var mostrarImportar = false
    @State private var inventarioEditando: InventarioItem? = nil
    @State private var mostrarAgregar = false

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
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.nombre).font(.headline).lineLimit(2)
                                    Text("\(item.stock, specifier: "%.0f") \(item.unidad) · mínimo \(item.minimo, specifier: "%.0f")")
                                        .font(.caption)
                                        .foregroundStyle(item.bajoStock ? .red : .secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button("-1") { store.cambiarStock(item, delta: -1) }
                                    .buttonStyle(.bordered)
                                Button("+1") { store.cambiarStock(item, delta: 1) }
                                    .buttonStyle(.bordered)
                            }
                            ProgressView(value: min(1, item.stock / max(1, item.minimo * 2)))
                                .tint(item.bajoStock ? .red : .posVerde)
                            HStack(spacing: 16) {
                                Button("✏️ Editar") { inventarioEditando = item }
                                    .font(.callout)
                                Button("🗑️ Eliminar", role: .destructive) { store.eliminarInventario(item) }
                                    .font(.callout)
                                Spacer()
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                Section("Importar / exportar (CSV)") {
                    Text("Sube un archivo CSV con líneas: Nombre,unidad,stock,minimo. Ejemplo: Ron blanco,botella,12,2. Sin duplicar por nombre.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button("📥 Importar CSV") { mostrarImportar = true }
                            .buttonStyle(.borderedProminent)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                        ShareLink(item: store.exportarInventarioCSV(), subject: Text("Inventario")) {
                            Text("📤 Exportar CSV")
                                .font(.callout).bold()
                                .lineLimit(1).minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("O pega el CSV aquí:")
                        .font(.callout).foregroundStyle(.secondary)
                    TextField("Nombre,unidad,stock,minimo", text: $csvTexto, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    Button("Importar lo pegado") {
                        let (a, u, e) = store.importarInventarioCSVDetallado(csvTexto)
                        mensajeImport = "Inventario: \(a) agregados, \(u) actualizados." + (e.isEmpty ? "" : " Errores: \(e.joined(separator: " | "))")
                        csvTexto = ""
                    }
                    .buttonStyle(.borderedProminent)
                    if !mensajeImport.isEmpty { Text(mensajeImport).foregroundStyle(.green).font(.callout) }
                }
                Section("Agregar producto") {
                    TextField("Nombre (ej. Ron blanco)", text: $nombre)
                    TextField("Unidad (botella / pzas / kg / L)", text: $unidad)
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
            .navigationBarTitleDisplayMode(.inline)
            .barraTecladoListo()
            .fileImporter(isPresented: $mostrarImportar, allowedContentTypes: [.commaSeparatedText], allowsMultipleSelection: false) { resultado in
                guard let url = try? resultado.get().first,
                      url.startAccessingSecurityScopedResource(),
                      let data = try? Data(contentsOf: url),
                      let texto = String(data: data, encoding: .utf8) else {
                    mensajeImport = "No se pudo leer el CSV. Revisa el archivo."
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                let (a, u, e) = store.importarInventarioCSVDetallado(texto)
                mensajeImport = "Inventario: \(a) agregados, \(u) actualizados." + (e.isEmpty ? "" : " Errores: \(e.joined(separator: " | "))")
            }
            .sheet(item: $inventarioEditando) { item in
                InventarioEditorView(item: item)
            }
        }
    }
}

/// Editor de un producto de inventario: nombre, unidad, stock y mínimo.
struct InventarioEditorView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss
    var item: InventarioItem
    @State private var nombre = ""
    @State private var unidad = ""
    @State private var stockTexto = ""
    @State private var minimoTexto = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Producto") {
                    TextField("Nombre", text: $nombre)
                    TextField("Unidad (botella / pzas / kg / L)", text: $unidad)
                    TextField("Stock", text: $stockTexto).keyboardType(.decimalPad)
                    TextField("Mínimo", text: $minimoTexto).keyboardType(.decimalPad)
                }
                Button("Guardar cambios") {
                    guard let stock = Double(stockTexto), let minimo = Double(minimoTexto), !nombre.isEmpty else { return }
                    store.actualizarInventario(item, nombre: nombre, unidad: unidad, stock: stock, minimo: minimo)
                    dismiss()
                }
                .botonPOS()
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Editar inventario")
            .navigationBarTitleDisplayMode(.inline)
            .barraTecladoListo()
            .onAppear {
                nombre = item.nombre; unidad = item.unidad
                stockTexto = String(format: "%.0f", item.stock); minimoTexto = String(format: "%.0f", item.minimo)
            }
        }
    }
}

// MARK: - Ventas del día (con devoluciones y exportar CSV)

struct VentasView: View {
    @EnvironmentObject var store: DataStore
    @State private var motivo = ""
    var body: some View {
        NavigationStack {
            List {
                Section("Hoy") {
                    Text("Total cobrado: \(mxn(store.ventasDelDia))")
                        .font(.title2).bold()
                    Text("Propinas: \(mxn(store.propinasDelDia))")
                    Text("Descuentos: \(mxn(store.descuentosDelDia))")
                    Text("Devoluciones: \(mxn(store.devolucionesDelDia))")
                    Text("Pedidos cobrados: \(store.pedidosCobrados.count)")
                    Text("Pedidos activos: \(store.pedidosActivos.count)")
                    ShareLink(item: store.exportarVentasCSV(), subject: Text("Ventas")) {
                        Label("📤 Exportar ventas a CSV", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Section("Pedidos cobrados") {
                    if store.pedidosCobrados.isEmpty {
                        Text("Aún no hay ventas cobradas hoy.").foregroundStyle(.secondary)
                    }
                    ForEach(store.pedidosCobrados) { pedido in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Pedido #\(pedido.numero) · \(pedido.mesa)")
                                Spacer()
                                Text(mxn(pedido.totalConPropina)).bold()
                            }
                            Text("Comida \(mxn(pedido.total))" + (pedido.descuento > 0 ? " − descuento \(mxn(pedido.descuento))" : "") + " + propina \(mxn(pedido.propina)) · \(pedido.formaPago)")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                TextField("Motivo de devolución", text: $motivo)
                                    .textFieldStyle(.roundedBorder)
                                Button("↩️ Devolver") {
                                    store.devolverPedido(pedido, motivo: motivo)
                                    motivo = ""
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                Section("Devoluciones") {
                    let devueltos = store.pedidos.filter { $0.devuelto }
                    if devueltos.isEmpty {
                        Text("No hay devoluciones.").foregroundStyle(.secondary)
                    }
                    ForEach(devueltos) { pedido in
                        Text("Pedido #\(pedido.numero) · \(mxn(pedido.totalConPropina)) · \(pedido.motivoDevolucion)")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Ventas del día")
            .barraTecladoListo()
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
    @State private var nombreCliente = ""
    @State private var direccionCliente = ""
    @State private var telefonoCliente = ""

    var total: Double { carrito.reduce(0) { $0 + $1.subtotal } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Pide desde tu iPhone. Tu pedido llega directo a Barra y Cocina.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Picker("¿Dónde estás?", selection: $modo) {
                    Text("En mesa").tag("Mesa")
                    Text("Para llevar").tag("Para llevar")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                TextField("Tu nombre", text: $nombreCliente)
                    .textFieldStyle(.roundedBorder).padding(.horizontal)
                if modo == "Mesa" {
                    Picker("Mesa", selection: $mesaCliente) {
                        ForEach(1...8, id: \.self) { n in Text("Mesa \(n)").tag(n) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }
                List {
                    ForEach(store.menu) { plato in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Color.posNaranja.opacity(0.15)).frame(width: 48, height: 48)
                                Text(iconoCategoria(plato.categoria)).font(.title3)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plato.nombre).font(.headline)
                                Text(mxn(plato.precio)).font(.title3).bold().foregroundStyle(Color.posRojo)
                            }
                            Spacer()
                            Button("Agregar") {
                                if let i = carrito.firstIndex(where: { $0.nombre == plato.nombre }) {
                                    carrito[i].cantidad += 1
                                } else {
                                    carrito.append(PedidoItem(nombre: plato.nombre, precio: plato.precio, cantidad: 1))
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .listRowBackground(Color.white)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.posFondo)
                if !carrito.isEmpty {
                    VStack(spacing: 8) {
                        Text("Tu pedido: \(mxn(total))").font(.title2).bold()
                        Button("Enviar mi pedido") {
                            let mesa = modo == "Mesa" ? "Mesa \(mesaCliente)" : modo
                            store.crearPedidoCompleto(mesa: mesa, tipo: "Cliente", tipoPedido: modo, items: carrito, descuento: 0, clienteId: nil, clienteNombre: nombreCliente, direccion: direccionCliente, telefono: telefonoCliente)
                            mensaje = "¡Pedido enviado! Llega a Barra y Cocina en un momento."
                            carrito = []
                        }
                        .botonPOS()
                        if !mensaje.isEmpty {
                            Text(mensaje).foregroundStyle(.green).font(.callout)
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
                    .padding()
                }
            }
            .background(Color.posFondo)
            .navigationTitle("Pedir (Cliente)")
            .barraTecladoListo()
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
    @State private var descuentoTexto = ""
    @State private var descuentoEsPorcentaje = true
    @State private var formaPago = "Efectivo"

    var ticketBase: Ticket? { store.ticketParaMesa(mesa) }
    var subtotal: Double { ticketBase?.subtotal ?? 0 }
    var propina: Double {
        if usarManual { return Double(propinaManual) ?? 0 }
        return subtotal * Double(porcentaje) / 100
    }
    var descuentoMonto: Double {
        let v = Double(descuentoTexto) ?? 0
        return descuentoEsPorcentaje ? subtotal * v / 100 : v
    }
    var total: Double { max(0, subtotal - descuentoMonto) + propina }

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
                    HStack(spacing: 10) {
                        ForEach([0, 10, 15, 20], id: \.self) { p in
                            Button(p == 0 ? "Sin propina" : "\(p)%") {
                                porcentaje = p; usarManual = false
                            }
                            .font(.headline).bold()
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(!usarManual && porcentaje == p
                                ? LinearGradient(colors: [.posNaranja, .posRojo], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [Color.white, Color.white], startPoint: .leading, endPoint: .trailing))
                            .foregroundStyle(!usarManual && porcentaje == p ? .white : .posTinta)
                            .cornerRadius(14)
                            .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 3)
                        }
                    }
                    Toggle("Otra cantidad", isOn: $usarManual)
                    if usarManual {
                        TextField("Propina en pesos (ej. 25)", text: $propinaManual)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                    }
                    Text("Propina: \(mxn(propina))").font(.title3)

                    Text("Descuento (Loyverse)").font(.title2).bold()
                    HStack {
                        Picker("", selection: $descuentoEsPorcentaje) {
                            Text("%").tag(true)
                            Text("$").tag(false)
                        }
                        .pickerStyle(.segmented).frame(width: 110)
                        TextField("0", text: $descuentoTexto)
                            .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(width: 90)
                        Spacer()
                        Text("-\(mxn(descuentoMonto))")
                    }
                    Text("Forma de pago").font(.title2).bold()
                    Picker("Forma de pago", selection: $formaPago) {
                        Text("💵 Efectivo").tag("Efectivo")
                        Text("💳 Tarjeta").tag("Tarjeta")
                        Text("🏦 Transferencia").tag("Transferencia")
                    }
                    .pickerStyle(.segmented)

                    Text("3. ¿Quién atiende?").font(.title2).bold()
                    TextField("Mesero", text: $mesero)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)

                    Divider()
                    Text("TOTAL A COBRAR: \(mxn(total))").font(.title).bold()
                    Button("✅ Cerrar cuenta y ver ticket") {
                        let ticket = store.cerrarMesa(mesa, propina: propina, mesero: mesero.isEmpty ? store.negocio.mesero : mesero, descuento: descuentoMonto, formaPago: formaPago)
                        if let ticket = ticket {
                            alCerrar(ticket)
                            dismiss()
                        }
                    }
                    .botonPOS()
                    .disabled(ticketBase == nil)
                    Button("Cancelar") { dismiss() }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding()
            }
            .navigationTitle("Cerrar cuenta")
            .barraTecladoListo()
            .onAppear {
                let m = store.meseroDeMesa(mesa)
                mesero = m == "Sin mesero" ? store.negocio.mesero : m
            }
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
                        .botonPOS()
                    ShareLink(item: textoTicket(ticket, negocio: store.negocio)) {
                        Label("Compartir ticket", systemImage: "square.and.arrow.up")
                    }
                    .botonPOS()
                    Button("Cerrar") { dismiss() }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding()
                .background(Color.white)
                .cornerRadius(24)
                .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 6)
                .padding()
            }
            .background(Color.posFondo)
            .navigationTitle("Ticket")
            .barraTecladoListo()
        }
    }
    private func fechaTicket(_ fecha: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: fecha)
    }
}


// MARK: - Caja (fondo, entradas/salidas, corte)

struct CajaView: View {
    @EnvironmentObject var store: DataStore
    @State private var concepto = ""
    @State private var montoTexto = ""
    @State private var tipoMovimiento = "salida"
    @State private var fondoTexto = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Corte de caja") {
                    Text("Efectivo en caja: \(mxn(store.efectivoEnCaja))").font(.title2).bold()
                    Text("Fondo inicial: \(mxn(store.fondoInicial))")
                    ForEach(store.ventasPorPago(), id: \.0) { forma, total in
                        HStack { Text(forma); Spacer(); Text(mxn(total)).bold() }
                    }
                    Text("Ventas hoy: \(mxn(store.ventasDelDia))")
                    Text("Devoluciones: \(mxn(store.devolucionesDelDia))")
                }
                Section("Fondo inicial") {
                    HStack {
                        TextField("Fondo en pesos", text: $fondoTexto).keyboardType(.decimalPad)
                        Button("Guardar fondo") {
                            store.fondoInicial = Double(fondoTexto) ?? store.fondoInicial
                            store.guardar()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                Section("Entrada / salida de efectivo") {
                    Picker("Tipo", selection: $tipoMovimiento) {
                        Text("💰 Entrada").tag("entrada")
                        Text("💸 Salida").tag("salida")
                    }
                    .pickerStyle(.segmented)
                    TextField("Concepto (ej. Compra de tortillas)", text: $concepto)
                    TextField("Monto", text: $montoTexto).keyboardType(.decimalPad)
                    Button("Registrar movimiento") {
                        store.registrarMovimiento(tipo: tipoMovimiento, concepto: concepto, monto: Double(montoTexto) ?? 0)
                        concepto = ""; montoTexto = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
                Section("Movimientos") {
                    if store.movimientos.isEmpty {
                        Text("Sin movimientos de caja todavía.").foregroundStyle(.secondary)
                    }
                    ForEach(store.movimientos) { mov in
                        HStack {
                            Text(mov.tipo == "entrada" ? "⬆️" : "⬇️")
                            VStack(alignment: .leading) {
                                Text(mov.concepto)
                                Text(fechaCortaMov(mov.fecha)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text((mov.tipo == "entrada" ? "+" : "-") + mxn(mov.monto))
                                .bold().foregroundStyle(mov.tipo == "entrada" ? .green : .red)
                        }
                    }
                }
            }
            .navigationTitle("Caja")
            .barraTecladoListo()
            .onAppear { fondoTexto = String(format: "%.0f", store.fondoInicial) }
        }
    }
    private func fechaCortaMov(_ fecha: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: fecha)
    }
}

// MARK: - Clientes y lealtad

struct ClientesView: View {
    @EnvironmentObject var store: DataStore
    @State private var nombre = ""
    @State private var telefono = ""
    @State private var clienteDetalle: Cliente? = nil

    var body: some View {
        NavigationStack {
            List {
                Section("Registrar cliente") {
                    Text("1 punto por cada $20 gastados. Los puntos se suman solos al cobrar.")
                        .font(.callout).foregroundStyle(.secondary)
                    TextField("Nombre", text: $nombre)
                    TextField("Teléfono", text: $telefono).keyboardType(.phonePad)
                    Button("➕ Agregar cliente") {
                        store.agregarCliente(nombre: nombre, telefono: telefono)
                        nombre = ""; telefono = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
                Section("Clientes (\(store.clientes.count))") {
                    if store.clientes.isEmpty {
                        Text("Sin clientes registrados.").foregroundStyle(.secondary)
                    }
                    ForEach(store.clientes) { cliente in
                        Button {
                            clienteDetalle = cliente
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(cliente.nombre).font(.headline)
                                    Text(cliente.telefono.isEmpty ? "Sin teléfono" : cliente.telefono)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("⭐ \(cliente.puntos) pts").bold()
                                    Text("\(cliente.visitas) visitas").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Clientes")
            .barraTecladoListo()
            .sheet(item: $clienteDetalle) { cliente in
                NavigationStack {
                    List {
                        Section("Historial") {
                            Text("Nombre: \(cliente.nombre)")
                            Text("Teléfono: \(cliente.telefono.isEmpty ? "—" : cliente.telefono)")
                            Text("Puntos: \(cliente.puntos)")
                            Text("Total gastado: \(mxn(cliente.totalGastado))")
                            Text("Visitas: \(cliente.visitas)")
                        }
                        Section("Sus pedidos") {
                            let lista = store.pedidos.filter { $0.clienteId == cliente.id || $0.clienteNombre == cliente.nombre }
                            if lista.isEmpty { Text("Sin pedidos registrados.").foregroundStyle(.secondary) }
                            ForEach(lista) { pedido in
                                Text("Pedido #\(pedido.numero) · \(pedido.mesa) · \(mxn(pedido.totalConPropina))")
                            }
                        }
                    }
                    .navigationTitle(cliente.nombre)
                }
            }
        }
    }
}

// MARK: - Reportes / analítica

struct ReportesView: View {
    @EnvironmentObject var store: DataStore
    var body: some View {
        NavigationStack {
            List {
                Section("Resumen") {
                    Text("Hoy: \(mxn(store.ventasDelDia))").font(.title2).bold()
                    Text("Últimos 7 días: \(mxn(store.ventasSemana))")
                    Text("Venta promedio: \(mxn(store.ventaPromedio))")
                    Text("Pedidos cobrados hoy: \(store.pedidosCobrados.count)")
                }
                Section("Por forma de pago") {
                    ForEach(store.ventasPorPago(), id: \.0) { forma, total in
                        HStack { Text(forma); Spacer(); Text(mxn(total)).bold() }
                    }
                }
                Section("Lo más vendido") {
                    let top = store.masVendidos()
                    if top.isEmpty {
                        Text("Aún no hay ventas.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(top.prefix(10)), id: \.0) { nombre, cantidad in
                        HStack {
                            Text("🏆 \(nombre)")
                            Spacer()
                            Text("\(cantidad) vendidos").bold()
                        }
                    }
                }
                Section("Exportar") {
                    ShareLink(item: store.exportarVentasCSV(), subject: Text("Reporte de ventas")) {
                        Label("📤 Exportar ventas a CSV (Excel)", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Reportes")
            .barraTecladoListo()
        }
    }
}

// MARK: - Red local (sincronizar varios iPhones por WiFi)

struct RedLocalView: View {
    @EnvironmentObject var store: DataStore
    // Observar red directamente: si solo se observa store, la lista de
    // dispositivos conectados no se actualiza en vivo.
    @ObservedObject var red: RedLocalSync

    var body: some View {
        NavigationStack {
            List {
                Section("WiFi local") {
                    Text("Todos los iPhones con esta app, en el mismo WiFi, se ven entre ellos y se sincronizan: pedidos, mesas, inventario y ventas. Sin internet y sin servidor.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Estado: \(red.estado)")
                        .font(.title3).bold()
                    Text("Conectado a: \(red.conectados.count) dispositivo(s)")
                    if let ultima = red.ultimaSync {
                        Text("Última sincronización: \(fechaCorta(ultima))")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Toggle("Encender red local", isOn: Binding(
                        get: { red.activa },
                        set: { nuevo in nuevo ? red.encender() : red.apagar() }
                    ))
                    .font(.title3)
                    Button("🔄 Enviar mi estado ahora") { store.enviarSync() }
                        .botonPOS()
                        .disabled(!red.activa)
                }
                Section("Dispositivos conectados") {
                    if red.conectados.isEmpty {
                        Text("Nadie conectado todavía. Enciende la red en los dos iPhones y acepta el permiso de red local.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(red.conectados, id: \.self) { nombre in
                        Label(nombre, systemImage: "iphone")
                    }
                }
                Section("Dispositivos cercanos") {
                    if red.encontrados.isEmpty {
                        Text("No se ve ningún iPhone cercano. Revisa que estén en el mismo WiFi, con WiFi y Bluetooth prendidos.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(red.encontrados, id: \.self) { nombre in
                        HStack {
                            Label(nombre, systemImage: "iphone")
                            Spacer()
                            Button("Conectar") { red.invitar(nombre) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                Section("Cómo probarlo con 2 iPhones") {
                    Text("1. Los dos en el mismo WiFi, con WiFi y Bluetooth prendidos.\n2. En los dos, pestaña Red local → Encender red local.\n3. Acepta el permiso de red local la primera vez.\n4. En uno, toca Conectar en el otro iPhone.\n5. Crea un pedido en uno: tiene que aparecer en Barra / Cocina del otro.")
                        .font(.callout)
                }
            }
            .navigationTitle("Red local")
            .barraTecladoListo()
        }
    }
    private func fechaCorta(_ fecha: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .none; f.timeStyle = .medium
        return f.string(from: fecha)
    }
}

// MARK: - Mi negocio (nombre, datos y logo)

struct NegocioView: View {
    @EnvironmentObject var store: DataStore
    @State private var foto: PhotosPickerItem? = nil
    @State private var nuevoMesero = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Tu bar") {
                    Text("Esto es lo que sale arriba del ticket.")
                        .font(.callout).foregroundStyle(.secondary)
                    TextField("Nombre del bar", text: $store.negocio.nombre)
                        .font(.title3)
                    TextField("Dirección", text: $store.negocio.direccion)
                    TextField("Teléfono", text: $store.negocio.telefono)
                        .keyboardType(.phonePad)
                    TextField("Mesero por defecto", text: $store.negocio.mesero)
                }
                Section("Meseros del bar") {
                    Text("Elige el mesero al abrir una mesa. En la tarjeta de cada mesa se ve quién la atiende, y en el ticket sale su nombre.")
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(store.meseros, id: \.self) { m in
                        HStack {
                            Text(m).font(.headline)
                            Spacer()
                            Button("Quitar", role: .destructive) { store.eliminarMesero(m) }
                        }
                    }
                    HStack {
                        TextField("Nombre del mesero nuevo", text: $nuevoMesero)
                        Button("Agregar") {
                            store.agregarMesero(nuevoMesero)
                            nuevoMesero = ""
                        }
                        .buttonStyle(.borderedProminent)
                    }
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
                        .botonPOS()
                }
            }
            .navigationTitle("Mi negocio")
            .barraTecladoListo()
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
