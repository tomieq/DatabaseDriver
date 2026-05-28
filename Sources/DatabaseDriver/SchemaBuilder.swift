import Foundation

public enum SQLColumnType: Sendable, Equatable {
    case bool
    case int
    case unsignedInt
    case bigInt
    case unsignedBigInt
    case double
    case decimal(precision: Int, scale: Int)
    case varchar(Int)
    case text
    case blob
    case date
    case time(fractionalSecondsPrecision: Int? = nil)
    case dateTime(fractionalSecondsPrecision: Int? = nil)
    case custom(String)

    public var sql: String {
        switch self {
        case .bool: return "BOOL"
        case .int: return "INT"
        case .unsignedInt: return "INT UNSIGNED"
        case .bigInt: return "BIGINT"
        case .unsignedBigInt: return "BIGINT UNSIGNED"
        case .double: return "DOUBLE"
        case let .decimal(precision, scale): return "DECIMAL(\(precision), \(scale))"
        case let .varchar(length): return "VARCHAR(\(length))"
        case .text: return "TEXT"
        case .blob: return "BLOB"
        case .date: return "DATE"
        case let .time(precision): return self.temporalSQL(name: "TIME", precision: precision)
        case let .dateTime(precision): return self.temporalSQL(name: "DATETIME", precision: precision)
        case let .custom(sql): return sql
        }
    }

    private func temporalSQL(name: String, precision: Int?) -> String {
        if let precision { return "\(name)(\(precision))" }
        return name
    }
}

public enum SQLPrimaryKey: Sendable, Equatable, ExpressibleByBooleanLiteral {
    case none
    case primaryKey
    case autoIncrement

    public init(booleanLiteral value: Bool) {
        self = value ? .primaryKey : .none
    }

    var sql: String? {
        switch self {
        case .none: return nil
        case .primaryKey: return "PRIMARY KEY"
        case .autoIncrement: return "PRIMARY KEY AUTO_INCREMENT"
        }
    }
}

public enum SQLForeignKeyAction: String, Sendable, Equatable {
    case cascade = "CASCADE"
    case restrict = "RESTRICT"
    case setNull = "SET NULL"
    case noAction = "NO ACTION"
}

public protocol DatabaseSchemaRepresentable {
    init()
}

public struct CreateTableQuery: SQLStatement {
    public let table: Table
    public let temporary: Bool
    public let ifNotExists: Bool
    public let definitions: [String]

    public var sql: String {
        var parts = ["CREATE"]
        if self.temporary { parts.append("TEMPORARY") }
        parts.append("TABLE")
        if self.ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(self.table.sql)
        parts.append("(\(self.definitions.joined(separator: ", ")))")
        return parts.joined(separator: " ")
    }
}

public struct DropTableQuery: SQLStatement {
    public let table: Table
    public let ifExists: Bool

    public var sql: String {
        "DROP TABLE " + (self.ifExists ? "IF EXISTS " : "") + self.table.sql
    }
}

public struct CreateIndexQuery: SQLStatement {
    public let table: Table
    public let name: String
    public let columns: [String]
    public let unique: Bool
    public let ifNotExists: Bool

    public var sql: String {
        var parts = ["CREATE"]
        if self.unique { parts.append("UNIQUE") }
        parts.append("INDEX")
        if self.ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(SQLBuilder.quoteIdentifier(self.name))
        parts.append("ON")
        parts.append(self.table.sql)
        parts.append("(\(self.columns.joined(separator: ", ")))")
        return parts.joined(separator: " ")
    }
}

public struct DropIndexQuery: SQLStatement {
    public let table: Table
    public let name: String
    public let ifExists: Bool

    public var sql: String {
        "DROP INDEX " + (self.ifExists ? "IF EXISTS " : "") + SQLBuilder.quoteIdentifier(self.name) + " ON " + self.table.sql
    }
}

public final class TableDefinition {
    private let tableName: String
    private var definitions: [String] = []

    fileprivate init(tableName: String) {
        self.tableName = tableName
    }

