import SwiftUI
import Combine
import CoreLocation
import CoreData

// MARK: - Models

struct FuelStation: Codable, Identifiable {
	let id = UUID()
	let rotulo: String
	let direccion: String
	let precioGasoleoA: String
	let precioGasoleoAPlus: String
	let precioGasolina95: String
	let precioGasolina98: String
	let precioBiodiesel: String
	let precioBioetanol: String
	let precioGNC: String
	let precioGNL: String
	let precioGLP: String
	let precioH2: String
	let horario: String
	let latitud: String
	let longitud: String
	
	enum CodingKeys: String, CodingKey {
		case rotulo = "Rótulo"
		case direccion = "Dirección"
		case precioGasoleoA = "Precio Gasoleo A"
		case precioGasoleoAPlus = "Precio Gasoleo Premium"
		case precioGasolina95 = "Precio Gasolina 95 E5"
		case precioGasolina98 = "Precio Gasolina 98 E5"
		case precioBiodiesel = "Precio Biodiesel"
		case precioBioetanol = "Precio Bioetanol"
		case precioGNC = "Precio Gas Natural Comprimido"
		case precioGNL = "Precio Gas Natural Licuado"
		case precioGLP = "Precio Gases licuados del petróleo"
		case precioH2 = "Precio Hidrogeno"
		case horario = "Horario"
		case latitud = "Latitud"
		case longitud = "Longitud (WGS84)"
	}
	
	var coordinate: CLLocationCoordinate2D? {
		guard let lat = Double(latitud.replacingOccurrences(of: ",", with: ".")),
					let lon = Double(longitud.replacingOccurrences(of: ",", with: ".")) else {
			print("Failed to parse coordinates for station: \(rotulo)")
			return nil
		}
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
	@Published var locationStatus: CLAuthorizationStatus = .notDetermined
	@Published var locationError: String?
	@Published var sortOption: SortOption = .locationAsc
	
	private var cancellables = Set<AnyCancellable>()
	private let locationManager = CLLocationManager()
	private var lastFetchTime: Date?
	
	override init() {
		super.init()
		setupLocationManager()
	}

	private func setupLocationManager() {
		locationManager.delegate = self
		locationManager.desiredAccuracy = kCLLocationAccuracyBest
	}
	
	func requestLocationPermission() {
		locationManager.requestWhenInUseAuthorization()
	}
	
	func startUpdatingLocation() {
		locationError = nil
		if locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways {
			locationManager.startUpdatingLocation()
		} else {
			requestLocationPermission()
		}
	}
	
	func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
		locationStatus = manager.authorizationStatus
		print("Location authorization status changed to: \(locationStatus.rawValue)")
		if locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways {
			locationManager.startUpdatingLocation()
		}
	}
	
	func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
		guard let location = locations.last else { return }
		print("Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
		userLocation = location
		fetchNearbyFuelStations()
	}
	
	func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
		print("Location manager failed with error: \(error.localizedDescription)")
		if let clError = error as? CLError {
			switch clError.code {
			case .denied:
				locationError = "Location access denied. Please enable it in settings."
			case .locationUnknown:
				locationError = "Unable to determine location. Please try again later."
			default:
				locationError = "An unknown error occurred while trying to get your location."
			}
		} else {
			locationError = "An unexpected error occurred: \(error.localizedDescription)"
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
			self.startUpdatingLocation()
		}
	}
	
	func fetchFuelStationsIfNeeded() {
		guard shouldFetch() else {
			print("Skipping fetch, last fetch was less than 30 minutes ago")
			return
		}
		
		fetchFuelStations()
	}
	
	private func shouldFetch() -> Bool {
		guard let lastFetchTime = lastFetchTime else {
			return true
		}
		
		let thirtyMinutesAgo = Date().addingTimeInterval(-30 * 60)
		return lastFetchTime < thirtyMinutesAgo
	}
	
	func fetchFuelStations() {
		guard let url = URL(string: "https://gp.intron014.com/fuel_stations") else { return }
		
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
				self.lastFetchTime = Date()
				print("Fetched \(self.fuelStations.count) fuel stations")
				self.fetchNearbyFuelStations()
			}
			.store(in: &cancellables)
	}
	
	
	func fetchNearbyFuelStations() {
		guard let userLocation = userLocation else {
			print("User location is not available")
			return
		}
		
		print("Fetching nearby fuel stations...")
		let nearbyStations = fuelStations.filter { station in
			guard let stationCoordinate = station.coordinate else {
				print("Invalid coordinates for station: \(station.rotulo)")
				return false
			}
			let stationLocation = CLLocation(latitude: stationCoordinate.latitude, longitude: stationCoordinate.longitude)
			let distance = userLocation.distance(from: stationLocation)
			print("Distance to \(station.rotulo): \(distance) meters")
			return distance <= locationRange
		}
		
		print("Found \(nearbyStations.count) nearby stations")
		DispatchQueue.main.async {
			self.fuelStations = nearbyStations
		}
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
	
	func sortFuelStations() {
		switch sortOption {
		case .locationAsc:
			fuelStations.sort { station1, station2 in
				guard let location1 = station1.coordinate, let location2 = station2.coordinate, let userLocation = userLocation else {
					return false
				}
				let distance1 = userLocation.distance(from: CLLocation(latitude: location1.latitude, longitude: location1.longitude))
				let distance2 = userLocation.distance(from: CLLocation(latitude: location2.latitude, longitude: location2.longitude))
				return distance1 < distance2
			}
		case .locationDesc:
			fuelStations.sort { station1, station2 in
				guard let location1 = station1.coordinate, let location2 = station2.coordinate, let userLocation = userLocation else {
					return false
				}
				let distance1 = userLocation.distance(from: CLLocation(latitude: location1.latitude, longitude: location1.longitude))
				let distance2 = userLocation.distance(from: CLLocation(latitude: location2.latitude, longitude: location2.longitude))
				return distance1 > distance2
			}
		case .priceAsc(let fuelType):
			fuelStations.sort { station1, station2 in
				let price1 = self.getPrice(for: fuelType, in: station1)
				let price2 = self.getPrice(for: fuelType, in: station2)
				return price1 < price2
			}
		case .priceDesc(let fuelType):
			fuelStations.sort { station1, station2 in
				let price1 = self.getPrice(for: fuelType, in: station1)
				let price2 = self.getPrice(for: fuelType, in: station2)
				return price1 > price2
			}
		}
	}
	
	private func getPrice(for fuelType: FuelType, in station: FuelStation) -> Double {
		let priceString: String
		switch fuelType {
		case .gasoleoA:
			priceString = station.precioGasoleoA
		case .gasoleoAPlus:
			priceString = station.precioGasoleoAPlus
		case .gasolina95:
			priceString = station.precioGasolina95
		case .gasolina98:
			priceString = station.precioGasolina98
		}
		return Double(priceString.replacingOccurrences(of: ",", with: ".")) ?? 0
	}
}

