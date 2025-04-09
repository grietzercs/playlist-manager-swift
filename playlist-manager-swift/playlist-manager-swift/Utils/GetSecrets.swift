//
//  GetSecrets.swift
//  playlist-manager-swift
//
//  Created by Colden on 1/31/25.
//

import Foundation

struct Secrets {
    public func loadFile<T: DecodeType>(file: String, ofType type: T.Type) throws -> T {
        // Get the file URL
        guard let url = Bundle.main.url(forResource: file, withExtension: "json") else {
            // log properly later
            print("File not found!")
            //return nil
            throw SecretsLoadError.loadError(message: "Could not get credentials from file provided")
        }
        do {
            let data = try Data(contentsOf: url)
            let decodedObject = try T.decode(from: data)
            return decodedObject
        } catch {
            print("Failed to decode data")
            throw error
        }
    }
    
    public func secretsLoad() {
        let foundationEnv = ProcessInfo().environment
        
        
    }
}