    public func column<Value: DatabaseExpressionValue>(
        _ expression: Expression<Value>,
        type: SQLColumnType? = nil,
        primaryKey: SQLPrimaryKey = false,
        notNull: Bool = true,
        unique: Bool = false,
        defaultValue: Value? = nil,
        check: SQLPredicate? = nil,
        references: (table: Table, column: any SQLSelectable)? = nil,
        delete: SQLForeignKeyAction? = nil,
        update: SQLForeignKeyAction? = nil
    ) {
        self.addColumn(
            name: expression.name,
            type: type ?? SQLColumnType.inferred(Value.self),
            primaryKey: primaryKey,
            notNull: notNull || primaryKey != .none,
            unique: unique,
            defaultValue: defaultValue?.databaseValue,
            check: check,
            references: references,
            delete: delete,
            update: update
        )
    }

    public func column<Value: DatabaseExpressionValue>(
        _ expression: Expression<Value?>,
        type: SQLColumnType? = nil,
        primaryKey: SQLPrimaryKey = false,
        notNull: Bool = false,
        unique: Bool = false,
        defaultValue: Value? = nil,
        check: SQLPredicate? = nil,
        references: (table: Table, column: any SQLSelectable)? = nil,
        delete: SQLForeignKeyAction? = nil,
        update: SQLForeignKeyAction? = nil
    ) {
        self.addColumn(
            name: expression.name,
            type: type ?? SQLColumnType.inferred(Value.self),
            primaryKey: primaryKey,
            notNull: notNull || primaryKey != .none,
            unique: unique,
            defaultValue: defaultValue?.databaseValue,
            check: check,
            references: references,
            delete: delete,
            update: update
        )
    }

    public func primaryKey(_ columns: any SQLSelectable...) {
        self.definitions.append("PRIMARY KEY (\(columns.map { $0.ddlColumnSQL }.joined(separator: ", ")))")
    }

    public func unique(_ columns: any SQLSelectable...) {
        self.definitions.append("UNIQUE (\(columns.map { $0.ddlColumnSQL }.joined(separator: ", ")))")
    }

    public func check(_ predicate: SQLPredicate) {
        self.definitions.append("CHECK (\(self.schemaSQL(predicate.sql)))")
    }

    public func foreignKey(_ columns: [any SQLSelectable], references table: Table, _ referencedColumns: [any SQLSelectable], delete: SQLForeignKeyAction? = nil, update: SQLForeignKeyAction? = nil) {
        var sql = "FOREIGN KEY (\(columns.map { $0.ddlColumnSQL }.joined(separator: ", "))) REFERENCES \(table.sql) (\(referencedColumns.map { $0.ddlColumnSQL }.joined(separator: ", ")))"
        if let delete { sql += " ON DELETE \(delete.rawValue)" }
        if let update { sql += " ON UPDATE \(update.rawValue)" }
        self.definitions.append(sql)
    }

    fileprivate func build() -> [String] {
        self.definitions
    }

    private func addColumn(
        name: String,
        type: SQLColumnType,
        primaryKey: SQLPrimaryKey,
        notNull: Bool,
        unique: Bool,
        defaultValue: DatabaseValue?,
        check: SQLPredicate?,
        references: (table: Table, column: any SQLSelectable)?,
        delete: SQLForeignKeyAction?,
        update: SQLForeignKeyAction?
    ) {
        var parts = [SQLBuilder.quoteIdentifier(name), type.sql]
        if let primaryKeySQL = primaryKey.sql { parts.append(primaryKeySQL) }
        if notNull { parts.append("NOT NULL") }
        if unique { parts.append("UNIQUE") }
        if let defaultValue { parts.append("DEFAULT " + SQLBuilder.literal(defaultValue)) }
        if let check { parts.append("CHECK (\(self.schemaSQL(check.sql)))") }
        if let references {
            parts.append("REFERENCES")
            parts.append(references.table.sql)
            parts.append("(\(references.column.ddlColumnSQL))")
            if let delete { parts.append("ON DELETE \(delete.rawValue)") }
            if let update { parts.append("ON UPDATE \(update.rawValue)") }
        }
        self.definitions.append(parts.joined(separator: " "))
    }

