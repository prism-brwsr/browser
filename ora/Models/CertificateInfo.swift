import Foundation
import Security

struct CertificateInfo: Identifiable {
    let id = UUID()
    let subject: String
    let issuer: String
    let validFrom: Date
    let validUntil: Date
    let serialNumber: String?
    let publicKeyAlgorithm: String
    let signatureAlgorithm: String
    let keySize: Int?
    
    init?(from secTrust: SecTrust) {
        // Use the modern API to get certificate chain
        let certificateChain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate]
        guard let certificate = certificateChain?.first else {
            return nil
        }
        
        // Extract certificate properties using SecCertificateCopyValues
        var error: Unmanaged<CFError>?
        guard let certDict = SecCertificateCopyValues(certificate, nil, &error) as? [String: Any] else {
            // Fallback: try to get basic info from certificate
            let subjectSummary = SecCertificateCopySubjectSummary(certificate) as String? ?? "Unknown"
            self.subject = CertificateInfo.parseDistinguishedName(subjectSummary)
            self.issuer = "Unknown"
            self.validFrom = Date()
            self.validUntil = Date()
            self.serialNumber = nil
            self.publicKeyAlgorithm = "Unknown"
            self.signatureAlgorithm = "Unknown"
            self.keySize = nil
            return
        }
        
        // Helper to recursively extract the actual value from nested structures
        func deepExtractValue(_ value: Any?, depth: Int = 0) -> Any? {
            guard let value = value, depth < 5 else { return nil } // Prevent infinite recursion
            
            // If it's already a primitive type, return it
            if value is String || value is Date || value is Data || value is NSNumber {
                return value
            }
            
            // If it's a dictionary, look for kSecPropertyKeyValue
            if let dict = value as? [String: Any] {
                // Check if there's a direct value
                if let directValue = dict[kSecPropertyKeyValue as String] {
                    let extracted = deepExtractValue(directValue, depth: depth + 1)
                    if extracted != nil {
                        return extracted
                    }
                }
                
                // Check for label (sometimes the value is in the label)
                if let label = dict[kSecPropertyKeyLabel as String] as? String, !label.isEmpty {
                    return label
                }
                
                // Try to find any string value in the dictionary
                for (_, val) in dict {
                    if let str = val as? String, !str.isEmpty {
                        return str
                    }
                    if let extracted = deepExtractValue(val, depth: depth + 1) {
                        return extracted
                    }
                }
            }
            
            // If it's an array, try to extract from first element
            if let array = value as? [Any], let first = array.first {
                return deepExtractValue(first, depth: depth + 1)
            }
            
            return value
        }
        
        // Helper to extract value for a specific OID
        func extractOIDValue(_ oid: String) -> Any? {
            guard let oidDict = certDict[oid] as? [String: Any] else { return nil }
            return deepExtractValue(oidDict)
        }
        
        // Helper to extract string from OID
        func extractString(_ oid: String) -> String? {
            if let value = extractOIDValue(oid) {
                if let str = value as? String {
                    return str
                }
                if let data = value as? Data,
                   let str = String(data: data, encoding: .utf8) {
                    return str
                }
            }
            return nil
        }
        
        // Helper to extract date from OID
        func extractDate(_ oid: String) -> Date? {
            if let value = extractOIDValue(oid) {
                if let date = value as? Date {
                    return date
                }
                if let dateString = value as? String {
                    let isoFormatter = ISO8601DateFormatter()
                    if let date = isoFormatter.date(from: dateString) {
                        return date
                    }
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    return formatter.date(from: dateString)
                }
            }
            return nil
        }
        
        // Extract subject - try multiple methods
        var subjectValue: String?
        if let str = extractString(kSecOIDX509V1SubjectName as String) {
            subjectValue = str
        } else {
            // Fallback: try to get subject summary directly from certificate
            subjectValue = SecCertificateCopySubjectSummary(certificate) as String?
        }
        self.subject = subjectValue.map { CertificateInfo.parseDistinguishedName($0) } ?? "Unknown"
        
        // Extract issuer
        if let issuerValue = extractString(kSecOIDX509V1IssuerName as String) {
            self.issuer = CertificateInfo.parseDistinguishedName(issuerValue)
        } else {
            self.issuer = "Unknown"
        }
        
        // Extract validity dates
        let validFromDate = extractDate(kSecOIDX509V1ValidityNotBefore as String)
        let validUntilDate = extractDate(kSecOIDX509V1ValidityNotAfter as String)
        
        self.validFrom = validFromDate ?? Date()
        self.validUntil = validUntilDate ?? Date()
        
        // Extract serial number
        if let serialValue = extractOIDValue(kSecOIDX509V1SerialNumber as String) {
            if let serialString = serialValue as? String {
                self.serialNumber = serialString
            } else if let serialData = serialValue as? Data {
                self.serialNumber = serialData.map { String(format: "%02X", $0) }.joined(separator: ":")
            } else {
                self.serialNumber = nil
            }
        } else {
            self.serialNumber = nil
        }
        
        // Extract public key algorithm
        if let algorithmValue = extractString(kSecOIDX509V1SubjectPublicKeyAlgorithm as String) {
            self.publicKeyAlgorithm = algorithmValue
        } else {
            self.publicKeyAlgorithm = "Unknown"
        }
        
        // Extract signature algorithm
        if let signatureValue = extractString(kSecOIDX509V1SignatureAlgorithm as String) {
            self.signatureAlgorithm = signatureValue
        } else {
            self.signatureAlgorithm = "Unknown"
        }
        
        // Extract key size from public key data
        if let keyData = extractOIDValue(kSecOIDX509V1SubjectPublicKey as String) as? Data {
            // Estimate key size from data length
            self.keySize = keyData.count * 8
        } else {
            self.keySize = nil
        }
    }
    
    private static func parseDistinguishedName(_ dn: String) -> String {
        // Parse DN format like "CN=example.com, O=Organization, C=US"
        // Extract common name (CN) if available, otherwise return formatted version
        let components = dn.split(separator: ",")
        for component in components {
            let parts = component.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0].uppercased() == "CN" {
                return String(parts[1])
            }
        }
        return dn
    }
    
    
    var isValid: Bool {
        let now = Date()
        return now >= validFrom && now <= validUntil
    }
    
    var daysUntilExpiration: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: validUntil)
        return components.day ?? 0
    }
    
}

