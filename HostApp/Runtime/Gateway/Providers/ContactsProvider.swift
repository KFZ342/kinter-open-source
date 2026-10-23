import Contacts

final class ContactsProvider: CapabilityProvider {
    static var capability: String { "contacts" }
    static var level: CapabilityLevel { .l1 }

    required init() {}

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "getAll" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, _ in
            guard granted else {
                DispatchQueue.main.async { completion(.failure(.userDenied("contacts"))) }
                return
            }
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
            let req = CNContactFetchRequest(keysToFetch: keys)
            var list: [[String: Any]] = []
            try? store.enumerateContacts(with: req) { c, _ in
                let phones = c.phoneNumbers.map { $0.value.stringValue }
                let emails = c.emailAddresses.map { $0.value as String }
                list.append(["name": "\(c.givenName) \(c.familyName)", "phones": phones, "emails": emails])
            }
            DispatchQueue.main.async { completion(.success(["contacts": list])) }
        }
    }
}
