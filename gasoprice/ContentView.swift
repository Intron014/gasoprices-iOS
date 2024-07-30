import SwiftUI
import Combine
import CoreLocation

// MARK: - Models

struct FuelStation: Codable, Identifiable {
	let id = UUID()
	let rotulo: String
	let direccion: String
	let precioGasoleoA: String
	let precioGasolina95: String
	let horario: String
	let latitud: String
	let longitud: String
	
	enum CodingKeys: String, CodingKey {
		case rotulo = "Rótulo"
		case direccion = "Dirección"
		case precioGasoleoA = "Precio Gasoleo A"
		case precioGasolina95 = "Precio Gasolina 95 E5"
		case horario = "Horario"
		case latitud = "Latitud"
		case longitud = "Longitud (WGS84)"
	}
	
	var coordinate: CLLocationCoordinate2D? {
		guard let lat = Double(latitud), let lon = Double(longitud) else { return nil }
		return CLLocationCoordinate2D(latitude: lat, longitude: lon)
	}
}

struct Provincia: Codable, Identifiable {
	let id: String
	let nombre: String
	
	enum CodingKeys: String, CodingKey {
		case id = "IDPovincia"
		case nombre = "Provincia"
	}
}

struct Municipio: Codable, Identifiable {
	let id: String
	let nombre: String
	
	enum CodingKeys: String, CodingKey {
		case id = "IDMunicipio"
		case nombre = "Municipio"
	}
}

// MARK: - View Models

class FuelStationsViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
	@Published var fuelStations: [FuelStation] = []
	@Published var provincias: [Provincia] = []
	@Published var municipios: [Municipio] = []
	@Published var selectedProvinciaId: String?
	@Published var selectedMunicipioId: String?
	@Published var userLocation: CLLocation?
	@Published var locationRange: Double = 4000 // 4km default
	
	private var cancellables = Set<AnyCancellable>()
	private let locationManager = CLLocationManager()
	
	override init() {
		super.init()
		setupLocationManager()
	}
	
	private func setupLocationManager() {
		locationManager.delegate = self
		locationManager.desiredAccuracy = kCLLocationAccuracyBest
		locationManager.requestWhenInUseAuthorization()
	}
	
	func startUpdatingLocation() {
		locationManager.startUpdatingLocation()
	}
	
	func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
		guard let location = locations.last else { return }
		userLocation = location
		fetchNearbyFuelStations()
	}
	
	func fetchNearbyFuelStations() {
		guard let userLocation = userLocation else { return }
		
		let nearbyStations = fuelStations.filter { station in
			guard let stationCoordinate = station.coordinate else { return false }
			let stationLocation = CLLocation(latitude: stationCoordinate.latitude, longitude: stationCoordinate.longitude)
			return userLocation.distance(from: stationLocation) <= locationRange
		}
		
		DispatchQueue.main.async {
			self.fuelStations = nearbyStations
		}
	}
	
	func fetchFuelStations() {
		guard let url = URL(string: "https://sedeaplicaciones.minetur.gob.es/ServiciosRESTCarburantes/PreciosCarburantes/EstacionesTerrestres/") else { return }
		
		URLSession.shared.dataTaskPublisher(for: url)
			.map(\.data)
			.decode(type: FuelStationsResponse.self, decoder: JSONDecoder())
			.receive(on: DispatchQueue.main)
			.sink { completion in
				if case .failure(let error) = completion {
					print("Error fetching fuel stations: \(error)")
				}
			} receiveValue: { response in
				self.fuelStations = response.listaEESSPrecio
				self.fetchNearbyFuelStations()
			}
			.store(in: &cancellables)
	}
	
	func fetchProvincias() {
		guard let url = URL(string: "https://sedeaplicaciones.minetur.gob.es/ServiciosRESTCarburantes/PreciosCarburantes/Listados/Provincias/") else { return }
		
		URLSession.shared.dataTaskPublisher(for: url)
			.map(\.data)
			.decode(type: [Provincia].self, decoder: JSONDecoder())
			.receive(on: DispatchQueue.main)
			.sink { completion in
				if case .failure(let error) = completion {
					print("Error fetching provincias: \(error)")
				}
			} receiveValue: { provincias in
				self.provincias = provincias
			}
			.store(in: &cancellables)
	}
	
	func fetchMunicipios(for provinciaId: String) {
		guard let url = URL(string: "https://sedeaplicaciones.minetur.gob.es/ServiciosRESTCarburantes/PreciosCarburantes/Listados/MunicipiosPorProvincia/\(provinciaId)") else { return }
		
		URLSession.shared.dataTaskPublisher(for: url)
			.map(\.data)
			.decode(type: [Municipio].self, decoder: JSONDecoder())
			.receive(on: DispatchQueue.main)
			.sink { completion in
				if case .failure(let error) = completion {
					print("Error fetching municipios: \(error)")
				}
			} receiveValue: { municipios in
				self.municipios = municipios
			}
			.store(in: &cancellables)
	}
	
	func filterFuelStations(by municipioId: String) {
		guard let url = URL(string: "https://sedeaplicaciones.minetur.gob.es/ServiciosRESTCarburantes/PreciosCarburantes/EstacionesTerrestres/FiltroMunicipio/\(municipioId)") else { return }
		
		URLSession.shared.dataTaskPublisher(for: url)
			.map(\.data)
			.decode(type: FuelStationsResponse.self, decoder: JSONDecoder())
			.receive(on: DispatchQueue.main)
			.sink { completion in
				if case .failure(let error) = completion {
					print("Error filtering fuel stations: \(error)")
				}
			} receiveValue: { response in
				self.fuelStations = response.listaEESSPrecio
			}
			.store(in: &cancellables)
	}
}

