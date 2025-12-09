import SwiftUI
import Foundation

enum MoveDirection {
    case up
    case down
}

class Debouncer {
    private var workItem: DispatchWorkItem?
    private let delay: TimeInterval

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func run(_ block: @escaping @Sendable () async -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem {
            Task { await block() }
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}

let debouncer = Debouncer(delay: 0.2)

struct LauncherMain: View {
    struct Match {
        let text: String
        let color: Color
        let foregroundColor: Color
        let icon: String
        let originalAlias: String
        let searchURL: String
        let favicon: NSImage?
        let faviconBackgroundColor: Color?
    }

    @Binding var text: String
    @Binding var match: Match?
    var isFocused: FocusState<Bool>.Binding
    let onTabPress: () -> Void
    let onSubmit: (String?) -> Void

    @Environment(\.theme) private var theme
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var toolbarManager: ToolbarManager
    @EnvironmentObject var privacyMode: PrivacyMode
    @State var focusedElement: UUID = .init()

    @StateObject private var searchEngineService = SearchEngineService()

    @State private var suggestions: [LauncherSuggestion] = []
    @State private var isUpdatingTextFromNavigation = false // Flag to prevent suggestion regeneration during arrow key navigation

    private func createAISuggestion(engineName: SearchEngineID, query: String? = nil)
        -> LauncherSuggestion
    {
        guard let engine = searchEngineService.getSearchEngine(engineName) else {
            return LauncherSuggestion(
                type: .aiChat,
                title: query ?? engineName.rawValue,
                name: engineName.rawValue,
                action: {}
            )
        }

        _ = FaviconService.shared.getFavicon(for: engine.searchURL)
        let faviconURL = FaviconService.shared.faviconURL(for: URL(string: engine.searchURL)?.host ?? "")

        return LauncherSuggestion(
            type: .aiChat,
            title: query ?? engine.name,
            name: engine.name,
            faviconURL: faviconURL,
            action: {
                tabManager.openFromEngine(
                    engineName: engineName,
                    query: query ?? text,
                    historyManager: historyManager,
                    isPrivate: privacyMode.isPrivate
                )
            }
        )
    }

    func defaultSuggestions() -> [LauncherSuggestion] {
        let containerId = tabManager.activeContainer?.id
        let searchEngine = searchEngineService.getDefaultSearchEngine(for: containerId)
        let engineName = searchEngine?.name ?? "Google"
        return [
            LauncherSuggestion(
                type: .suggestedQuery, title: "Search on \(engineName)",
                action: { onSubmit(nil) }
            ),
            createAISuggestion(engineName: .grok),
            createAISuggestion(engineName: .chatgpt),
            createAISuggestion(engineName: .claude),
            createAISuggestion(engineName: .gemini)
        ]
    }

    private func isValidHostname(_ input: String) -> Bool {
        let regex = #"^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$"#
        return input.range(of: regex, options: .regularExpression) != nil
    }
    
    private func isMathExpression(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        
        // Match patterns like: number operator number (with optional spaces)
        // Supports: +, -, *, /, parentheses, decimal numbers
        let mathPattern = #"^[\d\s\+\-\*\/\(\)\.]+$"#
        guard trimmed.range(of: mathPattern, options: .regularExpression) != nil else {
            return false
        }
        
        // Must contain at least one operator
        let operatorPattern = #"[+\-*/]"#
        guard trimmed.range(of: operatorPattern, options: .regularExpression) != nil else {
            return false
        }
        
        // Must contain at least one digit
        let digitPattern = #"\d"#
        guard trimmed.range(of: digitPattern, options: .regularExpression) != nil else {
            return false
        }
        
        // Don't treat single numbers as math expressions
        let onlyNumbers = trimmed.replacingOccurrences(of: #"[\s\+\.]"#, with: "", options: .regularExpression)
        guard onlyNumbers.count > 1 || trimmed.contains(where: { "+-*/()".contains($0) }) else {
            return false
        }
        
        // Ensure expression doesn't end with an operator (incomplete expression)
        // Note: - at the end could be valid as unary minus, but we'll reject it for safety
        let trimmedForCheck = trimmed.trimmingCharacters(in: .whitespaces)
        guard !trimmedForCheck.isEmpty else { return false }
        let lastChar = trimmedForCheck.last!
        if lastChar == "+" || lastChar == "*" || lastChar == "/" || lastChar == "-" {
            return false // Incomplete expression - ends with operator
        }
        
        // Reject expressions ending with a decimal point (e.g., "123." or "2938293.")
        // NSExpression cannot parse numbers ending with just a dot
        if lastChar == "." {
            return false // Incomplete decimal number
        }
        
        // Check for trailing decimal points in the middle of expressions (e.g., "123. + 4" or "254442349/2938293.")
        // This pattern matches a number followed by a dot followed by whitespace/operator or end of string
        let trailingDotPattern = #"\d\.\s*([+\-*/)]|$)"#
        if trimmed.range(of: trailingDotPattern, options: .regularExpression) != nil {
            return false // Number with trailing dot
        }
        
        // Also check without spaces for cases like "2938293./123"
        let noSpacesForCheck = trimmed.replacingOccurrences(of: " ", with: "")
        if noSpacesForCheck.range(of: #"\d\.[+\-*/)]"#, options: .regularExpression) != nil {
            return false // Number with trailing dot immediately before operator
        }
        if noSpacesForCheck.hasSuffix(".") {
            return false // Ends with trailing dot
        }
        
        // Ensure expression doesn't start with an operator (except - for negative numbers)
        let trimmedNoSpaces = trimmed.replacingOccurrences(of: " ", with: "")
        if trimmedNoSpaces.hasPrefix("+") || trimmedNoSpaces.hasPrefix("*") || trimmedNoSpaces.hasPrefix("/") {
            return false
        }
        
        // Basic validation: must have at least one number before and after an operator
        // Simple check: after removing spaces, we should have digit-operator-digit pattern
        let noSpaces = trimmed.replacingOccurrences(of: " ", with: "")
        // Check that operators are not consecutive (except for negative numbers after operators)
        let consecutiveOperatorsPattern = #"[+\-*/]{2,}"#
        if noSpaces.range(of: consecutiveOperatorsPattern, options: .regularExpression) != nil {
            // Allow - after operators (for negative numbers), but not other consecutive operators
            let invalidConsecutive = #"[+\*/]{2,}|[\+\*/]\-{2,}"#
            if noSpaces.range(of: invalidConsecutive, options: .regularExpression) != nil {
                return false
            }
        }
        
        return true
    }
    
    private func evaluateMathExpression(_ expression: String) -> String? {
        let trimmed = expression.trimmingCharacters(in: .whitespaces)
        
        // Sanitize: only allow numbers, operators, spaces, parentheses, and decimal points
        let sanitized = trimmed.replacingOccurrences(
            of: #"[^\d\s\+\-\*\/\(\)\.]"#,
            with: "",
            options: .regularExpression
        )
        
        guard sanitized == trimmed else {
            return nil // Contains invalid characters
        }
        
        // Remove all spaces for evaluation
        let noSpaces = sanitized.replacingOccurrences(of: " ", with: "")
        
        // Additional validation: ensure we have a valid expression structure
        guard !noSpaces.isEmpty else {
            return nil
        }
        
        // Check for balanced parentheses
        var parenCount = 0
        for char in noSpaces {
            if char == "(" {
                parenCount += 1
            } else if char == ")" {
                parenCount -= 1
                if parenCount < 0 {
                    return nil // Unbalanced parentheses
                }
            }
        }
        if parenCount != 0 {
            return nil // Unbalanced parentheses
        }
        
        // CRITICAL: Reject expressions with trailing decimal points (e.g., "2938293.")
        // NSExpression cannot parse numbers ending with just a dot and will throw an exception
        // This must be checked before any other validation
        if noSpaces.last == "." {
            return nil // Trailing decimal point
        }
        
        // Check for number-dot-operator or number-dot-end patterns (e.g., "254442349/2938293." or "2938293./123")
        // This catches cases where a number has a trailing dot
        let trailingDotPattern = #"\d\.([+\-*/)]|$)"#
        if noSpaces.range(of: trailingDotPattern, options: .regularExpression) != nil {
            return nil // Number with trailing dot
        }
        
        // Additional safety: validate expression ends with a number or closing paren
        // This prevents incomplete expressions like "10+" from being evaluated
        let lastChar = noSpaces.last!
        guard lastChar.isNumber || lastChar == ")" else {
            return nil // Can't end with operator, decimal point, etc.
        }
        
        // Additional safety: validate expression starts with a number, opening paren, or minus
        let firstChar = noSpaces.first!
        guard firstChar.isNumber || firstChar == "(" || firstChar == "-" else {
            return nil // Can't start with operator (except minus) or decimal point
        }
        
        // Use NSExpression to evaluate - but we need to be careful about exceptions
        // NSExpression can throw Objective-C exceptions which Swift's do-catch doesn't catch
        // We've done thorough validation above, so this should be safe, but wrap in Obj-C compatible way
        // For now, since we've validated the structure, we'll proceed
        // In production, you might want to use an Objective-C bridge for exception handling
        
        // Create the expression - this can throw NSInvalidArgumentException
        // We'll use a C-style exception handler via a helper function
        return evaluateExpressionSafely(noSpaces)
    }
    
    // Helper function to safely evaluate expressions
    // Note: This doesn't actually catch Objective-C exceptions in pure Swift
    // But with thorough validation above, we should be safe
    private func evaluateExpressionSafely(_ expression: String) -> String? {
        // Final validation before attempting evaluation
        // Ensure no invalid operator sequences
        let invalidPatterns = [
            #"[+\*/]{2,}"#,  // Consecutive operators (except -- which might be valid)
            #"\([+\*/]"#,    // Operator immediately after opening paren (except -)
            #"[+\*/]\)"#,    // Operator immediately before closing paren
        ]
        
        for pattern in invalidPatterns {
            if expression.range(of: pattern, options: .regularExpression) != nil {
                return nil
            }
        }
        
        // Attempt to create NSExpression
        // Note: NSExpression(format:) can throw Objective-C exceptions (NSInvalidArgumentException)
        // which Swift's do-catch cannot catch. We rely on thorough validation above to prevent crashes.
        // If this still crashes, we may need an Objective-C bridge to catch exceptions properly.
        let expr = NSExpression(format: expression)
        
        // Attempt to evaluate
        let result = expr.expressionValue(with: nil, context: nil)
        
        guard let number = result as? NSNumber else {
            return nil
        }
        
        let value = number.doubleValue
        
        // Check for invalid results
        guard value.isFinite && !value.isNaN else {
            return nil
        }
        
        // Format the result
        if abs(value.truncatingRemainder(dividingBy: 1)) < Double.ulpOfOne {
            return String(format: "%.0f", value)
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 10
            formatter.minimumFractionDigits = 0
            formatter.usesGroupingSeparator = false
            
            return formatter.string(from: NSNumber(value: value)) ?? String(value)
        }
    }

    func searchHandler(_ text: String) {
        // Don't regenerate suggestions if we're updating text from arrow key navigation
        // This preserves the current suggestion list and focused element
        if isUpdatingTextFromNavigation {
            return
        }
        
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            suggestions = defaultSuggestions()
            return
        }

        let histories = historyManager.search(
            text,
            activeContainerId: tabManager.activeContainer?.id ?? UUID()
        )
        let tabs = tabManager.search(text)

        suggestions = []

        var itemsCount = 0
        appendAliasSuggestionIfNeeded(text)
        appendMathSuggestionIfNeeded(text)
        appendOpenTabs(tabs, itemsCount: &itemsCount)
        appendOpenURLSuggestionIfNeeded(text)
        appendSearchWithDefaultEngineSuggestion(text)

        let insertIndex = suggestions.count
        requestAutoSuggestions(text, insertAt: insertIndex)

        appendHistorySuggestions(histories, itemsCount: &itemsCount)
        appendAISuggestionsIfNeeded(text)

        // Set default focused element based on priority:
        // 1. Alias suggestions (with showTabShortcut) or math results - highest priority
        // 2. Explicit URL suggestion (when input looks like a URL) - default priority
        // 3. "Search with [engine]" suggestion - fallback priority
        // 4. First suggestion - final fallback
        
        // Note: Setting focusedElement programmatically does NOT trigger text field updates
        // Text field only updates when user explicitly navigates (arrow keys or hover)
        if let aliasOrMathSuggestion = suggestions.first(where: { suggestion in
            // Check if it's an alias suggestion (has showTabShortcut) or math result
            (suggestion.showTabShortcut && 
             (suggestion.title.hasPrefix("Ask ") || 
              suggestion.title.hasPrefix("Search with ") ||
              suggestion.title.hasPrefix("Search on "))) ||
            suggestion.type == .mathResult
        }) {
            focusedElement = aliasOrMathSuggestion.id
        } else if let urlSuggestion = suggestions.first(where: { $0.type == .suggestedLink }) {
            // Prefer the explicit URL when the input looks like a URL (e.g., http/https/www or domain)
            focusedElement = urlSuggestion.id
        } else if let searchWithSuggestion = suggestions.first(where: { suggestion in
            // Find the "Search with [engine]" suggestion
            suggestion.title.contains(" - Search with ") || suggestion.title.hasPrefix("Search with ")
        }) {
            focusedElement = searchWithSuggestion.id
        } else {
            focusedElement = suggestions.first?.id ?? UUID()
        }
    }

    private func appendAliasSuggestionIfNeeded(_ text: String) {
        // Only show alias suggestion if match is nil (no engine selected yet)
        guard match == nil else { return }
        
        // Trim whitespace and check if the text exactly matches an alias
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        guard !trimmedText.isEmpty else { return }
        
        // Check if the text exactly matches an alias (case-insensitive)
        if let searchEngine = searchEngineService.findSearchEngine(for: trimmedText) {
            // Verify that the trimmed text is indeed an exact alias match
            let textLowercased = trimmedText.lowercased()
            guard searchEngine.aliases.contains(textLowercased) else { return }
            
            let faviconURL = FaviconService.shared.faviconURL(for: URL(string: searchEngine.searchURL)?.host ?? "")
            
            let prefix = searchEngine.isAIChat ? "Ask" : "Search with"
            suggestions.insert(
                LauncherSuggestion(
                    type: .suggestedQuery,
                    title: "\(prefix) \(searchEngine.name)",
                    name: searchEngine.name,
                    icon: searchEngine.icon.isEmpty ? nil : searchEngine.icon,
                    faviconURL: faviconURL,
                    showTabShortcut: true,
                    action: {
                        onTabPress()
                    }
                ),
                at: 0
            )
        }
    }
    
    private func appendMathSuggestionIfNeeded(_ text: String) {
        // Only show math suggestion if match is nil (no engine selected yet)
        guard match == nil else { return }
        
        // Double-check that we don't have an incomplete expression
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        
        // Ensure expression doesn't end with an operator (extra safety check)
        let lastChar = trimmed.last!
        if lastChar == "+" || lastChar == "-" || lastChar == "*" || lastChar == "/" {
            return // Incomplete expression, don't try to evaluate
        }
        
        // CRITICAL: Reject expressions ending with a decimal point (e.g., "2938293.")
        // NSExpression cannot parse numbers ending with just a dot and will crash
        if lastChar == "." {
            return // Incomplete decimal number, don't try to evaluate
        }
        
        // Check for trailing decimal points in the expression (e.g., "254442349/2938293.")
        // This pattern matches a digit followed by a dot at the end or before an operator
        let noSpacesCheck = trimmed.replacingOccurrences(of: " ", with: "")
        let trailingDotPattern = #"\d\.([+\-*/)]|$)"#
        if noSpacesCheck.range(of: trailingDotPattern, options: .regularExpression) != nil {
            return // Number with trailing dot, don't try to evaluate
        }
        
        guard isMathExpression(text) else { return }
        
        guard let result = evaluateMathExpression(text) else { return }
        
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        suggestions.insert(
            LauncherSuggestion(
                type: .mathResult,
                title: "\(trimmedText) = \(result)",
                icon: "plus.forwardslash.minus",
                showTabShortcut: true,
                action: {
                    // Replace text field contents with the result
                    self.text = result
                }
            ),
            at: 0
        )
    }

    private func appendOpenTabs(_ tabs: [Tab], itemsCount: inout Int) {
        for tab in tabs {
            if itemsCount >= 2 { break }
            suggestions.append(
                LauncherSuggestion(
                    type: .openedTab,
                    title: tab.title,
                    url: tab.url,
                    faviconURL: tab.favicon,
                    faviconLocalFile: tab.faviconLocalFile,
                    action: {
                        if !tab.isWebViewReady {
                            tab.restoreTransientState(
                                historyManager: historyManager,
                                downloadManager: downloadManager,
                                tabManager: tabManager,
                                isPrivate: privacyMode.isPrivate
                            )
                        }
                        tabManager.activateTab(tab)
                    }
                )
            )
            itemsCount += 1
        }
    }

    private func appendOpenURLSuggestionIfNeeded(_ text: String) {
        guard let candidateURL = URL(string: text) else { return }
        let finalURL: URL? =
            if candidateURL.scheme != nil {
                candidateURL
            } else if isValidURL(text) {
                constructURL(from: text)
            } else {
                nil
            }
        guard let url = finalURL else { return }
        suggestions.append(
            LauncherSuggestion(
                type: .suggestedLink,
                title: text,
                url: url,
                action: {
                    tabManager.openTab(
                        url: url,
                        historyManager: historyManager,
                        downloadManager: downloadManager,
                        isPrivate: privacyMode.isPrivate
                    )
                }
            )
        )
    }

    private func appendSearchWithDefaultEngineSuggestion(_ text: String) {
        let containerId = tabManager.activeContainer?.id
        let searchEngine = searchEngineService.getDefaultSearchEngine(for: containerId)
        let engineName = searchEngine?.name ?? "Google"
        suggestions.append(
            LauncherSuggestion(
                type: .suggestedQuery,
                title: "\(text) - Search with \(engineName)",
                action: { onSubmit(nil) }
            )
        )
    }

    private func requestAutoSuggestions(_ text: String, insertAt: Int) {
        let containerId = tabManager.activeContainer?.id
        debouncer.run {
            let searchEngine = self.searchEngineService.getDefaultSearchEngine(for: containerId)
            if let autoSuggestions = searchEngine?.autoSuggestions {
                let searchSuggestions = await autoSuggestions(text)
                await MainActor.run {
                    var localCount = 0
                    for ss in searchSuggestions {
                        if localCount == 3 { break }
                        let insertIndex = insertAt + localCount
                        let suggestion = LauncherSuggestion(
                            type: .suggestedQuery,
                            title: ss,
                            action: { onSubmit(ss) }
                        )
                        if insertIndex <= suggestions.count {
                            suggestions.insert(suggestion, at: insertIndex)
                        } else {
                            suggestions.append(suggestion)
                        }
                        localCount += 1
                    }
                }
            }
        }
    }

    private func appendHistorySuggestions(_ histories: [History], itemsCount: inout Int) {
        for history in histories {
            if itemsCount >= 5 { break }
            suggestions.append(
                LauncherSuggestion(
                    type: .suggestedLink,
                    title: history.title,
                    url: history.url,
                    faviconURL: history.faviconURL,
                    faviconLocalFile: history.faviconLocalFile,
                    action: {
                        tabManager.openTab(
                            url: history.url,
                            historyManager: historyManager,
                            isPrivate: privacyMode.isPrivate
                        )
                    }
                )
            )
            itemsCount += 1
        }
    }

    private func appendAISuggestionsIfNeeded(_ text: String) {
        guard isAISuitableQuery(text) else { return }
        suggestions.append(createAISuggestion(engineName: .grok, query: text))
        suggestions.append(createAISuggestion(engineName: .chatgpt, query: text))
        suggestions.append(createAISuggestion(engineName: .claude, query: text))
        suggestions.append(createAISuggestion(engineName: .gemini, query: text))
    }

    func executeCommand() {
        if let suggestion =
            suggestions
                .first(where: { $0.id == focusedElement })
        {
            // If user requested to use the current tab (e.g., Cmd+Shift+G),
            // prefer loading the URL in-place instead of opening a new tab.
            if appState.launcherSearchInCurrentTab,
               let url = suggestion.url,
               let activeTab = tabManager.activeTab
            {
                activeTab.loadURL(url.absoluteString)
            } else {
                suggestion.action()
            }
            appState.launcherSearchInCurrentTab = false
            appState.showLauncher = false
        }
    }

    func moveFocusedElement(_ dir: MoveDirection) {
        guard let idx = suggestions.firstIndex(where: { $0.id == focusedElement }) else { return }
        let offset = dir == .up ? -1 : 1
        let newIndex = (idx + offset + suggestions.count) % suggestions.count
        let newSuggestion = suggestions[newIndex]
        focusedElement = newSuggestion.id
        // Explicitly update text field only when user navigates with arrow keys
        updateTextFieldWithSuggestion(newSuggestion)
    }
    
    private func updateTextFieldWithSuggestion(_ suggestion: LauncherSuggestion) {
        // Don't update text field for AI chat suggestions or generic search prompts
        // These have prefixes like "Ask with ChatGPT" or "Search with..." which shouldn't replace user input
        if suggestion.type == .aiChat {
            return // Skip AI chat suggestions - they break the "Press Tab" feature
        }
        
        // Don't update for math results during navigation
        if suggestion.type == .mathResult {
            return
        }
        
        isUpdatingTextFromNavigation = true
        defer {
            // Reset the flag after a brief delay to allow the text update to complete
            DispatchQueue.main.async {
                self.isUpdatingTextFromNavigation = false
            }
        }
        
        switch suggestion.type {
        case .suggestedQuery:
            // Skip alias suggestions (they have showTabShortcut and prefixes like "Ask" or "Search with")
            // These are meant to be selected with Tab, not auto-filled
            if suggestion.showTabShortcut {
                // Check if it's an alias suggestion (starts with "Ask" or "Search with" without a query part)
                if suggestion.title.hasPrefix("Ask ") || 
                   suggestion.title.hasPrefix("Search with ") ||
                   suggestion.title.hasPrefix("Search on ") {
                    return // Skip alias suggestions
                }
            }
            
            // For query suggestions, extract just the query text
            // Title might be like "query text - Search with Google" or just "query text"
            if let dashIndex = suggestion.title.firstIndex(of: "—") {
                let queryText = String(suggestion.title[..<dashIndex]).trimmingCharacters(in: .whitespaces)
                text = queryText
            } else if suggestion.title.contains(" - Search with ") {
                // Handle format like "query - Search with Google"
                if let dashRange = suggestion.title.range(of: " - Search with ") {
                    let queryText = String(suggestion.title[..<dashRange.lowerBound])
                    text = queryText
                } else {
                    text = suggestion.title
                }
            } else if suggestion.title.hasPrefix("Search on") || suggestion.title.hasPrefix("Search with") {
                // Skip updating if it's a generic search prompt without actual query
                return
            } else {
                // For auto-suggestions, title is just the query text
                text = suggestion.title
            }
        case .suggestedLink, .openedTab:
            // For links and tabs, use the URL string
            if let url = suggestion.url {
                text = url.absoluteString
            } else {
                text = suggestion.title
            }
        default:
            // For other types (aiChat, mathResult), we already returned above
            break
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                if match == nil {
                    Image(systemName: getIconName(match: match, text: text))
                        .resizable()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Color(.placeholderTextColor))
                }

                if match != nil {
                    SearchEngineCapsule(
                        text: match?.text ?? "",
                        color: match?.color ?? .blue,
                        foregroundColor: match?.foregroundColor ?? .white,
                        icon: match?.icon ?? "",
                        favicon: match?.favicon,
                        faviconBackgroundColor: match?.faviconBackgroundColor
                    )
                }
                LauncherTextField(
                    text: $text,
                    font: NSFont.systemFont(ofSize: 18, weight: .medium),
                    onTab: {
                        // First check if there's a focused suggestion with tab shortcut
                        if let focusedSuggestion = suggestions.first(where: { $0.id == focusedElement }),
                           focusedSuggestion.showTabShortcut {
                            focusedSuggestion.action()
                        } else {
                            // Fall back to the original tab press handler
                            onTabPress()
                        }
                    },
                    onSubmit: {
                        executeCommand()
                    },
                    onDelete: {
                        if text.isEmpty, match != nil {
                            text = match!.originalAlias
                            match = nil
                            return true
                        }
                        return false
                    },
                    onMoveUp: {
                        moveFocusedElement(.up)
                    },
                    onMoveDown: {
                        moveFocusedElement(.down)
                    },
                    cursorColor: match?.faviconBackgroundColor ?? match?.color
                        ?? (theme.foreground),
                    placeholder: getPlaceholder(match: match)
                )
                .onChange(of: text) { _, _ in
                    searchHandler(text)
                }
                .textFieldStyle(PlainTextFieldStyle())
                .focused(isFocused)
            }
            .animation(nil, value: match?.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)

            if match == nil, !suggestions.isEmpty {
                LauncherSuggestionsView(
                    text: $text,
                    suggestions: $suggestions,
                    focusedElement: $focusedElement
                )
            }
        }
        .padding(8)
        .frame(minWidth: 320, maxWidth: 814, alignment: .leading)
        .background(theme.launcherMainBackground)
        .background(BlurEffectView(material: .popover, blendingMode: .withinWindow))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .inset(by: 0.25)
                .stroke(
                    Color(match?.faviconBackgroundColor ?? match?.color ?? theme.foreground)
                        .opacity(0.15),
                    lineWidth: 0.5
                )
        )
        .shadow(
            color: Color.black.opacity(0.1),
            radius: 40, x: 0, y: 24
        )
    }

    private func getPlaceholder(match: Match?) -> String {
        if match == nil {
            return "Search the web or enter URL..."
        }

        // Find the search engine by name to get its isAIChat property
        if let engine = searchEngineService.getSearchEngine(byName: match!.text) {
            let prefix = engine.isAIChat ? "Ask" : "Search on"
            return "\(prefix) \(engine.name)"
        }

        // Fallback (should rarely happen)
        return "Search on \(match!.text)"
    }

    private func getIconName(match: Match?, text: String) -> String {
        if match != nil {
            return "magnifyingglass"
        }
        return isValidURL(text) ? "globe" : "magnifyingglass"
    }
}

func isAISuitableQuery(_ query: String) -> Bool {
    let lowercased = query.lowercased()

    // AI-suited queries: open-ended, creative, opinion-based, etc.
    let aiKeywords = [
        #"^(who|when|where|what|how|why)\b.*\?$"#,  // e.g. "When was Apple founded?"
        #"^\d{4}"#,
        "summarize", "rewrite", "explain", "code", "how to", "generate",
        "idea", "opinion", "feedback", "story", "joke", "email", "draft",
        "translate", "compare", "alternatives", "improve", "fix", "suggest"
    ]

    for keyword in aiKeywords {
        if lowercased.contains(keyword) {
            return true
        }
    }

    return false
}
