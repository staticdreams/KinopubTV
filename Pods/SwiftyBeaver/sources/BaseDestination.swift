//
//  BaseDestination.swift
//  SwiftyBeaver
//
//  Created by Sebastian Kreutzberger (Twitter @skreutzb) on 05.12.15.
//  Copyright © 2015 Sebastian Kreutzberger
//  Some rights reserved: http://opensource.org/licenses/MIT
//

import Foundation

// store operating system / platform
#if os(iOS)
let OS = "iOS"
#elseif os(OSX)
let OS = "OSX"
#elseif os(watchOS)
let OS = "watchOS"
#elseif os(tvOS)
let OS = "tvOS"
#elseif os(Linux)
let OS = "Linux"
#elseif os(FreeBSD)
let OS = "FreeBSD"
#elseif os(Windows)
let OS = "Windows"
#elseif os(Android)
let OS = "Android"
#else
let OS = "Unknown"
#endif


/// destination which all others inherit from. do not directly use
open class BaseDestination: Hashable, Equatable {

    /// output format pattern, see documentation for syntax
    open var format = "$Dyyyy-MM-dd HH:mm:ss.SSS$d $N.$F:$l $L: $M"

    /// runs in own serial background thread for better performance
    open var asynchronously = true

    /// do not log any message which has a lower level than this one
    open var minLevel = SwiftyBeaver.Level.Verbose {
        didSet {
            // Craft a new level filter and add it
            self.addFilter(filter: Filters.Level.atLeast(level: minLevel))
        }
    }

    /// set custom log level words for each level
    open var levelString = LevelString()

    /// set custom log level colors for each level
    open var levelColor = LevelColor()

    public struct LevelString {
        public var Verbose = "VERBOSE"
        public var Debug = "DEBUG"
        public var Info = "INFO"
        public var Warning = "WARNING"
        public var Error = "ERROR"
    }

    // For a colored log level word in a logged line
    // empty on default
    public struct LevelColor {
        public var Verbose = ""     // silver
        public var Debug = ""       // green
        public var Info = ""        // blue
        public var Warning = ""     // yellow
        public var Error = ""       // red
    }

    var reset = ""
    var escape = ""

    var filters = [FilterType]()
    let formatter = DateFormatter()

    // each destination class must have an own hashValue Int
    lazy public var hashValue: Int = self.defaultHashValue
    open var defaultHashValue: Int {return 0}

    // each destination instance must have an own serial queue to ensure serial output
    // GCD gives it a prioritization between User Initiated and Utility
    var queue: DispatchQueue? //dispatch_queue_t?

    public init() {
        let uuid = NSUUID().uuidString
        let queueLabel = "swiftybeaver-queue-" + uuid
        queue = DispatchQueue(label: queueLabel, target: queue)
        addFilter(filter: Filters.Level.atLeast(level: minLevel))
    }

    /// send / store the formatted log message to the destination
    /// returns the formatted log message for processing by inheriting method
    /// and for unit tests (nil if error)
    open func send(_ level: SwiftyBeaver.Level, msg: String, thread: String,
        file: String, function: String, line: Int) -> String? {

        return formatMessage(format, level: level, msg: msg, thread: thread,
                             file: file, function: function, line: line)
    }


    ////////////////////////////////
    // MARK: Format
    ////////////////////////////////

