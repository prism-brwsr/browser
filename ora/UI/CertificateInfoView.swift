import SwiftUI

struct CertificateInfoView: View {
    let certificateInfo: CertificateInfo?
    let host: String?
    @Environment(\.dismiss) private var dismiss
    
    init(certificateInfo: CertificateInfo?, host: String? = nil) {
        self.certificateInfo = certificateInfo
        self.host = host
    }
    
    private var displaySubject: String {
        certificateInfo?.subject ?? host ?? "Unknown"
    }
    
    private var isConnectionSecure: Bool {
        guard let certInfo = certificateInfo else {
            // No cert info available - assume secure for HTTPS connections
            return true
        }
        
        // Only show as insecure if certificate is actually expired or not yet valid
        // Don't show as insecure just because some fields are "Unknown"
        let now = Date()
        let isExpired = now > certInfo.validUntil
        let isNotYetValid = now < certInfo.validFrom
        
        // Check if dates are fallback dates (both today) - if so, assume valid
        let calendar = Calendar.current
        let datesAreFallback = calendar.isDateInToday(certInfo.validFrom) && 
                               calendar.isDateInToday(certInfo.validUntil)
        
        // If dates are fallback, or certificate is within valid range, show as secure
        return datesAreFallback || (!isExpired && !isNotYetValid)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: isConnectionSecure ? "lock.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(isConnectionSecure ? .green : .orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connection is Secure")
                        .font(.headline)
                    Text(displaySubject)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(.bottom, 8)
            
            if let certInfo = certificateInfo {
                certificateDetails(certInfo)
            } else {
                Text("Certificate information is not available for this connection.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
    
    @ViewBuilder
    private func certificateDetails(_ certInfo: CertificateInfo) -> some View {
        Divider()
        
        // Certificate Details
        VStack(alignment: .leading, spacing: 12) {
            if certInfo.subject != "Unknown" {
                CertificateRow(label: "Issued to", value: certInfo.subject)
            }
            
            if certInfo.issuer != "Unknown" {
                CertificateRow(label: "Issued by", value: certInfo.issuer)
            }
            
            if let serialNumber = certInfo.serialNumber {
                CertificateRow(label: "Serial Number", value: serialNumber)
            }
            
            // Only show dates if they're not the fallback date (today)
            let calendar = Calendar.current
            let isToday = calendar.isDateInToday(certInfo.validFrom) && 
                          calendar.isDateInToday(certInfo.validUntil)
            
            if !isToday {
                CertificateRow(
                    label: "Valid from",
                    value: formatDate(certInfo.validFrom)
                )
                
                CertificateRow(
                    label: "Valid until",
                    value: formatDate(certInfo.validUntil)
                )
                
                if certInfo.isValid {
                    HStack {
                        Text("Expires in")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(certInfo.daysUntilExpiration) days")
                            .font(.subheadline)
                            .foregroundColor(certInfo.daysUntilExpiration < 30 ? .orange : .primary)
                    }
                } else {
                    HStack {
                        Text("Status")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Expired")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        
        Divider()
        
        // Technical Details - only show if we have real data
        if certInfo.publicKeyAlgorithm != "Unknown" || 
           certInfo.signatureAlgorithm != "Unknown" || 
           certInfo.keySize != nil {            
            VStack(alignment: .leading, spacing: 8) {
                Text("Technical Details")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                if certInfo.publicKeyAlgorithm != "Unknown" {
                    CertificateRow(label: "Public Key Algorithm", value: certInfo.publicKeyAlgorithm)
                }
                
                if certInfo.signatureAlgorithm != "Unknown" {
                    CertificateRow(label: "Signature Algorithm", value: certInfo.signatureAlgorithm)
                }
                
                if let keySize = certInfo.keySize {
                    CertificateRow(label: "Key Size", value: "\(keySize) bits")
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct CertificateRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }
}

