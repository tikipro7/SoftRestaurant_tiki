import SwiftUI
import Foundation
import PhotosUI
import UIKit
import MultipeerConnectivity
import AVFoundation

// Restaurante — app tipo Soft Restaurant para iPhone.
// Para el restaurante: mesas, comandas, cocina, inventario y ventas.
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
                                  clientes: clientes, movimientos: movimientos, fondoInicial: fondoInicial)
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
    /// Minutos que lleva un pedido activo desde que se creó (pantalla de cocina).
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

    func crearPedido(mesa: String, tipo: String, items: [PedidoItem]) {
        crearPedidoCompleto(mesa: mesa, tipo: tipo, tipoPedido: "Mesa", items: items, descuento: 0, clienteId: nil, clienteNombre: "", direccion: "", telefono: "")
    }

    /// Crea un pedido con descuento, cliente y domicilio (para llevar / a domicilio).
    func crearPedidoCompleto(mesa: String, tipo: String, tipoPedido: String, items: [PedidoItem], descuento: Double, clienteId: UUID?, clienteNombre: String, direccion: String, telefono: String) {
        guard !items.isEmpty else { return }
        var pedido = Pedido(numero: siguienteNumero, mesa: mesa, tipo: tipo, items: items, estado: .pendiente)
        pedido.descuento = descuento
        pedido.tipoPedido = tipoPedido
        pedido.clienteId = clienteId
        pedido.clienteNombre = clienteNombre
        pedido.direccionEntrega = direccion
        pedido.telefonoEntrega = telefono
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
        return Ticket(numero: lista.first!.numero, mesa: mesa, mesero: negocio.mesero,
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

    /// Importa inventario desde CSV (nombre,unidad,stock,minimo). Devuelve cuántos se agregaron.
    func importarInventarioCSV(_ texto: String) -> Int {
        var agregados = 0
        for linea in texto.components(separatedBy: .newlines) {
            let partes = linea.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "") }
            guard partes.count >= 4, partes[0].lowercased() != "nombre",
                  let stock = Double(partes[2]), let minimo = Double(partes[3]) else { continue }
            inventario.append(InventarioItem(nombre: partes[0], unidad: partes[1], stock: stock, minimo: minimo))
            agregados += 1
        }
        if agregados > 0 { guardar() }
        return agregados
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
        let datos = DatosGuardados(menu: menu, inventario: inventario, pedidos: pedidos, siguienteNumero: siguienteNumero, negocio: negocio, clientes: clientes, movimientos: movimientos, fondoInicial: fondoInicial)
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
        clientes = [Cliente(nombre: "Cliente frecuente", telefono: "", puntos: 10, totalGastado: 200, visitas: 2)]
        fondoInicial = 500
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
extension View {
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
    case "Tacos": return "🌮"
    case "Platos": return "🍲"
    case "Entradas": return "🥑"
    case "Bebidas": return "🥤"
    case "Postres": return "🍮"
    default: return "🍽️"
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
                RedLocalView(red: store.red)
                    .tabItem { Label("Red local", systemImage: "wifi") }
            }
        }
        .background(Color.posFondo)
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
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.tap.fill").foregroundStyle(.posNaranja)
                        Text("1. Toca una mesa  ·  2. Revisa su cuenta  ·  3. Cierra y cobra")
                            .font(.callout).bold().foregroundStyle(.posTinta)
                    }
                    .tarjetaPOS()
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(1...8, id: \.self) { n in
                            let ocupada = store.mesaOcupada(n)
                            let lista = store.pedidosDeMesa("Mesa \(n)")
                            let totalMesa = lista.reduce(0) { $0 + $1.total }
                            Button {
                                mesaSeleccionada = n
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: ocupada ? "person.2.fill" : "chair.fill")
                                            .font(.title2)
                                        Spacer()
                                        Text(ocupada ? "OCUPADA" : "LIBRE")
                                            .font(.caption2).bold()
                                            .padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(Color.white.opacity(0.30))
                                            .cornerRadius(20)
                                    }
                                    Text("Mesa \(n)").font(.title2).bold()
                                    if ocupada {
                                        Text(mxn(totalMesa)).font(.headline)
                                        if let fecha = lista.first?.fecha {
                                            Text("desde \(horaCorta(fecha))").font(.caption)
                                        }
                                    } else {
                                        Text("Lista para recibir").font(.caption)
                                    }
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(ocupada
                                    ? LinearGradient(colors: [.posNaranja, .posRojo], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [.posVerde, Color(red: 0.10, green: 0.55, blue: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .cornerRadius(20)
                                .shadow(color: (ocupada ? Color.posRojo : Color.posVerde).opacity(0.35), radius: 10, x: 0, y: 5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(mesaSeleccionada == n ? Color.white : Color.clear, lineWidth: 3)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "receipt.fill").foregroundStyle(.posNaranja)
                            Text("Mesa \(mesaSeleccionada)").font(.title2).bold()
                            Spacer()
                            let lista = store.pedidosDeMesa("Mesa \(mesaSeleccionada)")
                            Text("\(lista.count) pedido(s)").font(.caption).bold()
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.posNaranja.opacity(0.15)).cornerRadius(20)
                        }
                        let lista = store.pedidosDeMesa("Mesa \(mesaSeleccionada)")
                        if lista.isEmpty {
                            Text("Sin comanda. Agrega platillos en la pestaña Menú.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(lista) { pedido in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Pedido #\(pedido.numero)").font(.headline)
                                    Spacer()
                                    Text(pedido.estado.titulo).font(.caption).bold()
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(colorEstado(pedido.estado).opacity(0.20))
                                        .foregroundStyle(colorEstado(pedido.estado))
                                        .cornerRadius(20)
                                }
                                ForEach(pedido.items) { item in
                                    Text("\(item.cantidad) × \(item.nombre) — \(mxn(item.subtotal))")
                                }
                                Text("Total: \(mxn(pedido.total))").bold()
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                        if !lista.isEmpty {
                            let subtotal = lista.reduce(0) { $0 + $1.total }
                            Text("Cuenta total: \(mxn(subtotal))").font(.title2).bold()
                            Button("🧾 Cerrar cuenta") { mostrarCerrar = true }
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
                        Section {
                            ForEach(store.menu.filter { $0.categoria == cat }) { plato in
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(Color.posNaranja.opacity(0.15)).frame(width: 52, height: 52)
                                        Text(iconoCategoria(plato.categoria)).font(.title2)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(plato.nombre).font(.headline)
                                        Text(mxn(plato.precio)).font(.title3).bold().foregroundStyle(.posRojo)
                                    }
                                    Spacer()
                                    Button {
                                        agregar(plato)
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 36))
                                            .foregroundStyle(LinearGradient(colors: [.posNaranja, .posRojo], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .shadow(color: Color.posRojo.opacity(0.30), radius: 6, x: 0, y: 3)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 6)
                                .listRowBackground(Color.white)
                                .listRowSeparator(.hidden)
                            }
                        } header: {
                            Text(cat).font(.headline).bold().foregroundStyle(.posRojo)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.posFondo)

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
                        Text("Total: \(mxn(total))").font(.title2).bold()
                        Button("Enviar a cocina — Mesa \(mesa)") {
                            store.crearPedido(mesa: "Mesa \(mesa)", tipo: "Mesa", items: carrito)
                            mensaje = "Pedido enviado a cocina."
                            carrito = []
                        }
                        .botonPOS()
                        if !mensaje.isEmpty {
                            Text(mensaje).font(.callout).foregroundStyle(.green)
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
            ScrollView {
                VStack(spacing: 16) {
                    // Kanban por estado: Pendiente → En cocina → Listo.
                    ForEach([EstadoPedido.pendiente, .cocina, .listo], id: \.self) { estado in
                        let pedidos = store.pedidosActivos.filter { $0.estado == estado }
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: estado == .listo ? "checkmark.circle.fill" : estado == .cocina ? "flame.fill" : "clock.fill")
                                    .foregroundStyle(colorEstado(estado))
                                Text(estado.titulo).font(.title3).bold()
                                Spacer()
                                Text("\(pedidos.count)").font(.headline).bold()
                                    .padding(.horizontal, 12).padding(.vertical, 4)
                                    .background(colorEstado(estado).opacity(0.18))
                                    .foregroundStyle(colorEstado(estado))
                                    .cornerRadius(20)
                            }
                            if pedidos.isEmpty {
                                Text("Sin pedidos \(estado.titulo.lowercased()).").foregroundStyle(.secondary)
                            }
                            ForEach(pedidos) { pedido in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Pedido #\(pedido.numero) · \(pedido.mesa)").font(.headline)
                                        Spacer()
                                        Text(mxn(pedido.total)).font(.headline).bold().foregroundStyle(.posRojo)
                                    }
                                    ForEach(pedido.items) { item in
                                        Text("\(item.cantidad) × \(item.nombre)")
                                    }
                                    if let sig = pedido.estado.siguiente {
                                        Button(sig == .cobrado ? "Marcar cobrado" : "Pasar a \(sig.titulo)") {
                                            store.avanzar(pedido)
                                        }
                                        .botonPOS()
                                    }
                                }
                                .padding(12)
                                .background(colorEstado(estado).opacity(0.10))
                                .cornerRadius(16)
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(colorEstado(estado).opacity(0.35), lineWidth: 1.5))
                            }
                        }
                        .tarjetaPOS()
                        .padding(.horizontal)
                    }
                    if store.pedidosActivos.isEmpty {
                        Text("No hay pedidos en cocina.").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical)
            }
            .background(Color.posFondo)
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
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.nombre).font(.headline)
                                Text("\(item.stock, specifier: "%.0f") \(item.unidad) · mínimo \(item.minimo, specifier: "%.0f")")
                                    .font(.caption)
                                    .foregroundStyle(item.bajoStock ? .red : .secondary)
                                ProgressView(value: min(1, item.stock / max(1, item.minimo * 2)))
                                    .tint(item.bajoStock ? .red : .posVerde)
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
                Section {
                    VStack(spacing: 12) {
                        VStack(spacing: 4) {
                            Text("TOTAL COBRADO HOY").font(.caption).bold().foregroundStyle(.white.opacity(0.85))
                            Text(mxn(store.ventasDelDia)).font(.largeTitle).bold().foregroundStyle(.white)
                            Text("Propinas: \(mxn(store.propinasDelDia))").font(.headline).foregroundStyle(.white.opacity(0.90))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(20)
                        .background(LinearGradient(colors: [.posVerde, Color(red: 0.10, green: 0.55, blue: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .cornerRadius(20)
                        .shadow(color: Color.posVerde.opacity(0.35), radius: 10, x: 0, y: 5)
                        HStack(spacing: 12) {
                            VStack {
                                Text("\(store.pedidos.filter { $0.estado == .cobrado }.count)").font(.title).bold().foregroundStyle(.posRojo)
                                Text("Cobrados").font(.caption).bold()
                            }.frame(maxWidth: .infinity).tarjetaPOS()
                            VStack {
                                Text("\(store.pedidosActivos.count)").font(.title).bold().foregroundStyle(.posNaranja)
                                Text("Activos").font(.caption).bold()
                            }.frame(maxWidth: .infinity).tarjetaPOS()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
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
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.posFondo)
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
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Color.posNaranja.opacity(0.15)).frame(width: 48, height: 48)
                                Text(iconoCategoria(plato.categoria)).font(.title3)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plato.nombre).font(.headline)
                                Text(mxn(plato.precio)).font(.title3).bold().foregroundStyle(.posRojo)
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
                            let mesa = modo == "Mesa" ? "Mesa \(mesaCliente)" : "Para llevar"
                            store.crearPedido(mesa: mesa, tipo: "Cliente", items: carrito)
                            mensaje = "¡Pedido enviado! Llega a cocina en un momento."
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
                    .botonPOS()
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
        }
    }
    private func fechaTicket(_ fecha: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: fecha)
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
                    Text("1. Los dos en el mismo WiFi, con WiFi y Bluetooth prendidos.\n2. En los dos, pestaña Red local → Encender red local.\n3. Acepta el permiso de red local la primera vez.\n4. En uno, toca Conectar en el otro iPhone.\n5. Crea un pedido en uno: tiene que aparecer en Cocina del otro.")
                        .font(.callout)
                }
            }
            .navigationTitle("Red local")
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
                        .botonPOS()
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