    /// returns the log message based on the format pattern
    func formatMessage(_ format: String, level: SwiftyBeaver.Level, msg: String, thread: String,
                file: String, function: String, line: Int) -> String {

        var text = ""
        let phrases: [String] = format.components(separatedBy: "$")

        for phrase in phrases {
            if !phrase.isEmpty {
                let firstChar = phrase[phrase.startIndex]
                let rangeAfterFirstChar = phrase.index(phrase.startIndex, offsetBy: 1)..<phrase.endIndex
                let remainingPhrase = phrase[rangeAfterFirstChar]

                switch firstChar {
                case "L":
                    text += levelWord(level) + remainingPhrase
                case "M":
                    text += msg + remainingPhrase
                case "m":
                    // json-encoded message
                    let dict = ["message": msg]
                    let jsonString = jsonStringFromDict(dict)
                    text += jsonStringValue(jsonString, key: "message") + remainingPhrase
                case "T":
                    text += thread + remainingPhrase
                case "N":
                    // name of file without suffix
                    text += fileNameWithoutSuffix(file) + remainingPhrase
                case "n":
                    // name of file with suffix
                    text += fileNameOfFile(file) + remainingPhrase
                case "F":
                    text += function + remainingPhrase
                case "l":
                    text += String(line) + remainingPhrase
                case "D":
                    // start of datetime format
                    text += formatDate(remainingPhrase)
                case "d":
                    text += remainingPhrase
                case "C":
                    // color code ("" on default)
                    text += escape + colorForLevel(level) + remainingPhrase
                case "c":
                    text += reset + remainingPhrase
                default:
                    text += phrase
                }
            }
        }
        return text
    }

    /// returns the string of a level
    func levelWord(_ level: SwiftyBeaver.Level) -> String {

        var str = ""

        switch level {
        case SwiftyBeaver.Level.Debug:
            str = levelString.Debug

        case SwiftyBeaver.Level.Info:
            str = levelString.Info

        case SwiftyBeaver.Level.Warning:
            str = levelString.Warning

        case SwiftyBeaver.Level.Error:
            str = levelString.Error

        default:
            // Verbose is default
            str = levelString.Verbose
        }
        return str
    }

    /// returns color string for level
    func colorForLevel(_ level: SwiftyBeaver.Level) -> String {
        var color = ""

        switch level {
        case SwiftyBeaver.Level.Debug:
            color = levelColor.Debug

        case SwiftyBeaver.Level.Info:
            color = levelColor.Info

        case SwiftyBeaver.Level.Warning:
            color = levelColor.Warning

        case SwiftyBeaver.Level.Error:
            color = levelColor.Error

        default:
            color = levelColor.Verbose
        }
        return color
    }

    /// returns the filename of a path
    func fileNameOfFile(_ file: String) -> String {
        let fileParts = file.components(separatedBy: "/")
        if let lastPart = fileParts.last {
            return lastPart
        }
        return ""
    }

    /// returns the filename without suffix (= file ending) of a path
    func fileNameWithoutSuffix(_ file: String) -> String {
        let fileName = fileNameOfFile(file)

        if !fileName.isEmpty {
            let fileNameParts = fileName.components(separatedBy: ".")
            if let firstPart = fileNameParts.first {
                return firstPart
            }
        }
        return ""
    }

    /// returns a formatted date string
    func formatDate(_ dateFormat: String) -> String {
        //formatter.timeZone = NSTimeZone(abbreviation: "UTC")
        formatter.dateFormat = dateFormat
        let dateStr = formatter.string(from: NSDate() as Date)
        return dateStr
    }

    /// returns the json-encoded string value
    /// after it was encoded by jsonStringFromDict
    func jsonStringValue(_ jsonString: String?, key: String) -> String {
        guard let str = jsonString else {
            return ""
        }

        // remove the leading {"key":" from the json string and the final }
        let offset = key.characters.count + 5
        let endIndex = str.index(str.startIndex,
                                 offsetBy: str.characters.count - 2)
        let range = str.index(str.startIndex, offsetBy: offset)..<endIndex
        return str[range]
    }