enum SortOption {
	case locationAsc
	case locationDesc
	case priceAsc(FuelType)
	case priceDesc(FuelType)
}

enum FuelType: String, CaseIterable {
	case gasoleoA = "Diesel"
	case gasoleoAPlus = "Diesel+"
	case gasolina95 = "Gas 95"
	case gasolina98 = "Gas 98"
}

// MARK: - Views

struct ContentView: View {
	@StateObject private var viewModel = FuelStationsViewModel()
	@State private var showingSettings = false
	@State private var showingSortOptions = false
	
	var body: some View {
		NavigationView {
			VStack {
				if let error = viewModel.locationError {
					Text(error)
						.foregroundColor(.red)
						.padding()
				}
				
				if viewModel.locationStatus == .authorizedWhenInUse || viewModel.locationStatus == .authorizedAlways {
					if viewModel.fuelStations.isEmpty {
						Text("No nearby gas stations found.")
							.padding()
					} else {
						FuelStationListView(fuelStations: viewModel.fuelStations)
					}
				} else {
					Text("Location access is required to find nearby gas stations.")
					Button("Allow Location Access") {
						viewModel.requestLocationPermission()
					}
				}
			}
			.navigationTitle("GasoPrice")
			.navigationBarItems(trailing: HStack {
				filterButton
				settingsButton
			})
		}
		.onAppear {
			viewModel.fetchFuelStationsIfNeeded()
			viewModel.fetchProvincias()
			viewModel.startUpdatingLocation()
		}
		.sheet(isPresented: $showingSettings) {
			SettingsView(viewModel: viewModel)
		}
		.actionSheet(isPresented: $showingSortOptions) {
			ActionSheet(title: Text("Sort by"), buttons: sortButtons)
		}
	}
	
	private var settingsButton: some View {
		Button(action: {
			showingSettings = true
		}) {
			Image(systemName: "gear")
		}
	}
	
	private var filterButton: some View {
		Button(action: {
			showingSortOptions = true
		}) {
			Image(systemName: "arrow.up.arrow.down")
		}
	}
	
	private var sortButtons: [ActionSheet.Button] {
		var buttons: [ActionSheet.Button] = [
			.default(Text("Location (Nearest)")) {
				viewModel.sortOption = .locationAsc
				viewModel.sortFuelStations()
			},
			.default(Text("Location (Farthest)")) {
				viewModel.sortOption = .locationDesc
				viewModel.sortFuelStations()
			}
		]
		
		for fuelType in FuelType.allCases {
			buttons.append(.default(Text("\(fuelType.rawValue) (Lowest)")) {
				viewModel.sortOption = .priceAsc(fuelType)
				viewModel.sortFuelStations()
			})
			buttons.append(.default(Text("\(fuelType.rawValue) (Highest)")) {
				viewModel.sortOption = .priceDesc(fuelType)
				viewModel.sortFuelStations()
			})
		}
		
		buttons.append(.cancel())
		
		return buttons
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
						Slider(value: $viewModel.locationRange, in: 1000...100000, step: 1000)
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
				PriceText(label: "Diesel", price: station.precioGasoleoA)
				PriceText(label: "Gas 95", price: station.precioGasolina95)
				PriceText(label: "Diesel+", price: station.precioGasoleoAPlus)
				PriceText(label: "Gas 98", price: station.precioGasolina98)
			}
			HStack {
				PriceText(label: "Biodiesel", price: station.precioBiodiesel)
				PriceText(label: "Bioetanol", price: station.precioBioetanol)
				PriceText(label: "GNC", price: station.precioGNC)
				PriceText(label: "GNL", price: station.precioGNL)
			}
			HStack {
				PriceText(label: "GLP", price: station.precioGLP)
				PriceText(label: "H2", price: station.precioH2)
			}
			Text("Hours: \(station.horario)")
		}
	}
}

struct PriceText: View {
	let label: String
	let price: String
	
	var body: some View {
		Text("\(label): \(price.isEmpty ? "-" : price)")
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
			precioGasoleoAPlus: "-",
			precioGasolina95: "1.345",
			precioGasolina98: "-",
			precioBiodiesel: "-",
			precioBioetanol: "-",
			precioGNC: "-",
			precioGNL: "-",
			precioGLP: "-",
			precioH2: "-",
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
