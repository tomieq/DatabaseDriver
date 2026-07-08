//
//  SelectQuery+Aggregation.swift
//  DatabaseDriver
//
//  Created by: tomieq on 29/05/2026
//

extension SelectQuery {
    public var count: SQLScalarQuery<Int> {
        self.aggregate("count(*)") { value in
            try decodeRequiredScalar(Int.self, from: value)
        }
    }

    public func select<Value>(_ column: SQLAggregateExpression<Value>) -> SQLScalarQuery<Value> {
        self.aggregate(column.sql, decodeScalar: column.decodeScalar)
    }

    private func aggregate<Value>(_ sql: String, decodeScalar: @escaping @Sendable (DatabaseValue?) throws -> Value) -> SQLScalarQuery<Value> {
        SQLScalarQuery(
            query: SelectQuery(
                table: self.table,
                columns: [sql],
                predicate: self.predicate,
                groupings: self.groupings,
                orderings: self.orderings,
                limitValue: self.limitValue,
                offsetValue: self.offsetValue
            ),
            decodeScalar: decodeScalar
        )
    }
}