    /// turns dict into JSON-encoded string
    func jsonStringFromDict(_ dict: [String: Any]) -> String? {
        var jsonString: String?

        // try to create JSON string
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [])
            if let str = NSString(data: jsonData,
                                  encoding: String.Encoding.utf8.rawValue) as? String {
                jsonString = str
            }
        } catch let error as NSError {
            print("SwiftyBeaver could not create JSON from dict. \(error)")
        }
        return jsonString
    }

    ////////////////////////////////
    // MARK: Filters
    ////////////////////////////////

    /// Add a filter that determines whether or not a particular message will be logged to this destination
    public func addFilter(filter: FilterType) {
        // There can only be a maximum of one level filter in the filters collection.
        // When one is set, remove any others if there are any and then add
        let isNewLevelFilter = self.getFiltersTargeting(target: Filter.TargetType.LogLevel(minLevel),
                                                        fromFilters: [filter]).count == 1
        if isNewLevelFilter {
            let levelFilters = self.getFiltersTargeting(target: Filter.TargetType.LogLevel(minLevel),
                                                        fromFilters: self.filters)
            levelFilters.forEach {
                filter in
                self.removeFilter(filter: filter)
            }
        }
        filters.append(filter)
    }

    /// Remove a filter from the list of filters
    public func removeFilter(filter: FilterType) {
        let index = filters.index {
            return ObjectIdentifier($0) == ObjectIdentifier(filter)
        }

        guard let filterIndex = index else {
            return
        }

        filters.remove(at: filterIndex)
    }

    /// Answer whether the destination has any message filters
    /// returns boolean and is used to decide whether to resolve the message before invoking shouldLevelBeLogged
    func hasMessageFilters() -> Bool {
        return !getFiltersTargeting(target: Filter.TargetType.Message(.Equals([], true)),
                                    fromFilters: self.filters).isEmpty
    }

    /// checks if level is at least minLevel or if a minLevel filter for that path does exist
    /// returns boolean and can be used to decide if a message should be logged or not
    func shouldLevelBeLogged(level: SwiftyBeaver.Level, file: String, function: String, message: String? = nil) -> Bool {
        return passesAllRequiredFilters(level: level, file: file, function: function, message: message) &&
            passesAtLeastOneNonRequiredFilter(level: level, file: file, function: function, message: message)
    }

    func getFiltersTargeting(target: Filter.TargetType, fromFilters: [FilterType]) -> [FilterType] {
        return fromFilters.filter {
            filter in
            return filter.getTarget() == target
        }
    }

    func passesAllRequiredFilters(level: SwiftyBeaver.Level, file: String, function: String, message: String?) -> Bool {
        let requiredFilters = self.filters.filter {
            filter in
            return filter.isRequired()
        }

        return applyFilters(targetFilters: requiredFilters, level: level, file: file,
                            function: function, message: message) == requiredFilters.count
    }

    func passesAtLeastOneNonRequiredFilter(level: SwiftyBeaver.Level,
                                           file: String, function: String, message: String?) -> Bool {
        let nonRequiredFilters = self.filters.filter {
            filter in
            return !filter.isRequired()
        }

        return nonRequiredFilters.isEmpty ||
            applyFilters(targetFilters: nonRequiredFilters, level: level, file: file,
                         function: function, message: message) > 0
    }

    func passesLogLevelFilters(level: SwiftyBeaver.Level) -> Bool {
        let logLevelFilters = getFiltersTargeting(target: Filter.TargetType.LogLevel(level), fromFilters: self.filters)
        return logLevelFilters.filter {
            filter in

            return filter.apply(value: level.rawValue)
        }.count == logLevelFilters.count
    }

    func applyFilters(targetFilters: [FilterType], level: SwiftyBeaver.Level,
                      file: String, function: String, message: String?) -> Int {
        return targetFilters.filter {
            filter in

            let passes: Bool

            switch filter.getTarget() {
            case .LogLevel(_):
                passes = filter.apply(value: level.rawValue)

            case .Path(_):
                passes = filter.apply(value: file)

            case .Function(_):
                passes = filter.apply(value: function)

            case .Message(_):
                guard let message = message else {
                    return false
                }

                passes = filter.apply(value: message)
            }

            return passes
        }.count
    }

  /**
    Triggered by main flush() method on each destination. Runs in background thread.
   Use for destinations that buffer log items, implement this function to flush those
   buffers to their final destination (web server...)
   */
  func flush() {
    // no implementation in base destination needed
  }
}

public func == (lhs: BaseDestination, rhs: BaseDestination) -> Bool {
    return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
}