    private func schemaSQL(_ sql: String) -> String {
        sql.replacingOccurrences(of: SQLBuilder.quoteIdentifier(self.tableName) + ".", with: "")
    }
}

extension Table {
    public func create(temporary: Bool = false, ifNotExists: Bool = false, _ define: (TableDefinition) -> Void) -> CreateTableQuery {
        let definition = TableDefinition(tableName: self.name)
        define(definition)
        return CreateTableQuery(table: self, temporary: temporary, ifNotExists: ifNotExists, definitions: definition.build())
    }

    public func create<Value: DatabaseSchemaRepresentable>(from type: Value.Type, temporary: Bool = false, ifNotExists: Bool = false) -> CreateTableQuery {
        self.create(from: Value(), temporary: temporary, ifNotExists: ifNotExists)
    }

    public func create<Value: DatabaseSchemaRepresentable>(from type: Value.Type, temporary: Bool = false, ifNotExists: Bool = false, _ define: (TableDefinition) -> Void) -> CreateTableQuery {
        self.create(from: Value(), temporary: temporary, ifNotExists: ifNotExists, define)
    }

    public func create<Value>(from sample: Value, temporary: Bool = false, ifNotExists: Bool = false) -> CreateTableQuery {
        let definition = TableDefinition(tableName: self.name)
        definition.columns(from: sample)
        return CreateTableQuery(table: self, temporary: temporary, ifNotExists: ifNotExists, definitions: definition.build())
    }

    public func create<Value>(from sample: Value, temporary: Bool = false, ifNotExists: Bool = false, _ define: (TableDefinition) -> Void) -> CreateTableQuery {
        let definition = TableDefinition(tableName: self.name)
        definition.columns(from: sample)
        define(definition)
        return CreateTableQuery(table: self, temporary: temporary, ifNotExists: ifNotExists, definitions: definition.build())
    }

    public func drop(ifExists: Bool = false) -> DropTableQuery {
        DropTableQuery(table: self, ifExists: ifExists)
    }

    public func createIndex(_ columns: any SQLSelectable..., named name: String? = nil, unique: Bool = false, ifNotExists: Bool = false) -> CreateIndexQuery {
        self.createIndex(columns, named: name, unique: unique, ifNotExists: ifNotExists)
    }

    public func createIndex(_ columns: [any SQLSelectable], named name: String? = nil, unique: Bool = false, ifNotExists: Bool = false) -> CreateIndexQuery {
        CreateIndexQuery(table: self, name: name ?? self.generatedIndexName(columns: columns), columns: columns.map { $0.ddlColumnSQL }, unique: unique, ifNotExists: ifNotExists)
    }

    public func dropIndex(_ columns: any SQLSelectable..., named name: String? = nil, ifExists: Bool = false) -> DropIndexQuery {
        self.dropIndex(columns, named: name, ifExists: ifExists)
    }

    public func dropIndex(_ columns: [any SQLSelectable], named name: String? = nil, ifExists: Bool = false) -> DropIndexQuery {
        DropIndexQuery(table: self, name: name ?? self.generatedIndexName(columns: columns), ifExists: ifExists)
    }

    private func generatedIndexName(columns: [any SQLSelectable]) -> String {
        let columnNames = columns.map { column in
            column.ddlColumnName
                .replacingOccurrences(of: "`", with: "")
                .replacingOccurrences(of: ".", with: "_")
                .replacingOccurrences(of: " ", with: "_")
        }.joined(separator: "_and_")
        return "index_\(self.name)_on_\(columnNames)"
    }
}

extension TableDefinition {
    public func column(named name: String, type: SQLColumnType, primaryKey: SQLPrimaryKey = false, notNull: Bool = true, unique: Bool = false, defaultValue: DatabaseValue? = nil, check: SQLPredicate? = nil) {
        self.addColumn(
            name: name,
            type: type,
            primaryKey: primaryKey,
            notNull: notNull || primaryKey != .none,
            unique: unique,
            defaultValue: defaultValue,
            check: check,
            references: nil,
            delete: nil,
            update: nil
        )
    }

