//
//  Table+Aggregation.swift
//  DatabaseDriver
//
//  Created by: tomieq on 29/05/2026
//

extension Table {
    public var count: SQLScalarQuery<Int> {
        SelectQuery(table: self).count
    }

    public func select<Value>(_ column: SQLAggregateExpression<Value>) -> SQLScalarQuery<Value> {
        SelectQuery(table: self).select(column)
    }
}