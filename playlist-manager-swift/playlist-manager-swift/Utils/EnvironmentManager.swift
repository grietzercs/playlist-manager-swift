import Foundation

class EnvironmentManager {
    static let shared = EnvironmentManager()
    private var variables: [String: String] = [:]
    
    private init() {
        loadEnvironment()
    }
    
    private func loadEnvironment(from filename: String = ".env") {
        guard let path = Bundle.main.path(forResource: filename, ofType: nil),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("Could not load .env file")
            return
        }
        
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            // Skip comments and empty lines
            if line.hasPrefix("#") || line.isEmpty {
                continue
            }
            
            // Split by the first equals sign
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Remove quotes if present
                let cleanValue = value.replacingOccurrences(of: "^[\"']|[\"']$", with: "", options: .regularExpression)
                
                variables[key] = cleanValue
            }
        }
    }
    
    // Get a string value
    func string(for key: String) -> String? {
        return variables[key]
    }
    
    // Get an integer value
    func int(for key: String) -> Int? {
        guard let value = variables[key] else { return nil }
        return Int(value)
    }
    
    // Get a boolean value
    func bool(for key: String) -> Bool? {
        guard let value = variables[key]?.lowercased() else { return nil }
        if ["true", "yes", "1"].contains(value) {
            return true
        } else if ["false", "no", "0"].contains(value) {
            return false
        }
        return nil
    }
    
    // Get a URL
    func url(for key: String) -> URL? {
        guard let value = variables[key] else { return nil }
        return URL(string: value)
    }
}