    public func columns<Value>(from sample: Value) {
        self.addColumns(from: Mirror(reflecting: sample))
    }

    private func addColumns(from mirror: Mirror) {
        if let superclassMirror = mirror.superclassMirror {
            self.addColumns(from: superclassMirror)
        }
        for child in mirror.children {
            guard let name = child.label else { continue }
            let reflectedType = SQLColumnType.reflected(child.value)
            self.addColumn(
                name: name,
                type: reflectedType.type,
                primaryKey: .none,
                notNull: !reflectedType.isOptional,
                unique: false,
                defaultValue: nil,
                check: nil,
                references: nil,
                delete: nil,
                update: nil
            )
        }
    }
}

private protocol SQLNamedSelectable {
    var ddlColumnName: String { get }
}

extension Expression: SQLNamedSelectable {
    fileprivate var ddlColumnName: String { self.name }
}

private extension SQLSelectable {
    var ddlColumnName: String {
        (self as? SQLNamedSelectable)?.ddlColumnName ?? self.sql
    }

    var ddlColumnSQL: String {
        SQLBuilder.quoteIdentifier(self.ddlColumnName)
    }
}

private extension SQLColumnType {
    static func inferred<Value>(_ type: Value.Type) -> SQLColumnType {
        switch type {
        case is Bool.Type: return .bool
        case is Int.Type, is Int8.Type, is Int16.Type, is Int32.Type: return .int
        case is UInt.Type, is UInt8.Type, is UInt16.Type, is UInt32.Type: return .unsignedInt
        case is Int64.Type: return .bigInt
        case is UInt64.Type: return .unsignedBigInt
        case is Float.Type, is Double.Type: return .double
        case is Decimal.Type: return .decimal(precision: 65, scale: 30)
        case is String.Type: return .text
        case is Data.Type: return .blob
        case is DatabaseDate.Type: return .date
        case is DatabaseTime.Type: return .time(fractionalSecondsPrecision: 6)
        case is DatabaseDateTime.Type: return .dateTime(fractionalSecondsPrecision: 6)
        default: return .text
        }
    }

    static func reflected(_ value: Any) -> (type: SQLColumnType, isOptional: Bool) {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            if let wrapped = mirror.children.first?.value {
                return (self.reflectedNonOptional(wrapped), true)
            }
            return (self.reflectedNilOptional(value), true)
        }
        return (self.reflectedNonOptional(value), false)
    }

    private static func reflectedNonOptional(_ value: Any) -> SQLColumnType {
        switch value {
        case is Bool: return .bool
        case is Int, is Int8, is Int16, is Int32: return .int
        case is UInt, is UInt8, is UInt16, is UInt32: return .unsignedInt
        case is Int64: return .bigInt
        case is UInt64: return .unsignedBigInt
        case is Float, is Double: return .double
        case is Decimal: return .decimal(precision: 65, scale: 30)
        case is String: return .text
        case is Data: return .blob
        case is DatabaseDate: return .date
        case is DatabaseTime: return .time(fractionalSecondsPrecision: 6)
        case is DatabaseDateTime: return .dateTime(fractionalSecondsPrecision: 6)
        default: return .text
        }
    }

    private static func reflectedNilOptional(_ value: Any) -> SQLColumnType {
        let typeName = String(reflecting: Swift.type(of: value))
        if typeName.contains("Bool") { return .bool }
        if typeName.contains("Int64") { return .bigInt }
        if typeName.contains("UInt64") { return .unsignedBigInt }
        if typeName.contains("UInt") { return .unsignedInt }
        if typeName.contains("Int") { return .int }
        if typeName.contains("Float") || typeName.contains("Double") { return .double }
        if typeName.contains("Decimal") { return .decimal(precision: 65, scale: 30) }
        if typeName.contains("String") { return .text }
        if typeName.contains("Data") { return .blob }
        if typeName.contains("DatabaseDateTime") { return .dateTime(fractionalSecondsPrecision: 6) }
        if typeName.contains("DatabaseDate") { return .date }
        if typeName.contains("DatabaseTime") { return .time(fractionalSecondsPrecision: 6) }
        return .text
    }
}