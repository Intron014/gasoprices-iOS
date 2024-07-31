import CoreData

struct PersistenceController {
	static let shared = PersistenceController()
	
	@MainActor
	static let preview: PersistenceController = {
		let result = PersistenceController(inMemory: true)
		let viewContext = result.container.viewContext
		return result
	}()
	
	let container: NSPersistentContainer
	
	init(inMemory: Bool = false) {
		container = NSPersistentContainer(name: "gasoprice")
		if inMemory {
			container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
		}
		container.loadPersistentStores(completionHandler: { (storeDescription, error) in
			if let error = error as NSError? {
				fatalError("Unresolved error \(error), \(error.userInfo)")
			}
		})
		container.viewContext.automaticallyMergesChangesFromParent = true
	}
	
	func saveJSONData(_ jsonData: Data) {
		let context = container.viewContext
		
		// Delete old data
		let fetchRequest: NSFetchRequest<NSFetchRequestResult> = FuelStationsData.fetchRequest()
		let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
		_ = try? context.execute(batchDeleteRequest)
		
		// Save new data
		let fuelStationsData = FuelStationsData(context: context)
		fuelStationsData.jsonData = jsonData
		fuelStationsData.timestamp = Date()
		
		do {
			try context.save()
		} catch {
			let nsError = error as NSError
			fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
		}
	}
	
	func fetchJSONData() -> Data? {
		let context = container.viewContext
		let fetchRequest: NSFetchRequest<FuelStationsData> = FuelStationsData.fetchRequest()
		fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \FuelStationsData.timestamp, ascending: false)]
		fetchRequest.fetchLimit = 1
		
		do {
			let results = try context.fetch(fetchRequest)
			return results.first?.jsonData
		} catch {
			print("Error fetching JSON data: \(error)")
			return nil
		}
	}
}