// MARK: - Views

struct ContentView: View {
	@StateObject private var viewModel = FuelStationsViewModel()
	@State private var showingSettings = false
	
	var body: some View {
		NavigationView {
			VStack {
				FuelStationListView(fuelStations: viewModel.fuelStations)
			}
			.navigationTitle("GasoPrice")
			.navigationBarItems(trailing: settingsButton)
		}
		.onAppear {
			viewModel.fetchFuelStations()
			viewModel.fetchProvincias()
			viewModel.startUpdatingLocation()
		}
		.sheet(isPresented: $showingSettings) {
			SettingsView(viewModel: viewModel)
		}
	}
	
	private var settingsButton: some View {
		Button(action: {
			showingSettings = true
		}) {
			Image(systemName: "gear")
		}
	}
}

struct SettingsView: View {
	@ObservedObject var viewModel: FuelStationsViewModel
	@Environment(\.presentationMode) var presentationMode
	
	var body: some View {
		NavigationView {
			Form {
				Section(header: Text("Filters")) {
					Picker("Provincia", selection: $viewModel.selectedProvinciaId) {
						Text("Select Provincia").tag(nil as String?)
						ForEach(viewModel.provincias) { provincia in
							Text(provincia.nombre).tag(provincia.id as String?)
						}
					}
					.onChange(of: viewModel.selectedProvinciaId) { newValue in
						if let provinciaId = newValue {
							viewModel.fetchMunicipios(for: provinciaId)
						} else {
							viewModel.municipios = []
						}
						viewModel.selectedMunicipioId = nil
					}
					
					Picker("Municipio", selection: $viewModel.selectedMunicipioId) {
						Text("Select Municipio").tag(nil as String?)
						ForEach(viewModel.municipios) { municipio in
							Text(municipio.nombre).tag(municipio.id as String?)
						}
					}
					.disabled(viewModel.selectedProvinciaId == nil)
				}
				
				Section(header: Text("Location")) {
					HStack {
						Text("Range: ")
						Slider(value: $viewModel.locationRange, in: 1000...10000000, step: 1000)
						Text("\(Int(viewModel.locationRange)/1000) km")
							.frame(minWidth: 40, alignment: .trailing)
					}
				}
				
				Section {
					Button("Apply Filters") {
						if let municipioId = viewModel.selectedMunicipioId {
							viewModel.filterFuelStations(by: municipioId)
						} else {
							viewModel.fetchNearbyFuelStations()
						}
						presentationMode.wrappedValue.dismiss()
					}
				}
			}
			.navigationTitle("Settings")
			.navigationBarItems(trailing: Button("Done") {
				presentationMode.wrappedValue.dismiss()
			})
		}
	}
}

struct FuelStationListView: View {
	let fuelStations: [FuelStation]
	
	var body: some View {
		List(fuelStations) { station in
			FuelStationRow(station: station)
		}
	}
}

struct FuelStationRow: View {
	let station: FuelStation
	
	var body: some View {
		VStack(alignment: .leading) {
			Text(station.rotulo).font(.headline)
			Text(station.direccion)
			HStack {
				Text("Diesel: \(station.precioGasoleoA)")
				Text("Gas 95: \(station.precioGasolina95)")
			}
			Text("Hours: \(station.horario)")
		}
	}
}

// MARK: - Previews

struct ContentView_Previews: PreviewProvider {
	static var previews: some View {
		ContentView()
	}
}

struct FuelStationRow_Previews: PreviewProvider {
	static var previews: some View {
		FuelStationRow(station: FuelStation(
			rotulo: "Sample Station",
			direccion: "123 Main St, City",
			precioGasoleoA: "1.234",
			precioGasolina95: "1.345",
			horario: "24H",
			latitud: "40.4168",
			longitud: "-3.7038"
		))
		.previewLayout(.sizeThatFits)
		.padding()
	}
}

// MARK: - Supporting Types

struct FuelStationsResponse: Codable {
	let listaEESSPrecio: [FuelStation]
	
	enum CodingKeys: String, CodingKey {
		case listaEESSPrecio = "ListaEESSPrecio"
	}
}
